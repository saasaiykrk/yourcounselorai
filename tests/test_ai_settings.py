"""Web admin → AI Model, against a real Postgres (migration 008). Skipped without TEST_DATABASE_URL.

What must hold:
- only approved models (app/ai_models.py) can be chosen, with a typed confirmation, and only when a
  key for that provider exists; every switch is audited;
- a key added by an admin is checked first, stored encrypted, never returned or audited in clear,
  and takes priority over the server's key; removing it falls back to the server's key;
- the pipeline follows the switch within the cache time, and never stops if the database is down;
- only admins can see or change any of it."""
import base64
import importlib.util
import json
import os
import unittest
import uuid
from types import SimpleNamespace

URL = os.environ.get("TEST_DATABASE_URL", "")
HAVE = bool(URL) and all(importlib.util.find_spec(m) for m in ("fastapi", "httpx", "psycopg", "cryptography",
                                                                "anthropic"))
if HAVE:
    os.environ["DEV_MODE"] = "1"
    import psycopg
    from fastapi.testclient import TestClient

    from app import ai_models, byok, db, main
    from app.ai_settings import AiSettingsError, AiStore, ModelRouter
    db._DSN = URL

ANTHROPIC_SERVER = "sk-ant-api03-" + "s" * 60 + "SRV1"
ANTHROPIC_ADMIN = "sk-ant-api03-" + "a" * 60 + "ADM1"
GEMINI_ADMIN = "AIzaSy" + "g" * 33 + "GEM1"


class FakeClient:
    def __init__(self, provider, key, model):
        self.provider, self.key, self.model = provider, key, model

    def run(self, *a):
        return SimpleNamespace(text=f"{self.provider}:{self.model}")

    def run_structured(self, *a, **k):
        return {"by": self.model}, {}


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


