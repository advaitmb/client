/**
 * Clipboard failures (CODE_REVIEW.md E16), extracted from the three call sites
 * that used to each handle them differently — or not at all — into
 * src/shared/clipboard.js.
 *
 * Before: the paste path caught only the errors whose `message` contained
 * "denied" and dropped the rest, and would itself throw on an error with no
 * `message` at all; the two copy paths (`CopyToClipboard` in doc.js,
 * `CopyCurrentSubtree` in doc-helpers.js) attached no handler, so a refused
 * copy was an unhandled rejection behind a flash that said it had worked.
 */
import { expect, test } from "bun:test";

import { clipboardErrorMessage, copyText } from "../src/shared/clipboard";

/** What a browser rejects a clipboard call with when permission is refused. */
function permissionDenied(): Error {
  const error = new Error("Write permission denied.");
  error.name = "NotAllowedError";
  return error;
}

test("a refused read keeps the advice that tells the user how to allow it", () => {
  const message = clipboardErrorMessage("read", permissionDenied());

  expect(message).toContain("padlock");
});

test("a refused copy gets the same advice, not silence", () => {
  // Only the read path used to say anything at all.
  expect(clipboardErrorMessage("copy", permissionDenied())).toContain("padlock");
});

test("permission errors are recognized by name, not only by wording", () => {
  const noWording = new Error("The request is not allowed by the user agent.");
  noWording.name = "NotAllowedError";

  expect(clipboardErrorMessage("copy", noWording)).toContain("padlock");
});

test("permission errors are still recognized by wording, whatever the case", () => {
  expect(clipboardErrorMessage("read", new Error("Permission Denied"))).toContain("padlock");
});

test("any other failure says what failed instead of vanishing", () => {
  const message = clipboardErrorMessage("copy", new Error("Document is not focused"));

  expect(message).toContain("Document is not focused");
  expect(message).not.toContain("padlock");
});

test("the message says which direction the clipboard was being used in", () => {
  const copying = clipboardErrorMessage("copy", new Error("nope"));
  const reading = clipboardErrorMessage("read", new Error("nope"));

  expect(copying).not.toBe(reading);
});

test.each([undefined, null, "a bare string", 42, {}])(
  "an error of %p still produces a message rather than throwing",
  (thrown) => {
    // The old paste handler did `err.message.includes("denied")`, which threw
    // inside its own catch for anything without a `message`.
    expect(clipboardErrorMessage("read", thrown)).toBeString();
    expect(clipboardErrorMessage("read", thrown)).not.toBe("");
  },
);

test("a successful copy reports no error and writes the text", async () => {
  const written: string[] = [];
  const errors: string[] = [];

  await copyText("some cards", {
    clipboard: { writeText: async (text: string) => { written.push(text); } },
    onError: (message: string) => errors.push(message),
  });

  expect(written).toEqual(["some cards"]);
  expect(errors).toEqual([]);
});

test("a refused copy reports the failure instead of rejecting", async () => {
  const errors: string[] = [];

  // Awaiting must not throw: the call sites are inside a synchronous dispatch
  // table that does not await them, so a rejection here is an unhandled one.
  await copyText("some cards", {
    clipboard: { writeText: async () => { throw permissionDenied(); } },
    onError: (message: string) => errors.push(message),
  });

  expect(errors.length).toBe(1);
  expect(errors[0]).toContain("padlock");
});

test("a copy with no clipboard at all is a reported failure, not a crash", async () => {
  // `navigator.clipboard` is undefined outside a secure context.
  const errors: string[] = [];

  await copyText("some cards", {
    clipboard: undefined,
    onError: (message: string) => errors.push(message),
  });

  expect(errors.length).toBe(1);
});
