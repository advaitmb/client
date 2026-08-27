# 02: Sanitize all rendered card markdown (stored XSS)

Part of `../map.md`. **Type:** task · **Status:** ready-for-agent

**Blocked by:** 01

**Covers:** CODE_REVIEW.md C1 · Decision: ADR-0003.

**What to build:** A card containing hostile markup (e.g.
`<img src=x onerror=alert(1)>`, `javascript:` links) renders inert everywhere
card content is displayed — tree cards, fullscreen, export preview — while
CriticMarkup (`<ins>`/`<del>`) and task-list checkboxes keep working.

## Acceptance criteria

- [ ] DOMPurify (or equivalent) with the ADR-0003 allowlist wraps every
      `innerHTML` assignment of markdown-derived HTML, defined once and shared.
- [ ] Tests: script/event-handler/`javascript:`-URL payloads are neutralized;
      `ins`/`del` and checkbox inputs survive; checkbox click plumbing still
      fires.
- [ ] Export preview path uses the same sanitizer.
- [ ] Bundle builds and CI is green.