@unittest.skipUnless(HAVE, "TEST_DATABASE_URL not set")
class AiSettingsTests(unittest.TestCase):
    def setUp(self):
        with psycopg.connect(URL, autocommit=True) as c:
            c.execute("delete from ai_settings; delete from ai_provider_keys;")
            c.execute("delete from admin_audit where action like 'ai_%'")
            self.admin_id, self.clin_id = str(uuid.uuid4()), str(uuid.uuid4())
            for i, (who, adm) in enumerate(((self.admin_id, True), (self.clin_id, False))):
                c.execute("insert into auth.users (id, email) values (%s,%s)", (who, f"ai{i}-{who[:6]}@test"))
                c.execute("""insert into clinicians (id, role, registration_body, level, verification_status,
                               consent_version, is_admin) values (%s,'psychologist','RCI','L2','verified','v1',%s)""",
                          (who, adm))
        self.who = self.admin_id
        self.cfg = SimpleNamespace(anthropic_api_key=ANTHROPIC_SERVER, gemini_api_key="",
                                   platform_model="claude-opus-5-5")
        self.clock = Clock()
        self.built = []

        def factory(provider, key, model):
            self.built.append((provider, model))
            return FakeClient(provider, key, model)
        self.vault = byok.Vault.from_secrets(base64.b64encode(os.urandom(32)).decode())
        self.router = ModelRouter(self.cfg, AiStore(db._conn), self.vault, factory, ttl=30, clock=self.clock)
        self.checked = []

        def checker(provider, key):
            self.checked.append(provider)
            if key.endswith("BAD1"):
                raise AiSettingsError("key_rejected", "Google did not accept this Gemini API key.")

        def adm():
            row = db.get_clinician(self.who)
            if not row.get("is_admin"):
                raise main.HTTPException(403, "admin only")
            return {**row, "id": self.who}
        self.saved = list(main.app.router.routes)
        main.app.router.routes = [r for r in main.app.router.routes if not getattr(r, "path", "").startswith("/v1/admin/ai")]
        main.ai_admin_api.install(main.app, self.router, adm, key_checker=checker)
        self.client = TestClient(main.app)

    def tearDown(self):
        main.app.router.routes = self.saved

    def rows(self, sql, *args):
        with psycopg.connect(URL, autocommit=True, row_factory=psycopg.rows.dict_row) as c:
            return c.execute(sql, args or None).fetchall()

    def switch(self, model, confirm=None):
        return self.client.put("/v1/admin/ai/model", json={"model": model, "confirm": confirm or model})

    # --- the router the pipeline uses ----------------------------------------------------------------
    def test_default_is_the_servers_model_and_key(self):
        c = self.router.current()
        self.assertEqual((c.provider, c.model, c.key), ("anthropic", "claude-opus-5-5", ANTHROPIC_SERVER))

    def test_a_switch_reaches_the_pipeline_within_the_cache_time(self):
        self.assertEqual(self.client.put("/v1/admin/ai/keys/gemini", json={"api_key": GEMINI_ADMIN}).status_code, 200)
        self.router.current()                                     # warm the cache on Claude
        other = ModelRouter(self.cfg, AiStore(db._conn), self.vault, FakeClient, ttl=30, clock=self.clock)
        other.current()                                           # a second server instance
        self.assertEqual(self.switch("gemini-3.8-flash").status_code, 200)
        self.assertEqual(self.router.run("s", [], [], None).text, "gemini:gemini-3.8-flash", "this instance at once")
        self.assertEqual(other.model, "claude-opus-5-5", "another instance keeps its cache for up to 30 s")
        self.clock.t = 31
        self.assertEqual(other.model, "gemini-3.8-flash")
        self.assertEqual(other.current().key, GEMINI_ADMIN)
        self.assertEqual(self.router.run_structured("s", "u", {})[0], {"by": "gemini-3.8-flash"})

    def test_clients_are_built_only_when_something_changed(self):
        for t in (0, 31, 62):
            self.clock.t = t
            self.router.current()
        self.assertEqual(self.built, [("anthropic", "claude-opus-5-5")])

    def test_database_down_falls_back_to_the_server_default(self):
        class Down(AiStore):
            def active_model(self):
                raise RuntimeError("db down")
        r = ModelRouter(self.cfg, Down(db._conn), self.vault, FakeClient)
        self.assertEqual(r.model, "claude-opus-5-5")

    def test_missing_tables_never_stop_replies_or_the_health_check(self):
        class NoTables(AiStore):          # migration 008 not run yet
            def active_model(self):
                raise psycopg.errors.UndefinedTable("relation \"ai_settings\" does not exist")

            def keys(self):
                raise psycopg.errors.UndefinedTable("relation \"ai_provider_keys\" does not exist")
        r = ModelRouter(self.cfg, NoTables(db._conn), self.vault, FakeClient)
        self.assertEqual((r.model, r.current().key), ("claude-opus-5-5", ANTHROPIC_SERVER))

    def test_an_unapproved_model_in_the_database_is_ignored(self):
        self.rows("insert into ai_settings (id, active_model) values (1, 'some-untested-model') returning id")
        self.assertEqual(self.router.model, "claude-opus-5-5")

    # --- keys ------------------------------------------------------------------------------------------
    def test_an_admin_key_is_checked_encrypted_and_never_shown(self):
        r = self.client.put("/v1/admin/ai/keys/anthropic", json={"api_key": ANTHROPIC_ADMIN})
        self.assertEqual(r.json(), {"provider": "anthropic", "source": "admin", "last4": "ADM1"})
        self.assertEqual(self.checked, ["anthropic"])
        [row] = self.rows("select * from ai_provider_keys")
        self.assertNotIn(ANTHROPIC_ADMIN.encode(), bytes(row["ciphertext"]))
        page = self.client.get("/v1/admin/ai").text
        self.assertNotIn(ANTHROPIC_ADMIN, page)
        self.assertNotIn(ANTHROPIC_SERVER, page)
        self.assertNotIn(ANTHROPIC_ADMIN, json.dumps([r["detail"] for r in self.rows(
            "select detail from admin_audit where action like 'ai_%'")]))
        self.assertEqual(self.router.current().key, ANTHROPIC_ADMIN, "the admin key wins over the server key")
        keys = self.client.get("/v1/admin/ai").json()["keys"]
        self.assertEqual((keys["anthropic"]["source"], keys["gemini"]["source"]), ("admin", "none"))

    def test_bad_keys_are_refused_and_not_stored(self):
        self.assertEqual(self.client.put("/v1/admin/ai/keys/gemini", json={"api_key": "AIza" + "x" * 30 + "BAD1"})
                         .status_code, 422)
        self.assertEqual(self.client.put("/v1/admin/ai/keys/anthropic", json={"api_key": "not a key at all, really"})
                         .status_code, 422)
        self.assertEqual(self.client.put("/v1/admin/ai/keys/gemini", json={"api_key": ANTHROPIC_ADMIN}).status_code, 422,
                         "an Anthropic key in the Gemini slot")
        self.assertEqual(self.client.put("/v1/admin/ai/keys/openai", json={"api_key": GEMINI_ADMIN}).status_code, 404)
        self.assertEqual(self.rows("select provider from ai_provider_keys"), [])

    def test_removing_a_key_falls_back_but_not_from_under_the_active_model(self):
        self.client.put("/v1/admin/ai/keys/gemini", json={"api_key": GEMINI_ADMIN})
        self.switch("gemini-3.8-flash")
        r = self.client.delete("/v1/admin/ai/keys/gemini")
        self.assertEqual(r.status_code, 409, "the active model needs it and the server has no Gemini key")
        self.switch("claude-opus-5-5")
        self.assertEqual(self.client.delete("/v1/admin/ai/keys/gemini").status_code, 200)
        self.assertEqual(self.client.delete("/v1/admin/ai/keys/gemini").status_code, 404)
        self.client.put("/v1/admin/ai/keys/anthropic", json={"api_key": ANTHROPIC_ADMIN})
        self.assertEqual(self.client.delete("/v1/admin/ai/keys/anthropic").status_code, 200,
                         "the server's own Anthropic key takes over")
        self.router.invalidate()
        self.assertEqual(self.router.current().key, ANTHROPIC_SERVER)

    def test_keys_need_the_encryption_key(self):
        self.router.vault = None
        r = self.client.put("/v1/admin/ai/keys/gemini", json={"api_key": GEMINI_ADMIN})
        self.assertEqual(r.status_code, 503)

    # --- switching ----------------------------------------------------------------------------------
    def test_only_approved_models_with_a_typed_confirmation_and_a_key(self):
        self.assertEqual(self.switch("gpt-5").status_code, 422)
        self.assertEqual(self.switch("gemini-3.8-flash", confirm="yes").status_code, 422)
        r = self.switch("gemini-3.8-flash")
        self.assertEqual((r.status_code, r.json()["detail"]["error"]), (409, "no_key"))
        self.client.put("/v1/admin/ai/keys/gemini", json={"api_key": GEMINI_ADMIN})
        self.assertEqual(self.switch("gemini-3.8-flash").status_code, 200)
        page = self.client.get("/v1/admin/ai").json()
        self.assertEqual(page["active_model"], "gemini-3.8-flash")
        self.assertEqual([m["id"] for m in page["models"] if m["active"]], ["gemini-3.8-flash"])
        actions = [(h["action"], h["detail"]) for h in page["history"]]
        self.assertIn(("ai_model", {"from": "claude-opus-5-5", "to": "gemini-3.8-flash"}), actions)
        self.assertIn(("ai_key_set", {"provider": "gemini", "last4": "GEM1"}), actions)

    def test_every_listed_model_names_a_known_provider(self):
        self.assertTrue(ai_models.APPROVED)
        for m in ai_models.APPROVED:
            self.assertIn(m["provider"], ai_models.PROVIDERS)

    # --- access ---------------------------------------------------------------------------------------
    def test_only_admins(self):
        self.who = self.clin_id
        self.assertEqual(self.client.get("/v1/admin/ai").status_code, 403)
        self.assertEqual(self.switch("claude-opus-5-5").status_code, 403)
        self.assertEqual(self.client.put("/v1/admin/ai/keys/gemini", json={"api_key": GEMINI_ADMIN}).status_code, 403)

    def test_dev_mode_without_a_database_says_so(self):
        self.router.store = None
        self.assertEqual(self.client.get("/v1/admin/ai").status_code, 503)


if __name__ == "__main__":
    unittest.main()
