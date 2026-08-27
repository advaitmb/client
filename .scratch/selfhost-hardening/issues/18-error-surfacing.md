# 18: Surface swallowed errors through the app's toast pattern

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md E16.

**What to build:** Failures the user needs to know about stop dying in
silence: failed DOCX export shows a toast; an invalid JSON import file shows a
toast; malformed card/push-ack/history payloads surface an error instead of
silently freezing or no-oping; a failed `bulkPut` of pulled cards (lost
incoming sync data!) is reported, not `console.log`ged; clipboard failures are
handled consistently. Use the existing toast machinery — this ticket adds no
new UI concepts.

## Acceptance criteria

- [ ] Each site listed in E16 either surfaces a user-visible error or has a
      written-down reason (in Comments) why silence is correct there.
- [ ] The `ws.onmessage` catch-all no longer flattens every handler error to
      console noise: sync-data write failures produce a visible error state.
- [ ] Tests where a seam allows (decoder failure → error branch).
- [ ] CI green.
