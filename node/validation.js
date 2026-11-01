import { ValidationError } from "./errors.js";

// The rule each numeric field of a request follows (H-07, H-31, H-44). The
// received handlers checked `!value`, which is truthiness, not a rule: it let
// text, negatives and objects through and turned zero away.
//
// Number.isFinite does not coerce, so numeric text such as "1000" is rejected
// with NaN and Infinity: JSON carries numbers as numbers, and a string kept as
// sent would be concatenated by `balance += amount`.

// For a value that has to be strictly above zero: an amount, a rate.
export function assertPositiveNumber(name, value) {
  if (!Number.isFinite(value) || value <= 0) {
    throw new ValidationError(`${name} must be a positive number`);
  }
}

// For a value where zero is meaningful: an account balance.
export function assertNonNegativeNumber(name, value) {
  if (!Number.isFinite(value) || value < 0) {
    throw new ValidationError(`${name} must be a number greater than or equal to 0`);
  }
}
