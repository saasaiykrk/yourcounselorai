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
        bad["plans"]["practice"].update(price_month=-1, was_year=599900)       # old price not above the price
        bad["plans"]["scale"].update(guided_per_month=0)
        bad["plans"]["per_report"]["prices"]["guided"] = 50          # under ₹1
        bad["plans"]["byok_scale"]["name"] = " "
        bad["plans"]["learn"]["trial_days"] = -1
        bad["year_days"] = 0
        with self.assertRaises(billing.ConfigError) as cm:
            billing.validate(bad)
        text = " | ".join(cm.exception.problems)
        for part in ("practice.price_month", "practice.was_year", "scale.guided_per_month", "per_report.prices.guided",
                     "byok_scale.name", "learn.trial_days", "year_days"):
            self.assertIn(part, text)

    def test_unknown_or_wrongly_typed_settings_are_refused(self):
        for bad in ({"plans": {"gold": {}}}, {"enabled": "yes"}, {"currency": "USD"},
                    {"plans": {"scale": {"price_year": 199.5}}}, {"plans": {"scale": {"price_month": True}}},
                    {"plans": {"scale": {"discount": 10}}}, {"plans": {"learn": {"sell_month": False, "sell_year": False}}}):
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

    def test_a_configuration_saved_before_the_new_plans_still_loads(self):
        old = {"enabled": True, "rollover": True, "currency": "INR",
               "plans": {"per_report": {"prices": {"guided": 14900, "direct": 9900}},
                         "sub_30": {"price": 199900}, "sub_50": {}, "byok": {"fee": 0}}}
        c = billing.validate(old)
        self.assertEqual(c["plans"]["per_report"]["prices"]["guided"], 14900, "the per-report prices are kept")
        self.assertEqual(c["plans"]["scale"]["price_year"], 1999900, "new plans start at the defaults")
        self.assertNotIn("rollover", c)

    def test_the_default_plans_are_the_launch_prices(self):
        p = billing.validate({})["plans"]
        self.assertEqual([p[n]["name"] for n in billing.TIERS], ["Learn", "Practice", "BYOK Scale", "Scale"])
        self.assertEqual({n: (p[n]["price_month"], p[n]["price_year"], p[n]["was_year"]) for n in billing.TIERS},
                         {"learn": (59900, 499900, 0), "practice": (99900, 599900, 999900),
                          "byok_scale": (199900, 1499900, 1999900), "scale": (299900, 1999900, 2999900)})
        self.assertEqual((p["learn"]["trial_days"], p["scale"]["guided_per_month"], p["scale"]["extra_price"]),
                         (90, 10, 12900))
        self.assertEqual(p["per_report"]["prices"], {"guided": 19900, "direct": 9900}, "per report unchanged")
        self.assertEqual((p["print"]["price"], p["print"]["hours"]), (4900, 24), "single print unchanged")

    def test_what_each_plan_unlocks(self):
        self.assertEqual(billing.FEATURES["learn"], ("library",))
        self.assertNotIn("guided_own_key", billing.FEATURES["practice"])
        self.assertIn("guided_own_key", billing.FEATURES["byok_scale"])
        self.assertIn("guided_included", billing.FEATURES["scale"])
        for t in ("practice", "byok_scale", "scale"):
            self.assertTrue({"library", "pdf", "booking", "appointments"} <= set(billing.FEATURES[t]), t)

    def test_diff_names_each_changed_value(self):
        a = billing.validate({})
        b = copy.deepcopy(a)
        b["plans"]["scale"]["price_year"] = 2499900
        b["enabled"] = True
        self.assertEqual(billing.diff(a, b), {"enabled": [False, True], "plans.scale.price_year": [1999900, 2499900]})
        b["plans"]["practice"]["enabled"] = False
        self.assertEqual(billing.newly_disabled(a, b), ["practice"])


