import { ValidationError } from "./errors.js";

// H-35: the cursor of a page of the log. Both adapters here issue the
// position of the last entry a page answered, as a decimal string; the client
// sends it back untouched as `after`. Another adapter can issue another
// format: the cursor is opaque to the routes, and only the adapter that
// issued it reads it.
export function positionAfter(after) {
  if (after === undefined) {
    return 0;
  }
  if (typeof after !== "string" || !/^\d+$/.test(after)) {
    throw new ValidationError("after is not a cursor this service issued");
  }
  return Number(after);
}
