import { checkoutSessionOutcome } from "./paymongo.ts";

Deno.test("paid checkout session outcome is never treated as expired", () => {
  const outcome = checkoutSessionOutcome({
    data: {
      id: "cs_test_paid",
      attributes: {
        status: "active",
        payments: [
          {
            data: {
              id: "pay_test",
              attributes: { status: "paid", amount: 1000, currency: "PHP" },
            },
          },
        ],
      },
    },
  });
  if (outcome.outcome !== "paid") {
    throw new Error(`expected paid, got ${outcome.outcome}`);
  }
});

Deno.test("pending checkout session stays pending", () => {
  const outcome = checkoutSessionOutcome({
    data: {
      id: "cs_test_pending",
      attributes: {
        status: "active",
        payments: [
          {
            data: {
              id: "pay_test",
              attributes: {
                status: "awaiting_payment_method",
                amount: 1000,
                currency: "PHP",
              },
            },
          },
        ],
      },
    },
  });
  if (outcome.outcome !== "pending") {
    throw new Error(`expected pending, got ${outcome.outcome}`);
  }
});