class PriceTests(unittest.TestCase):
    def setUp(self):
        self.c = billing.validate(cfg(enabled=True))

    def test_prices_come_from_the_configuration(self):
        p = billing.price_for(self.c, "per_report", "guided")
        self.assertEqual((p.amount, p.credits, p.days, p.report_type), (19900, 1, None, "guided"))
        p = billing.price_for(self.c, "practice", None, period="year")
        self.assertEqual((p.amount, p.credits, p.days, p.period), (599900, 0, 365, "year"))
        p = billing.price_for(self.c, "practice", None, period="month")
        self.assertEqual((p.amount, p.days), (99900, 30))
        self.c["plans"]["practice"]["price_year"] = 549900
        self.assertEqual(billing.price_for(self.c, "practice", None, period="year").amount, 549900)

    def test_scale_reports_come_each_month_and_extras_at_scales_price(self):
        self.assertEqual(billing.price_for(self.c, "scale", None, period="month").credits, 10)
        self.assertEqual(billing.price_for(self.c, "scale", None, period="year").credits, 120, "12 months of 10")
        self.assertEqual((billing.allowance_windows(30), billing.allowance_windows(365)), (1, 12))
        p = billing.price_for(self.c, "scale_extra", None)
        self.assertEqual((p.amount, p.credits, p.report_type, p.days), (12900, 1, "guided", None))
        with self.assertRaises(billing.NotPurchasable):
            billing.price_for(self.c, "scale_extra", "direct")

    def test_what_cannot_be_bought(self):
        off = billing.validate({})
        for args, kw, c in ((("scale", None), {"period": "year"}, off), (("per_report", None), {}, self.c),
                            (("per_report", "x"), {}, self.c), (("scale", "guided"), {"period": "year"}, self.c),
                            (("scale", None), {}, self.c), (("scale", None), {"period": "week"}, self.c),
                            (("per_report", "guided"), {"period": "month"}, self.c),
                            (("gold", None), {}, self.c), (("sub_30", None), {}, self.c), (("byok", None), {}, self.c)):
            with self.assertRaises(billing.NotPurchasable, msg=(args, kw)):
                billing.price_for(c, *args, **kw)
        self.c["plans"]["scale"]["sell_month"] = False
        with self.assertRaises(billing.NotPurchasable):
            billing.price_for(self.c, "scale", None, period="month")
        self.c["plans"]["scale"]["enabled"] = False
        with self.assertRaises(billing.NotPurchasable):
            billing.price_for(self.c, "scale", None, period="year")

    def test_a_single_print_is_one_page_for_the_admins_hours(self):
        p = billing.price_for(self.c, "print", None, item="cbt")
        self.assertEqual((p.amount, p.credits, p.days, p.item, p.report_type), (4900, 0, None, "cbt", None))
        self.assertEqual(self.c["plans"]["print"]["hours"], 24)
        for item in (None, ""):
            with self.assertRaises(billing.NotPurchasable, msg=item):
                billing.price_for(self.c, "print", None, item=item)
        with self.assertRaises(billing.NotPurchasable):
            billing.price_for(self.c, "print", "guided", item="cbt")
        with self.assertRaises(billing.NotPurchasable, msg="a page is only for a single print"):
            billing.price_for(self.c, "per_report", "guided", item="cbt")
        self.c["plans"]["print"]["enabled"] = False
        with self.assertRaises(billing.NotPurchasable):
            billing.price_for(self.c, "print", None, item="cbt")

    def test_single_print_settings_are_checked(self):
        for bad in ({"price": -1}, {"hours": 0}, {"hours": 24 * 8}):
            c = cfg()
            c["plans"]["print"].update(bad)
            with self.assertRaises(billing.ConfigError, msg=bad):
                billing.validate(c)
        old = copy.deepcopy(billing.DEFAULT_CONFIG)
        del old["plans"]["print"]
        self.assertEqual(billing.validate(old)["plans"]["print"]["price"], 4900, "saved configs from before get the default")

    def test_app_sees_only_enabled_visible_plans_in_order(self):
        self.c["plans"]["practice"]["visible"] = False
        self.c["plans"]["per_report"]["order"] = 0
        view = billing.public_plans(self.c)
        self.assertEqual([p["id"] for p in view["plans"]], ["per_report", "learn", "byok_scale", "scale"])
        scale = view["plans"][3]
        self.assertEqual(scale, {**scale, "kind": "tier", "badge": "Launch offer", "price_year": 1999900,
                                 "was_year": 2999900, "price_month": 299900, "periods": ["month", "year"]})
        self.assertEqual(scale["table"]["guided"], "10 per month · extra ₹129 each")
        self.assertEqual(view["plans"][2]["table"]["guided"], "Unlimited, with your own AI key")
        learn = view["plans"][1]
        self.assertEqual((learn["trial_days"], learn["table"]["library"], learn["table"]["pdf"]), (90, "Included", None))
        self.assertEqual([r["label"] for r in view["rows"]][0], "Full practice library")
        self.assertNotIn("print", [p["id"] for p in view["plans"]], "bought from the page, not the plans list")

    def test_rupees_use_indian_grouping(self):
        self.assertEqual([billing.rupees(v) for v in (12900, 499900, 1999900, 10000000, 12950)],
                         ["₹129", "₹4,999", "₹19,999", "₹1,00,000", "₹129.50"])


if __name__ == "__main__":
    unittest.main()
