# ADR-0003: Sanitize all HTML rendered from card markdown

**Status:** accepted · **Date:** 2026-08-27

## Decision

Card content is untrusted input (collaborators, JSON import, drag-drop text).
Every `innerHTML` assignment of markdown-derived HTML goes through
**DOMPurify** with one shared allowlist config, defined in one module
(`src/ui/markdown.ts` is the natural home) and used by every render path,
including the export preview.

The allowlist must keep the app's legitimate output working:

- `ins` / `del` (CriticMarkup, injected by `preprocess()`),
- `input[type=checkbox][checked][disabled]` and the click plumbing for task
  lists (`window.checkboxClicked`),
- the usual markdown output (headings, lists, links, code, images, tables).

`javascript:` URLs, event-handler attributes, `style`/`script`/`iframe` are
out. Raw inline HTML in cards that survives the allowlist is fine; anything
executable is not.

## Context

`marked` ≥ 5 has no sanitizer and passes raw inline HTML through;
`markdown.ts` assigned its output directly to `innerHTML` (CODE_REVIEW.md C1,
stored XSS). Escaping all HTML instead of sanitizing would break CriticMarkup
and task-list checkboxes, which are real features.
