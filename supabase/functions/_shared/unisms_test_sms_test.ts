import {
  FIXED_TEST_SMS_CONTENT,
  authorizeTestUnismsSmsUser,
  handleTestUnismsSmsRequest,
  isPhoneOnTestAllowlist,
  isTestSmsFeatureEnabled,
  parseTestPhoneAllowlist,
  parseTestSmsRequestBody,
  type TestUnismsSmsDeps,
} from "./unisms_test_sms.ts";

function assertEquals(actual: unknown, expected: unknown, label?: string) {
  if (actual !== expected) {
    throw new Error(
      `${label ? `${label}: ` : ""}expected ${JSON.stringify(expected)} but got ${JSON.stringify(actual)}`,
    );
  }
}

function assertTrue(cond: boolean, message: string) {
  if (!cond) throw new Error(message);
}

function baseDeps(overrides: Partial<TestUnismsSmsDeps> = {}): TestUnismsSmsDeps {
  return {
    getUser: async () => ({ id: "11111111-1111-1111-1111-111111111111" }),
    loadUserProfile: async () => ({
      role: "super_admin",
      account_status: "active",
    }),
    claimSend: async () => "ok",
    sendSms: async () => ({
      accepted: true,
      status: 201,
      referenceId: "ref_test",
      deliveryStatus: "sent",
      userMessage: "",
    }),
    writeAudit: async () => {},
    featureEnabled: true,
    allowlist: new Set(["09171234567"]),
    fixedMessage: FIXED_TEST_SMS_CONTENT,
    log: () => {},
    ...overrides,
  };
}

Deno.test("feature flag is off unless explicitly enabled", () => {
  assertEquals(isTestSmsFeatureEnabled(undefined), false);
  assertEquals(isTestSmsFeatureEnabled("false"), false);
  assertEquals(isTestSmsFeatureEnabled("true"), true);
});

Deno.test("authorizeTestUnismsSmsUser allows active super_admin only", () => {
  assertEquals(
    authorizeTestUnismsSmsUser({ role: "super_admin", accountStatus: "active" })
      .allowed,
    true,
  );
  assertEquals(
    authorizeTestUnismsSmsUser({ role: "admin", accountStatus: "active" })
      .allowed,
    false,
  );
  assertEquals(
    authorizeTestUnismsSmsUser({ role: "buyer", accountStatus: "active" })
      .allowed,
    false,
  );
  assertEquals(
    authorizeTestUnismsSmsUser({ role: "seller", accountStatus: "active" })
      .allowed,
    false,
  );
  assertEquals(
    authorizeTestUnismsSmsUser({ role: "super_admin", accountStatus: "suspended" })
      .allowed,
    false,
  );
  assertEquals(
    authorizeTestUnismsSmsUser({ role: null, accountStatus: "active" }).allowed,
    false,
  );
});

Deno.test("parseTestSmsRequestBody rejects custom content and extra fields", () => {
  const custom = parseTestSmsRequestBody({
    phone: "09171234567",
    content: "spam",
  });
  assertEquals(custom.ok, false);
  if (!custom.ok) assertEquals(custom.code, "invalid_field");

  const ok = parseTestSmsRequestBody({ phone: "0917 123 4567" });
  assertEquals(ok.ok, true);
  if (ok.ok) assertEquals(ok.phone, "09171234567");

  assertEquals(parseTestSmsRequestBody({}).ok, false);
  assertEquals(parseTestSmsRequestBody({ phone: "08171234567" }).ok, false);
});

Deno.test("allowlist parsing normalizes Philippine numbers", () => {
  const list = parseTestPhoneAllowlist("09171234567, +639051234567");
  assertTrue(isPhoneOnTestAllowlist("09171234567", list), "first allowlisted");
  assertTrue(isPhoneOnTestAllowlist("09051234567", list), "second allowlisted");
  assertTrue(!isPhoneOnTestAllowlist("09181234567", list), "not allowlisted");
});

Deno.test("unauthenticated request is rejected without sending SMS", async () => {
  let sent = false;
  const outcome = await handleTestUnismsSmsRequest(
    { phone: "09171234567" },
    baseDeps({
      getUser: async () => null,
      sendSms: async () => {
        sent = true;
        return {
          accepted: true,
          status: 201,
          userMessage: "",
        };
      },
    }),
  );
  assertEquals(outcome.status, 401);
  assertEquals(sent, false);
});

