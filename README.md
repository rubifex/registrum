# Antares

Incremental syntax highlighting for Rouge, with measured per-lexer compatibility.

[![CI](https://github.com/noxdea/antares/actions/workflows/main.yml/badge.svg)](https://github.com/noxdea/antares/actions/workflows/main.yml)
[![Ruby 3.1+](https://img.shields.io/badge/ruby-3.1%2B-CC342D.svg)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

[Features](#features) · [Installation](#installation) · [Quick Start](#quick-start) · [Usage](#usage) · [Compatibility](#compatibility) · [Development](#development)

---

Antares adds edit-aware, line-oriented syntax highlighting to
[Rouge](https://github.com/rouge-ruby/rouge). It reuses lexer state where
compatibility tests show that incremental highlighting is safe, and falls back
to bounded re-highlighting for other lexers. Document storage and colors remain
with the caller.

## Features

- Lazy tokenization for individual lines or ranges
- Incremental re-highlighting with sparse state checkpoints
- Cached suffix reuse after edits converge with the previous lexer state
- Measured compatibility for every lexer registered by Rouge
- Windowed and full-document fallback strategies
- Configurable time, document, line, and checkpoint limits
- Rouge is the only runtime dependency

## Installation

Antares requires Ruby 3.1 or later and Rouge 5.x.

Build and install the gem from a local checkout:

```sh
gem build antares.gemspec
gem install ./antares-0.1.0.gem
```

Building does not publish the gem. Tests and CI do not publish it either.

## Quick Start

```ruby
require "antares"

lines = ["value = 1\n", "print(value)\n"]
highlighter = Antares::Highlighter.new(
  lexer: Rouge::Lexers::Python.new,
  lines: ->(index) { lines[index] },
  line_count: -> { lines.length }
)

highlighter.tokens_for(0) # [[Rouge token class, UTF-8 text], ...]

lines[0] = "value = 2\n"
highlighter.edit(from_line: 0, removed: 1, inserted: 1)
highlighter.tokens_in(0..1) # one token array per line
```

## Usage

### Input and tokens

Line indices are zero based. The `lines` provider returns one valid UTF-8
logical line for each index, preferably including its newline. Antares adds a
missing separator to non-final lines; a trailing empty logical line produces an
empty token array.

Tokens contain text rather than offsets. Sum `text.bytesize` for byte offsets or
`text.length` for character offsets. Returned rows, token pairs, and text are
frozen. Highlighter instances are not thread safe.

### Applying edits

Update the provider first, then call `edit` with the old removed line count and
the new inserted line count:

```ruby
lines[index, removed] = replacement_lines
highlighter.edit(
  from_line: index,
  removed: removed,
  inserted: replacement_lines.length
)
```

`frontier` is the first line not yet proven current. Use
`advance(until_line: 200)` to schedule incremental work from an event loop.
`last_scanned_lines` reports actual lexical work, while `checkpoint_bytes`
reports normalized checkpoint payload bytes.

### Strategies

| Strategy | Behavior |
|---|---|
| `:auto` | Uses the compatibility verdict bundled for the exact Rouge version. Unknown versions and lexers use `:window`. |
| `:incremental` | Forces state snapshots and convergence. Use only for certified lexers; forcing a failed lexer can return incorrect classifications. |
| `:window` | Restarts from the root state up to 200 lines before the requested range. This is approximate for long-running constructs. |
| `:full` | Runs ordinary Rouge over the complete bounded document after every edit. Use for exact results on small files with failed incremental lexers. |

### Resource limits

Defaults are 100,000 lines, an 8 MiB source snapshot, 16 KiB per line, 256 KiB
per checkpoint, and 250 ms per scan. Configure them with `max_lines`,
`max_bytes`, `max_line_bytes`, `max_checkpoint_bytes`, and `max_seconds`.

Exceeding a source limit switches to window mode. Oversized individual lines and
timed-out ranges return complete plain-text tokens. `fallback_reason` explains
the transition. These limits also apply to `:full`.

## Compatibility

`Antares.compatible?(Rouge::Lexers::Python)` returns `:incremental` or
`:window`. Every registered lexer has a bundled verdict in `COMPATIBILITY` and a
reproducible result in `COMPATIBILITY_DETAILS`; see the
[complete compatibility table](docs/compatibility.md). Do not infer support only
because a lexer subclasses `Rouge::RegexLexer`.

The matrix tests three source variants from Rouge's bundled MIT-licensed demos,
applies 50 deterministic insert, delete, and replace mutations to each, and
compares every line against a fresh full lex. Three additional distant-closure
probes detect backward reclassification. The result is an empirical corpus
guarantee, not a proof for every input or non-default lexer option.

## How It Works

Antares reuses Rouge's rule interpreter and copies persistent lexer state,
including nested collections, delegate lexers, heredoc queues, sets, and structs.
Immutable rule templates are shared; per-call scanners and callbacks are
excluded. Dynamic rule closures compare conservatively by identity, and opaque
state is rejected instead of shallow-copied.

Checkpoints are placed approximately every 64 completed lines, after entire rule
callbacks. State fingerprints allow early convergence after an edit, while
cached suffixes and checkpoint boundaries shift with line insertions and
deletions.

Calling `continue_lex` once per line is insufficient because Rouge expressions
can consume multiple lines or inspect surrounding text. Antares therefore
materializes a bounded source string on demand and resumes lexical work from a
checkpoint. It retains no array of provider lines. Source materialization is
O(document bytes) after an edit and is included in reported timings.

Some grammars are inherently nonlocal. For example, adding a distant `=end` can
change how Rouge classifies an earlier unmatched Ruby `=begin`. Such lexers use
`:window`; other failures are classified as token mismatches or unsupported
custom stream drivers.

## Development

```sh
bundle install
bundle exec rake test
bundle exec ruby script/compatibility --write
BUDGET=1 bundle exec ruby --yjit bench/highlighting.rb
```

The test suite reruns the complete compatibility matrix. For a shorter diagnostic
run, use `MUTATIONS=5 ruby script/compatibility python rust`; `DETAILS=1` prints
full JSON failure details. Only full runs with at least 50 mutations may replace
the bundled matrix.

Scheduled CI updates Rouge, regenerates the matrix, reruns tests, and uploads the
generated source and table for review. Regular CI tests Ruby 3.1 through 4.0 on
Linux, macOS, and Windows.

On the development Mac with Ruby 4.0.0/YJIT, the 5,000-line Python benchmark
measured 10.771 ms for the first 60 lines and a 1.325 ms median for a one-line
edit, including source materialization and convergence. One line was rescanned,
with 80 checkpoints and 10,560 normalized payload bytes. Run the benchmark for
current timing and retained-object memory results; budgets are 15 ms, 5 ms, and
2 MiB.

See the [changelog](CHANGELOG.md) for release history.

## License

Released under the [MIT License](LICENSE.txt).
