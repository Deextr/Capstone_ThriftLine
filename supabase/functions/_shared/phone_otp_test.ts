import {
  SMS_DELIVERY_UNAVAILABLE_MESSAGE,
  classifyUnismsFailure,
  normalizePhPhone,
  toE164Ph,
} from "./phone_otp.ts";

function assertEquals(actual: unknown, expected: unknown) {
  if (actual !== expected) {
    throw new Error(`expected ${JSON.stringify(expected)} but got ${JSON.stringify(actual)}`);
  }
}

Deno.test("normalizePhPhone accepts local and E.164 mobiles", () => {
  assertEquals(normalizePhPhone("09171234567"), "09171234567");
  assertEquals(normalizePhPhone("09051234567"), "09051234567");
  assertEquals(normalizePhPhone("+639171234567"), "09171234567");
  assertEquals(normalizePhPhone("639151234567"), "09151234567");
  assertEquals(normalizePhPhone("0917 123 4567"), "09171234567");
  assertEquals(normalizePhPhone("9171234567"), "09171234567");
  assertEquals(toE164Ph("09171234567"), "+639171234567");
  assertEquals(toE164Ph("09051234567"), "+639051234567");
});

Deno.test("normalizePhPhone rejects short, non-09, and truncated +63 values", () => {
  assertEquals(normalizePhPhone("0917123456"), null);
  assertEquals(normalizePhPhone("091712345678"), null);
  assertEquals(normalizePhPhone("08171234567"), null);
  assertEquals(normalizePhPhone("0917abc4567"), null);
  assertEquals(normalizePhPhone("63917123456"), null);
  assertEquals(normalizePhPhone("631234567890"), null);
});

Deno.test("UniSMS credit and SID failures are not invalid phone numbers", () => {
  const credits = classifyUnismsFailure(
    422,
    { errors: "Insufficient sms credits" },
    "",
  );
  assertEquals(credits.code, "provider_credits");
  assertEquals(credits.userMessage, SMS_DELIVERY_UNAVAILABLE_MESSAGE);

  const sid = classifyUnismsFailure(
    400,
    { errors: ["No SID tokens available"] },
    "",
  );
  assertEquals(sid.code, "provider_credits");
  assertEquals(sid.userMessage, SMS_DELIVERY_UNAVAILABLE_MESSAGE);
});

Deno.test("UniSMS sender and auth failures stay delivery errors", () => {
  const sender = classifyUnismsFailure(
    422,
    { errors: "Invalid sender_id" },
    "",
  );
  assertEquals(sender.code, "provider_error");
  assertEquals(sender.userMessage, SMS_DELIVERY_UNAVAILABLE_MESSAGE);

  const auth = classifyUnismsFailure(401, { error: "Unauthorized" }, "");
  assertEquals(auth.code, "provider_auth");
  assertEquals(auth.userMessage, SMS_DELIVERY_UNAVAILABLE_MESSAGE);

  const bare = classifyUnismsFailure(400, { errors: "Bad Request" }, "");
  assertEquals(bare.code, "provider_error");
});

Deno.test("UniSMS invalid recipient is the only provider invalid_phone", () => {
  const recipient = classifyUnismsFailure(
    422,
    { errors: "Invalid recipient" },
    "",
  );
  assertEquals(recipient.code, "invalid_phone");
});
