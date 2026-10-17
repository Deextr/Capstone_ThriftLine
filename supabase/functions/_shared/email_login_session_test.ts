import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decodeJwtPayload,
  sessionIdFromAccessToken,
} from "./jwt.ts";

function b64urlJson(value: Record<string, unknown>): string {
  const json = JSON.stringify(value);
  const bytes = new TextEncoder().encode(json);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fakeJwt(payload: Record<string, unknown>): string {
  return `header.${b64urlJson(payload)}.sig`;
}

Deno.test("sessionIdFromAccessToken reads session_id", () => {
  const token = fakeJwt({ session_id: "11111111-1111-1111-1111-111111111111" });
  assertEquals(
    sessionIdFromAccessToken(token),
    "11111111-1111-1111-1111-111111111111",
  );
});

Deno.test("decodeJwtPayload returns null for malformed token", () => {
  assertEquals(decodeJwtPayload("not-a-jwt"), null);
});
