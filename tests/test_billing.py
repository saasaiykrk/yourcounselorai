"""Pricing configuration rules (no database): validation, prices from the server's config only,
what the app is shown, and the audit diff."""
import copy
import unittest

from app import billing


def cfg(**changes):
    c = copy.deepcopy(billing.DEFAULT_CONFIG)
    c.update(changes)
    return c


class ConfigTests(unittest.TestCase):
    def test_defaults_are_valid_and_pricing_is_off(self):
        c = billing.validate({})
        self.assertFalse(c["enabled"])
        self.assertEqual(c["currency"], "INR")

    def test_invalid_values_are_all_reported(self):
        bad = cfg(enabled=True)
        bad["plans"]["sub_30"].update(price=-1, reports=0, duration_days=400)
        bad["plans"]["per_report"]["prices"]["guided"] = 50          # under ₹1
        bad["plans"]["sub_50"]["name"] = " "
        with self.assertRaises(billing.ConfigError) as cm:
            billing.validate(bad)
        text = " | ".join(cm.exception.problems)
        for part in ("sub_30.price", "sub_30.reports", "sub_30.duration_days", "per_report.prices.guided", "sub_50.name"):
            self.assertIn(part, text)

    def test_unknown_or_wrongly_typed_settings_are_refused(self):
        for bad in ({"plans": {"gold": {}}}, {"enabled": "yes"}, {"currency": "USD"},
                    {"plans": {"sub_30": {"price": 199.5}}}, {"plans": {"sub_30": {"price": True}}},
                    {"plans": {"sub_30": {"discount": 10}}}):
            with self.assertRaises(billing.ConfigError, msg=bad):
                billing.validate(bad)

    def test_free_is_allowed_but_pricing_on_with_every_plan_off_is_not(self):
        c = cfg(enabled=True)
        c["plans"]["per_report"]["prices"]["direct"] = 0
        billing.validate(c)
        for p in billing.PLANS:
            c["plans"][p]["enabled"] = False
        with self.assertRaises(billing.ConfigError):
            billing.validate(c)

    def test_byok_must_allow_a_report_type(self):
        c = cfg()
        c["plans"]["byok"].update(enabled=True, guided=False, direct=False)
        with self.assertRaises(billing.ConfigError):
            billing.validate(c)

    def test_diff_names_each_changed_value(self):
        a = billing.validate({})
        b = copy.deepcopy(a)
        b["plans"]["sub_30"]["price"] = 249900
        b["enabled"] = True
        self.assertEqual(billing.diff(a, b), {"enabled": [False, True], "plans.sub_30.price": [199900, 249900]})
        b["plans"]["sub_50"]["enabled"] = False
        self.assertEqual(billing.newly_disabled(a, b), ["sub_50"])


class PriceTests(unittest.TestCase):
    def setUp(self):
        self.c = billing.validate(cfg(enabled=True))

    def test_prices_come_from_the_configuration(self):
        p = billing.price_for(self.c, "per_report", "guided")
        self.assertEqual((p.amount, p.credits, p.days, p.report_type), (19900, 1, None, "guided"))
        p = billing.price_for(self.c, "sub_50", None)
        self.assertEqual((p.amount, p.credits, p.days), (299900, 50, 30))
        self.c["plans"]["sub_50"]["price"] = 259900
        self.assertEqual(billing.price_for(self.c, "sub_50", None).amount, 259900)

    def test_what_cannot_be_bought(self):
        off = billing.validate({})
        for args, c in ((("sub_30", None), off), (("per_report", None), self.c), (("per_report", "x"), self.c),
                        (("sub_30", "guided"), self.c), (("gold", None), self.c), (("byok", None), self.c)):
            with self.assertRaises(billing.NotPurchasable, msg=args):
                billing.price_for(c, *args)
        self.c["plans"]["sub_30"]["enabled"] = False
        with self.assertRaises(billing.NotPurchasable):
            billing.price_for(self.c, "sub_30", None)

    def test_app_sees_only_enabled_visible_plans_in_order(self):
        self.c["plans"]["sub_50"]["visible"] = False
        self.c["plans"]["byok"].update(enabled=True, order=0)
        view = billing.public_plans(self.c)
        self.assertEqual([p["id"] for p in view["plans"]], ["byok", "per_report", "sub_30"])
        self.assertEqual(view["plans"][2], {**view["plans"][2], "kind": "subscription", "price": 199900, "reports": 30})
        self.assertNotIn("consumes_credits", view["plans"][1])


if __name__ == "__main__":
    unittest.main()
