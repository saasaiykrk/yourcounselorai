"""Dollar prices outside India (stdlib only): whoever registered a mobile number from another country pays in
US dollars, converted from the ₹ prices at the admin's rate (₹ per $1) and rounded up to the next $x.99. A rate
of 0 (the default) keeps everyone on ₹."""
import unittest

from app import billing


def cfg(rate=85):
    c = billing.validate({"enabled": True, "usd_rate": rate})
    return c


class UsdPricingTests(unittest.TestCase):
    def test_rupees_become_dollars_rounded_up_to_99_cents(self):
        self.assertEqual(billing.usd_price(99900, 85), 1199)       # ₹999 → 11.75 → $11.99
        self.assertEqual(billing.usd_price(59900, 85), 799)        # ₹599 → 7.05 → $7.99
        self.assertEqual(billing.usd_price(85000, 85), 999)        # exactly $10 → $9.99
        self.assertEqual(billing.usd_price(4900, 85), 99)          # ₹49 → $0.99
        self.assertEqual(billing.usd_price(0, 85), 0, "free stays free")

    def test_who_pays_in_dollars(self):
        c = cfg()
        self.assertEqual(billing.currency_for(c, "+447911123456"), "USD")
        self.assertEqual(billing.currency_for(c, "+919876543210"), "INR")
        self.assertEqual(billing.currency_for(c, None), "INR", "no number yet: rupees")
        self.assertEqual(billing.currency_for(cfg(0), "+447911123456"), "INR", "rate 0: dollar prices are off")

    def test_every_price_is_converted_and_nothing_else(self):
        c = cfg()
        u = billing.in_currency(c, "USD")
        self.assertEqual(u["currency"], "USD")
        self.assertEqual(u["plans"]["practice"]["price_month"], billing.usd_price(c["plans"]["practice"]["price_month"], 85))
        self.assertEqual(u["plans"]["per_report"]["prices"]["guided"], billing.usd_price(19900, 85))
        self.assertEqual(u["plans"]["print"]["price"], 99)
        self.assertEqual(u["plans"]["scale"]["extra_price"], billing.usd_price(12900, 85))
        self.assertEqual(u["plans"]["scale"]["guided_per_month"], c["plans"]["scale"]["guided_per_month"])
        self.assertEqual(c["currency"], "INR", "the stored configuration is not changed")
        self.assertIs(billing.in_currency(c, "INR"), c)

    def test_a_struck_through_price_stays_above_the_price_or_goes(self):
        c = cfg()
        c["plans"]["learn"]["was_month"] = c["plans"]["learn"]["price_month"] + 100      # ₹1 more: same dollars
        u = billing.in_currency(c, "USD")
        self.assertEqual(u["plans"]["learn"]["was_month"], 0)
        self.assertGreater(u["plans"]["practice"]["was_year"], u["plans"]["practice"]["price_year"])

    def test_orders_are_priced_in_dollars(self):
        p = billing.price_for(billing.in_currency(cfg(), "USD"), "practice", None, period="month")
        self.assertEqual((p.currency, p.amount), ("USD", 1199))

    def test_plans_screen_shows_dollars(self):
        pub = billing.public_plans(billing.in_currency(cfg(), "USD"))
        self.assertEqual(pub["currency"], "USD")
        scale = next(p for p in pub["plans"] if p["id"] == "scale")
        self.assertIn("$", scale["table"]["guided"])

    def test_the_rate_is_checked(self):
        self.assertEqual(billing.validate({})["usd_rate"], 0, "off by default")
        for bad in (-1, 5, 5000, "85", True):
            with self.assertRaises(billing.ConfigError, msg=bad):
                billing.validate({"usd_rate": bad})
        self.assertEqual(billing.validate({"usd_rate": 85.5})["usd_rate"], 85.5)

    def test_money_is_written_in_its_currency(self):
        self.assertEqual(billing.money(1199, "USD"), "$11.99")
        self.assertEqual(billing.money(1200, "USD"), "$12")
        self.assertEqual(billing.money(1299900, "INR"), "₹12,999")


if __name__ == "__main__":
    unittest.main()
