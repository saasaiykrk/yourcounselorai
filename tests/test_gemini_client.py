"""The optional Gemini client against a fake Gemini server (httpx MockTransport): the tool loop,
blocked replies, cut-offs, structured JSON, usage names, errors that never carry the key, and that
the app still defaults to Anthropic."""
import importlib.util
import json
import os
import unittest
from unittest import mock

HAVE = importlib.util.find_spec("httpx") is not None
if HAVE:
    import httpx

    from app.gemini_client import GeminiClient, GeminiError, _schema
    from app.pipeline import TOOLS

KEY = "AIza-test-" + "k" * 30


def reply(parts, finish="STOP", usage=None):
    return {"candidates": [{"content": {"role": "model", "parts": parts}, "finishReason": finish}],
            "usageMetadata": usage or {"promptTokenCount": 100, "candidatesTokenCount": 20}}


class FakeGemini:
    def __init__(self, responses, status=200):
        self.responses, self.status, self.requests = list(responses), status, []

    def handler(self, request):
        self.requests.append(request)
        if self.status != 200:
            return httpx.Response(self.status, json={"error": {"message": "API key not valid."}})
        return httpx.Response(200, json=self.responses.pop(0))

    def body(self, i):
        return json.loads(self.requests[i].content)


@unittest.skipUnless(HAVE, "httpx not installed")
class GeminiClientTests(unittest.TestCase):
    def client(self, fake):
        return GeminiClient(KEY, "gemini-test", transport=httpx.MockTransport(fake.handler), sleep=lambda s: None)

    def test_tool_loop_sends_the_model_turn_back_and_returns_only_the_final_text(self):
        signed = {"functionCall": {"name": "icd11_lookup", "args": {"query": "panic disorder"}},
                  "thoughtSignature": "sig-abc"}
        fake = FakeGemini([reply([{"text": "Let me check. "}, signed]),
                           reply([{"text": "thinking…", "thought": True}, {"text": "MODE: C | Final"}])])
        seen = []
        r = self.client(fake).run(["SKILL", "ADDENDUM"], [{"role": "user", "content": "34F panic"}], TOOLS,
                                  lambda name, args: seen.append((name, args)) or "6B01 — Panic disorder")
        self.assertEqual(r.text, "MODE: C | Final", "preamble and thoughts are not part of the reply")
        self.assertEqual(seen, [("icd11_lookup", {"query": "panic disorder"})])
        self.assertEqual(r.tool_calls, [{"name": "icd11_lookup", "input": {"query": "panic disorder"}}])
        first, second = fake.body(0), fake.body(1)
        self.assertEqual([p["text"] for p in first["systemInstruction"]["parts"]], ["SKILL", "ADDENDUM"])
        self.assertEqual({d["name"] for d in first["tools"][0]["functionDeclarations"]}, {"get_card", "icd11_lookup"})
        self.assertIn(signed, second["contents"][1]["parts"], "the signed model turn goes back unchanged")
        self.assertEqual(second["contents"][2]["parts"][0]["functionResponse"],
                         {"name": "icd11_lookup", "response": {"result": "6B01 — Panic disorder"}})
        self.assertEqual(r.usage["input_tokens"], 200)

    def test_the_key_goes_in_a_header_never_the_url(self):
        fake = FakeGemini([reply([{"text": "ok"}])])
        self.client(fake).run("S", [{"role": "user", "content": "x"}], [], lambda *a: "")
        req = fake.requests[0]
        self.assertEqual(req.headers["x-goog-api-key"], KEY)
        self.assertNotIn(KEY, str(req.url))
        self.assertTrue(str(req.url).endswith("/models/gemini-test:generateContent"))

    def test_history_roles_map_to_gemini_roles(self):
        fake = FakeGemini([reply([{"text": "ok"}])])
        self.client(fake).run("S", [{"role": "user", "content": "a"}, {"role": "assistant", "content": "b"},
                                    {"role": "user", "content": "c"}], [], lambda *a: "")
        self.assertEqual([c["role"] for c in fake.body(0)["contents"]], ["user", "model", "user"])

    def test_a_blocked_reply_delivers_nothing(self):
        for resp in (reply([], finish="SAFETY"), {"promptFeedback": {"blockReason": "SAFETY"}}, {"candidates": []}):
            fake = FakeGemini([resp])
            r = self.client(fake).run("S", [{"role": "user", "content": "x"}], TOOLS, lambda *a: "")
            self.assertEqual(r.text, "", resp)

    def test_a_cut_off_reply_is_counted(self):
        fake = FakeGemini([reply([{"text": "half a tab"}], finish="MAX_TOKENS")])
        r = self.client(fake).run("S", [{"role": "user", "content": "x"}], [], lambda *a: "")
        self.assertEqual(r.usage["max_tokens_stops"], 1)

    def test_usage_uses_the_same_names_as_the_claude_client(self):
        fake = FakeGemini([reply([{"text": "ok"}], usage={"promptTokenCount": 1000, "cachedContentTokenCount": 800,
                                                          "candidatesTokenCount": 50, "thoughtsTokenCount": 150})])
        r = self.client(fake).run("S", [{"role": "user", "content": "x"}], [], lambda *a: "")
        self.assertEqual((r.usage["input_tokens"], r.usage["cache_read_input_tokens"], r.usage["output_tokens"]),
                         (200, 800, 200))

    def test_structured_json(self):
        schema = {"type": "object", "additionalProperties": False,
                  "properties": {"status": {"type": "string", "enum": ["ask", "ready"]},
                                 "items": {"type": "array", "items": {"type": "object", "additionalProperties": False,
                                                                      "properties": {"f": {"type": "string"}}}}},
                  "required": ["status"]}
        fake = FakeGemini([reply([{"text": '{"status": "ready"}'}]), reply([{"text": "not json"}]),
                           reply([], finish="SAFETY")])
        c = self.client(fake)
        self.assertEqual(c.run_structured("S", "u", schema)[0], {"status": "ready"})
        sent = fake.body(0)["generationConfig"]
        self.assertEqual(sent["responseMimeType"], "application/json")
        self.assertNotIn("additionalProperties", json.dumps(sent["responseSchema"]), "Gemini rejects it")
        self.assertEqual(sent["responseSchema"]["properties"]["status"]["enum"], ["ask", "ready"])
        self.assertIsNone(c.run_structured("S", "u", schema)[0])
        self.assertIsNone(c.run_structured("S", "u", schema)[0])

    def test_errors_are_raised_without_the_key_and_busy_is_retried(self):
        fake = FakeGemini([], status=400)
        with self.assertRaises(GeminiError) as cm:
            self.client(fake).run("S", [{"role": "user", "content": "x"}], [], lambda *a: "")
        self.assertNotIn(KEY, str(cm.exception))
        self.assertIn("400", str(cm.exception))
        busy = FakeGemini([reply([{"text": "ok"}])])
        calls = {"n": 0}

        def flaky(request):
            calls["n"] += 1
            return httpx.Response(503, json={}) if calls["n"] == 1 else busy.handler(request)
        waits = []
        c = GeminiClient(KEY, "gemini-test", transport=httpx.MockTransport(flaky), sleep=waits.append)
        self.assertEqual(c.run("S", [{"role": "user", "content": "x"}], [], lambda *a: "").text, "ok")
        self.assertEqual(waits, [5], "waits before trying again")

    def test_quota_errors_are_retried_with_googles_wait_then_given_up(self):
        calls, waits = {"n": 0}, []

        def limited(request):
            calls["n"] += 1
            return httpx.Response(429, headers={"retry-after": "7"}, json={"error": {"message": "quota"}})
        c = GeminiClient(KEY, "gemini-test", transport=httpx.MockTransport(limited), sleep=waits.append)
        with self.assertRaises(GeminiError) as cm:
            c.run("S", [{"role": "user", "content": "x"}], [], lambda *a: "")
        self.assertEqual((cm.exception.status, calls["n"], waits), (429, 4, [7.0, 7.0, 7.0]))

    def test_schema_cleaning_keeps_everything_else(self):
        self.assertEqual(_schema({"type": "object", "additionalProperties": False, "$schema": "x",
                                  "properties": {"a": {"type": "string", "default": "z"}}}),
                         {"type": "object", "properties": {"a": {"type": "string"}}})


