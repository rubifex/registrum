# ADR 001: Certify Rouge state snapshots empirically

- Status: Accepted
- Date: 2026-09-10

## Context

Antares must resume Rouge lexers after an edit without losing cross-line regular
expression semantics or mutable lexer-owned state. Rouge lexers vary: some use
custom stream drivers, some contain nonlocal rules, and their internals may
change between Rouge versions.

The credible alternatives are full-document lexing after every edit, bounded
window lexing, line-at-a-time `continue_lex`, and resuming from captured lexer
state. Full lexing is exact but scales with document size. Window lexing is
bounded but approximate for long-running constructs. Line-at-a-time lexing does
not preserve cross-line matches.

## Decision

Resume certified `Rouge::RegexLexer` instances from sparse snapshots of their
persistent state. Drive `RegexLexer#step` with fixed-anchor scanning over bounded,
materialized source, and capture state only after a complete rule callback. Use
state fingerprints to stop after convergence.

Certify compatibility separately for every lexer and exact Rouge version. The
automatic strategy uses incremental highlighting only for a certified lexer;
unknown versions and failed lexers use window highlighting. Full lexing remains
available when exact output is required.

## Consequences

Certified lexers can reuse work after edits while preserving Rouge's matching
semantics. Unsupported or uncertain cases fail closed to the bounded fallback.

Source must still be materialized after edits, and snapshotting depends on Rouge
internals. Compatibility must therefore be reassessed for each Rouge version.
Window highlighting remains approximate, while full highlighting retains its
document-size cost. Revisit this decision if Rouge provides a stable resume API,
source materialization becomes the dominant cost, or empirical certification no
longer gives sufficient confidence.
