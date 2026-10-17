import {
  classifyCreateResponse,
  createOrAdoptRefund,
  liveRefund,
  parseRefundList,
  parseRefundResource,
  PAYMONGO_QRPH_REFUNDS_BASE,
  refundsBaseFor,
  refundUpdatesFromWebhook,
} from "./paymongo_refund.ts";

function expect(cond: boolean, message: string): void {
  if (!cond) throw new Error(message);
}

function refund(
  id: string,
  status: string,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id,
    type: "refund",
    attributes: { status, amount: 5000, payment_id: "pay_1", ...extra },
  };
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("QR Ph refunds use the refunds-api host", () => {
  expect(refundsBaseFor("qrph") === PAYMONGO_QRPH_REFUNDS_BASE, "qrph host");
  expect(refundsBaseFor("gcash").startsWith("https://api.paymongo.com"), "legacy host");
});

Deno.test("succeeded refund is accepted", () => {
  const out = classifyCreateResponse(200, { data: refund("ref_a", "succeeded") });
  expect(out.kind === "accepted", `expected accepted, got ${out.kind}`);
  if (out.kind === "accepted") {
    expect(out.refund.status === "succeeded", "status");
    expect(out.refund.transferLink === null, "no link");
  }
});

Deno.test("pending refund with transfer link keeps the link", () => {
  const out = classifyCreateResponse(200, {
    data: refund("ref_b", "processing", {
      transfer_link: "https://transfer.paymongo.com/abc",
    }),
  });
  expect(out.kind === "accepted", "accepted");
  if (out.kind === "accepted") {
    expect(out.refund.status === "processing", "processing");
    expect(out.refund.transferLink === "https://transfer.paymongo.com/abc", "link");
  }
});

Deno.test("non-https transfer link is not trusted", () => {
  const snap = parseRefundResource({
    data: refund("ref_c", "pending", { transfer_link: "http://evil.example/x" }),
  });
  expect(snap?.transferLink === null, "http link dropped");
});

Deno.test("insufficient balance is a verified rejection", () => {
  const out = classifyCreateResponse(400, {
    errors: [{ code: "available_balance_insufficient", detail: "x" }],
  });
  expect(out.kind === "rejected", `expected rejected, got ${out.kind}`);
  if (out.kind === "rejected") {
    expect(out.errorCode === "available_balance_insufficient", "code");
  }
});

Deno.test("server errors and rate limits are unknown, not rejected", () => {
  expect(classifyCreateResponse(500, {}).kind === "unknown", "500");
  expect(classifyCreateResponse(429, {}).kind === "unknown", "429");
  expect(classifyCreateResponse(401, {}).kind === "unknown", "401");
});

Deno.test("2xx without a refund id is unknown", () => {
  expect(classifyCreateResponse(200, { data: {} }).kind === "unknown", "missing id");
});

Deno.test("payment resource refunds are listed and failed ones are not live", () => {
  const list = parseRefundList({
    data: {
      id: "pay_1",
      attributes: { refunds: [refund("ref_old", "failed"), refund("ref_new", "pending")] },
    },
  });
  expect(list.length === 2, "two refunds");
  expect(liveRefund(list)?.id === "ref_new", "pending refund is live");
  expect(liveRefund([list[0]]) === null, "failed refund is not live");
});

Deno.test("an existing live refund is adopted instead of creating another", async () => {
  let posted = false;
  const out = await createOrAdoptRefund({
    secret: "sk_test",
    paymentId: "pay_1",
    channel: "qrph",
    amountCentavos: 5000,
    idempotencyKey: "esc_1",
    notes: "test",
    fetchImpl: (_url, init) => {
      if (init?.method === "POST") posted = true;
      return Promise.resolve(jsonResponse(200, {
        data: { id: "pay_1", attributes: { refunds: [refund("ref_live", "processing")] } },
      }));
    },
  });
  expect(!posted, "must not POST a second refund");
  expect(out.kind === "accepted" && out.action === "adopt", "adopted");
});

Deno.test("lookup failure is unknown and nothing is created", async () => {
  let posted = false;
  const out = await createOrAdoptRefund({
    secret: "sk_test",
    paymentId: "pay_1",
    channel: "qrph",
    amountCentavos: 5000,
    idempotencyKey: "esc_1",
    notes: "test",
    fetchImpl: (_url, init) => {
      if (init?.method === "POST") posted = true;
      return Promise.resolve(jsonResponse(503, {}));
    },
  });
  expect(!posted, "must not POST when lookup failed");
  expect(out.kind === "unknown", "unknown");
});

Deno.test("no live refund creates one on the QR Ph host", async () => {
  let postUrl = "";
  const out = await createOrAdoptRefund({
    secret: "sk_test",
    paymentId: "pay_1",
    channel: "qrph",
    amountCentavos: 5000,
    idempotencyKey: "esc_1",
    notes: "test",
    fetchImpl: (url, init) => {
      if (init?.method === "POST") {
        postUrl = url;
        return Promise.resolve(jsonResponse(200, {
          data: refund("ref_new", "processing", {
            transfer_link: "https://transfer.paymongo.com/t",
          }),
        }));
      }
      return Promise.resolve(jsonResponse(200, {
        data: { id: "pay_1", attributes: { refunds: [refund("ref_old", "failed")] } },
      }));
    },
  });
  expect(postUrl.startsWith(PAYMONGO_QRPH_REFUNDS_BASE), `posted to ${postUrl}`);
  expect(out.kind === "accepted" && out.action === "create", "created");
});

Deno.test("refund webhook updates are read from refund and payment resources", () => {
  const direct = refundUpdatesFromWebhook({
    data: {
      attributes: { type: "payment.refund.updated", data: refund("ref_x", "succeeded") },
    },
  });
  expect(direct.length === 1 && direct[0].refundId === "ref_x", "direct refund");

  const viaPayment = refundUpdatesFromWebhook({
    data: {
      attributes: {
        type: "payment.refunded",
        data: { id: "pay_1", attributes: { refunds: [refund("ref_y", "succeeded")] } },
      },
    },
  });
  expect(viaPayment.length === 1 && viaPayment[0].status === "succeeded", "payment refunds");
});
