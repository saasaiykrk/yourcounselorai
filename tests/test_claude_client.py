"""AnthropicClient's tool loop against a fake SDK (stdlib only, no key, no network)."""
import unittest
from types import SimpleNamespace as NS

from app.claude_client import AnthropicClient


def _block(type_, **kw):
    return NS(type=type_, **kw)


class _FakeStream:
    def __init__(self, msg):
        self._msg = msg

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def get_final_message(self):
        return self._msg


class _FakeMessages:
    def __init__(self, replies):
        self._replies = list(replies)
        self.requests = []

    def stream(self, **kwargs):
        # Copy the list: the client keeps appending to the same conversation.
        self.requests.append({**kwargs, "messages": list(kwargs["messages"])})
        return _FakeStream(self._replies.pop(0))


def _client(replies):
    c = object.__new__(AnthropicClient)  # skip __init__: no SDK import, no key
    c._client = NS(messages=_FakeMessages(replies))
    c.model, c.max_tokens = "claude-opus-5-5", 16000
    return c


def _msg(content, stop_reason):
    return NS(content=content, stop_reason=stop_reason, usage=NS())


class ToolLoopTests(unittest.TestCase):
    def test_tool_round_replays_assistant_turn_unchanged_including_thinking(self):
        thinking = _block("thinking", thinking="", signature="sig-1")
        tool_use = _block("tool_use", id="tu1", name="lookup_card", input={"q": "panic"})
        first = _msg([thinking, tool_use], "tool_use")
        final = _msg([_block("thinking", thinking="", signature="sig-2"),
                      _block("text", text="<!-- yc -->\n### 1. Audit")], "end_turn")
        c = _client([first, final])

        result = c.run("SYSTEM", [{"role": "user", "content": "case"}], [], lambda n, i: "card text")

        second_request = c._client.messages.requests[1]["messages"]
        self.assertEqual(second_request[1], {"role": "assistant", "content": [thinking, tool_use]},
                         "thinking blocks must go back exactly as received, in order")
        self.assertEqual(second_request[2]["content"][0]["tool_use_id"], "tu1")
        self.assertEqual(result.text, "<!-- yc -->\n### 1. Audit")

    def test_refusal_returns_no_text_so_the_inspector_holds_it_back(self):
        c = _client([_msg([_block("text", text="partial answer")], "refusal")])
        result = c.run("SYSTEM", [{"role": "user", "content": "case"}], [], lambda n, i: "")
        self.assertEqual(result.text, "")


if __name__ == "__main__":
    unittest.main()