Deno.test("buyer and seller are rejected", async () => {
  for (const role of ["buyer", "seller"]) {
    let sent = false;
    const outcome = await handleTestUnismsSmsRequest(
      { phone: "09171234567" },
      baseDeps({
        loadUserProfile: async () => ({ role, account_status: "active" }),
        sendSms: async () => {
          sent = true;
          return { accepted: true, status: 201, userMessage: "" };
        },
      }),
    );
    assertEquals(outcome.status, 403, role);
    assertEquals(sent, false, role);
  }
});

Deno.test("regular admin is rejected", async () => {
  let sent = false;
  const outcome = await handleTestUnismsSmsRequest(
    { phone: "09171234567" },
    baseDeps({
      loadUserProfile: async () => ({ role: "admin", account_status: "active" }),
      sendSms: async () => {
        sent = true;
        return { accepted: true, status: 201, userMessage: "" };
      },
    }),
  );
  assertEquals(outcome.status, 403);
  assertEquals(sent, false);
});

Deno.test("super admin succeeds only on allowlisted number with fixed message", async () => {
  let capturedMessage = "";
  const outcome = await handleTestUnismsSmsRequest(
    { phone: "09171234567" },
    baseDeps({
      sendSms: async (_phone, message) => {
        capturedMessage = message;
        return {
          accepted: true,
          status: 201,
          referenceId: "ref_1",
          deliveryStatus: "sent",
          userMessage: "",
        };
      },
    }),
  );
  assertEquals(outcome.status, 200);
  assertEquals(capturedMessage, FIXED_TEST_SMS_CONTENT);
});

Deno.test("unauthorized recipient is rejected", async () => {
  let sent = false;
  const outcome = await handleTestUnismsSmsRequest(
    { phone: "09051234567" },
    baseDeps({
      sendSms: async () => {
        sent = true;
        return { accepted: true, status: 201, userMessage: "" };
      },
    }),
  );
  assertEquals(outcome.status, 403);
  assertEquals(outcome.body.code, "recipient_not_allowed");
  assertEquals(sent, false);
});

Deno.test("rate limit blocks before provider call", async () => {
  let sent = false;
  const outcome = await handleTestUnismsSmsRequest(
    { phone: "09171234567" },
    baseDeps({
      claimSend: async () => "cooldown",
      sendSms: async () => {
        sent = true;
        return { accepted: true, status: 201, userMessage: "" };
      },
    }),
  );
  assertEquals(outcome.status, 429);
  assertEquals(sent, false);
});

Deno.test("daily quota blocks before provider call", async () => {
  let sent = false;
  const outcome = await handleTestUnismsSmsRequest(
    { phone: "09171234567" },
    baseDeps({
      claimSend: async () => "user_daily",
      sendSms: async () => {
        sent = true;
        return { accepted: true, status: 201, userMessage: "" };
      },
    }),
  );
  assertEquals(outcome.status, 429);
  assertEquals(outcome.body.code, "daily_quota");
  assertEquals(sent, false);
});

Deno.test("provider failure returns 502 without ok true", async () => {
  const outcome = await handleTestUnismsSmsRequest(
    { phone: "09171234567" },
    baseDeps({
      sendSms: async () => ({
        accepted: false,
        status: 401,
        code: "provider_auth",
        userMessage: "Delivery unavailable.",
      }),
    }),
  );
  assertEquals(outcome.status, 502);
  assertEquals(outcome.body.ok, false);
});

Deno.test("disabled feature returns 404 and never sends", async () => {
  let sent = false;
  const outcome = await handleTestUnismsSmsRequest(
    { phone: "09171234567" },
    baseDeps({
      featureEnabled: false,
      sendSms: async () => {
        sent = true;
        return { accepted: true, status: 201, userMessage: "" };
      },
    }),
  );
  assertEquals(outcome.status, 404);
  assertEquals(sent, false);
});

Deno.test("audit hook receives blocked and success outcomes", async () => {
  const audits: string[] = [];
  await handleTestUnismsSmsRequest(
    { phone: "09171234567", content: "x" },
    baseDeps({
      writeAudit: async (_id, status) => {
        audits.push(status);
      },
    }),
  );
  assertEquals(audits.length, 1);
  assertEquals(audits[0], "blocked");

  audits.length = 0;
  await handleTestUnismsSmsRequest(
    { phone: "09171234567" },
    baseDeps({
      writeAudit: async (_id, status) => {
        audits.push(status);
      },
    }),
  );
  assertEquals(audits.length, 1);
  assertEquals(audits[0], "success");
});
