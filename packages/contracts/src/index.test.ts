import assert from "node:assert/strict";
import { test } from "node:test";
import { isApiError, API_ERROR_CODES } from "./index";

test("accepts canonical API errors and rejects malformed objects", () => {
  assert.equal(isApiError({ error: "Ungültige Anfrage", code: "VALIDATION" }), true);
  assert.equal(isApiError({ error: "oops", code: "INTERNAL" }), false);
  assert.equal(isApiError(null), false);
  assert.equal(API_ERROR_CODES.length, 12);
});