class ProviderConfigTests(unittest.TestCase):
    BASE = {"DATABASE_URL": "postgresql://u:p@h/db", "SUPABASE_JWKS_URL": "https://x/jwks", "DEV_MODE": "0"}

    def load(self, env):
        from app.secrets import load_config
        with mock.patch.dict(os.environ, env, clear=True):
            return load_config()

    def test_anthropic_stays_the_default(self):
        cfg = self.load({**self.BASE, "ANTHROPIC_API_KEY": "sk", "CLAUDE_MODEL": "claude-opus-5-5"})
        self.assertEqual((cfg.model_provider, cfg.platform_model), ("anthropic", "claude-opus-5-5"))
        self.assertFalse(cfg.public()["gemini_configured"])

    def test_gemini_needs_its_own_key_and_model_and_never_shows_the_key(self):
        with self.assertRaises(RuntimeError) as cm:
            self.load({**self.BASE, "MODEL_PROVIDER": "gemini", "GEMINI_API_KEY": KEY})
        self.assertIn("GEMINI_MODEL", str(cm.exception))
        cfg = self.load({**self.BASE, "MODEL_PROVIDER": "gemini", "GEMINI_API_KEY": KEY, "GEMINI_MODEL": "gemini-x"})
        self.assertEqual((cfg.model_provider, cfg.platform_model), ("gemini", "gemini-x"))
        self.assertTrue(cfg.public()["gemini_configured"])
        self.assertNotIn(KEY, json.dumps(cfg.public()))
        with self.assertRaises(RuntimeError):
            self.load({**self.BASE, "MODEL_PROVIDER": "openai"})


if __name__ == "__main__":
    unittest.main()
