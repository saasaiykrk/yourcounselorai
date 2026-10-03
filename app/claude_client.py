"""
Anthropic Messages API client with a small tool loop.

* Model is PINNED via CLAUDE_MODEL. Changing it = re-run the eval suite and get
  clinician sign-off before deploy (CLAUDE.md, rule 3).
* The system prompt (~34k tokens) is marked for prompt caching, so repeat turns
  pay the cache-read rate for it.
* Streams internally (long Mode A replies) but returns only the final text —
  nothing reaches the phone until the inspector has passed it.

⚠ Not run against the live API from this repo yet (no key in the build
environment). Day 2 task: smoke-test with a real key. The tool loop and refusal
handling are covered by tests/test_claude_client.py against a fake SDK.
"""
from __future__ import annotations

from .pipeline import ModelResult

MAX_TOOL_ROUNDS = 8


class AnthropicClient:
    def __init__(self, api_key: str, model: str, max_tokens: int = 16000):
        import anthropic  # imported lazily so unit tests don't need the SDK
        self._client = anthropic.Anthropic(api_key=api_key, max_retries=2, timeout=300)
        self.model, self.max_tokens = model, max_tokens

    def run(self, system: str, messages: list[dict], tools: list[dict], tool_handler) -> ModelResult:
        convo = list(messages)
        texts: list[str] = []
        usage_total: dict[str, int] = {}
        calls: list[dict] = []
        for _ in range(MAX_TOOL_ROUNDS):
            with self._client.messages.stream(
                model=self.model,
                max_tokens=self.max_tokens,
                system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
                tools=tools,
                messages=convo,
            ) as stream:
                msg = stream.get_final_message()
            for k, v in (msg.usage.model_dump() if hasattr(msg.usage, "model_dump") else {}).items():
                if isinstance(v, int):
                    usage_total[k] = usage_total.get(k, 0) + v
            if msg.stop_reason == "refusal":
                # Declined by the model's safety classifier: deliver nothing. The empty
                # text fails the inspector, so the turn is retried once, then held back.
                texts.append("")
                break
            tool_uses = [b for b in msg.content if b.type == "tool_use"]
            round_text = "".join(b.text for b in msg.content if b.type == "text")
            if not tool_uses:
                texts.append(round_text)
                break
            # Send the assistant turn back exactly as received, thinking blocks included:
            # the model needs its reasoning for the tool round, and the API rejects or
            # drops thinking from a history that was edited.
            convo.append({"role": "assistant", "content": msg.content})
            results = []
            for tu in tool_uses:
                out = tool_handler(tu.name, tu.input or {})
                calls.append({"name": tu.name, "input": tu.input})
                results.append({"type": "tool_result", "tool_use_id": tu.id, "content": out})
            convo.append({"role": "user", "content": results})
        # The contract line must be the very first thing in the reply; text emitted
        # before a tool call is preamble, so only the final round's text is used.
        return ModelResult(text=texts[-1] if texts else "", model=self.model, usage=usage_total, tool_calls=calls)
