import { checkoutSessionOutcome } from "./paymongo.ts";

function sessionPayload(opts: {
  status: string;
  payments?: Array<Record<string, unknown>>;
  intentStatus?: string;
}): Record<string, unknown> {
  return {
    data: {
      id: "cs_test_session",
      type: "checkout_session",
      attributes: {
        status: opts.status,
        currency: "PHP",
        metadata: { order_id: "11111111-1111-4111-8111-111111111111" },
        line_items: [{ amount: 150000, quantity: 1 }],
        payments: opts.payments ?? [],
        payment_intent: opts.intentStatus
          ? {
            id: "pi_test",
            type: "payment_intent",
            attributes: {
              status: opts.intentStatus,
              amount: 150000,
              currency: "PHP",
            },
          }
          : undefined,
      },
    },
  };
}

function paidPayment(): Record<string, unknown> {
  return {
    id: "pay_paid",
    type: "payment",
    attributes: { status: "paid", amount: 150000, currency: "PHP" },
  };
}

function failedPayment(): Record<string, unknown> {
  return {
    id: "pay_failed",
    type: "payment",
    attributes: { status: "failed", amount: 150000, currency: "PHP" },
  };
}

Deno.test("paid payment on an active session is paid", () => {
  const result = checkoutSessionOutcome(sessionPayload({
    status: "active",
    payments: [paidPayment()],
    intentStatus: "succeeded",
  }));
  if (result.outcome !== "paid") {
    throw new Error(`expected paid, got ${result.outcome}`);
  }
  if (result.paymentId !== "pay_paid") {
    throw new Error(`expected pay_paid, got ${result.paymentId}`);
  }
});

Deno.test("inactive after a successful payment is paid, not expired", () => {
  const result = checkoutSessionOutcome(sessionPayload({
    status: "inactive",
    payments: [paidPayment()],
    intentStatus: "succeeded",
  }));
  if (result.outcome !== "paid") {
    throw new Error(`expected paid, got ${result.outcome}`);
  }
});

Deno.test("a later paid payment wins over an earlier failed attempt", () => {
  const result = checkoutSessionOutcome(sessionPayload({
    status: "inactive",
    payments: [failedPayment(), paidPayment()],
  }));
  if (result.outcome !== "paid") {
    throw new Error(`expected paid, got ${result.outcome}`);
  }
});

Deno.test("inactive with no payments stays pending", () => {
  const result = checkoutSessionOutcome(sessionPayload({
    status: "inactive",
    payments: [],
  }));
  if (result.outcome !== "pending") {
    throw new Error(`expected pending, got ${result.outcome}`);
  }
});

Deno.test("an active session after a failed attempt stays pending", () => {
  const result = checkoutSessionOutcome(sessionPayload({
    status: "active",
    payments: [failedPayment()],
  }));
  if (result.outcome !== "pending") {
    throw new Error(`expected pending, got ${result.outcome}`);
  }
});

Deno.test("an expired session with no payment is expired", () => {
  const result = checkoutSessionOutcome(sessionPayload({
    status: "expired",
    payments: [],
  }));
  if (result.outcome !== "expired") {
    throw new Error(`expected expired, got ${result.outcome}`);
  }
});

Deno.test("an expired session that already captured payment is paid", () => {
  const result = checkoutSessionOutcome(sessionPayload({
    status: "expired",
    payments: [paidPayment()],
  }));
  if (result.outcome !== "paid") {
    throw new Error(`expected paid, got ${result.outcome}`);
  }
});

Deno.test("processing payments stay pending", () => {
  const result = checkoutSessionOutcome(sessionPayload({
    status: "active",
    intentStatus: "processing",
  }));
  if (result.outcome !== "pending") {
    throw new Error(`expected pending, got ${result.outcome}`);
  }
});

Deno.test("a payment intent with succeeded status is paid", () => {
  const result = checkoutSessionOutcome({
    data: {
      id: "pi_test",
      type: "payment_intent",
      attributes: {
        status: "succeeded",
        amount: 150000,
        currency: "PHP",
        payments: [paidPayment()],
      },
    },
  });
  if (result.outcome !== "paid") {
    throw new Error(`expected paid, got ${result.outcome}`);
  }
});

Deno.test("payments wrapped in a data array are still paid", () => {
  const result = checkoutSessionOutcome({
    data: {
      id: "cs_test_session",
      type: "checkout_session",
      attributes: {
        status: "active",
        payments: {
          data: [paidPayment()],
        },
      },
    },
  });
  if (result.outcome !== "paid") {
    throw new Error(`expected paid, got ${result.outcome}`);
  }
});
