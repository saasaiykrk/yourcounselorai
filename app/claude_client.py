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

import json

from .pipeline import ModelResult

MAX_TOOL_ROUNDS = 8
# Output cap per call, thinking included. A guided report is ~8k tokens of text plus thinking; at 16k
# one was cut off mid-table, failed the inspector and had to be written (and paid for) twice.
# A higher cap costs nothing unless the tokens are actually generated.
REPLY_MAX_TOKENS = 32000


class AnthropicClient:
    def __init__(self, api_key: str, model: str, max_tokens: int = REPLY_MAX_TOKENS):
        import anthropic  # imported lazily so unit tests don't need the SDK
        self._client = anthropic.Anthropic(api_key=api_key, max_retries=2, timeout=300)
        self.model, self.max_tokens = model, max_tokens

    def run(self, system: str | list[str], messages: list[dict], tools: list[dict], tool_handler) -> ModelResult:
        convo = list(messages)
        texts: list[str] = []
        usage_total: dict[str, int] = {}
        calls: list[dict] = []
        for _ in range(MAX_TOOL_ROUNDS):
            with self._client.messages.stream(
                model=self.model,
                max_tokens=self.max_tokens,
                system=_system_blocks(system),
                tools=tools,
                messages=convo,
            ) as stream:
                msg = stream.get_final_message()
            for k, v in (msg.usage.model_dump() if hasattr(msg.usage, "model_dump") else {}).items():
                if isinstance(v, int):
                    usage_total[k] = usage_total.get(k, 0) + v
            if msg.stop_reason == "max_tokens":
                # Counted with the usage (turns.usage) so cut-off replies show up in the cost figures.
                usage_total["max_tokens_stops"] = usage_total.get("max_tokens_stops", 0) + 1
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

    def run_structured(self, system: str, user: str, schema: dict, max_tokens: int = 2000) -> tuple[dict | None, dict]:
        """One short call that must return JSON matching `schema` (guided-consultation intake).
        No tools, low effort. Returns (None, usage) if the model declined or the JSON is unusable."""
        msg = self._client.messages.create(
            model=self.model,
            max_tokens=max_tokens,
            system=_system_blocks(system),
            messages=[{"role": "user", "content": user}],
            output_config={"effort": "low", "format": {"type": "json_schema", "schema": schema}},
        )
        usage = {k: v for k, v in (msg.usage.model_dump() if hasattr(msg.usage, "model_dump") else {}).items()
                 if isinstance(v, int)}
        if msg.stop_reason in ("refusal", "max_tokens"):
            return None, usage
        text = "".join(b.text for b in msg.content if b.type == "text")
        try:
            out = json.loads(text)
        except ValueError:
            return None, usage
        return (out if isinstance(out, dict) else None), usage


def _system_blocks(system: str | list[str]) -> list[dict]:
    """Each part is cached separately, so the skill prompt shared by both flows is reused
    when a consultation report adds its own part after it (at most 4 parts)."""
    parts = [system] if isinstance(system, str) else list(system)
    return [{"type": "text", "text": p, "cache_control": {"type": "ephemeral"}} for p in parts[:4]]
