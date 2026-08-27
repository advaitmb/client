# 09: Renames/deletes made offline are re-sent on reconnect

Part of `../map.md`. **Type:** task · **Status:** claimed

**Blocked by:** 01

**Covers:** CODE_REVIEW.md D6.

**What to build:** A document rename or delete performed while the socket is
down reaches the server as soon as the connection returns — not "whenever an
unrelated tree-table change or reload happens to retrigger the liveQuery".

## Acceptance criteria

- [ ] On socket (re)open, unsynced tree-metadata rows are sent (queue the
      `trees` message, or re-send unsynced rows in `onopen` alongside the
      existing queue drain and `rt:join`).
- [ ] Test at a practical seam (extracted resend logic, or an integration
      test with a fake socket).
- [ ] CI green.
