# Antares

Incremental syntax highlighting for Rouge, with measured per-lexer compatibility.
The only runtime dependency is `rouge ~> 5.0`; document storage and colors belong
to the caller. Ruby 3.1 or later is supported.

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

For a local checkout, `gem build antares.gemspec` creates an installable gem;
install that file with `gem install ./antares-0.1.0.gem`. Publication is separate
from building and is not performed by tests or CI.

## API and strategies

Line indices are zero based. Providers return one valid UTF-8 logical line each,
preferably including its newline. Missing separators are added to non-final
lines. A trailing empty logical line returns an empty token array. Tokens contain
text, not offsets: sum `text.bytesize` for byte offsets, or `text.length` for
character offsets. Returned rows/pairs/text are frozen.

Call `edit` **after** updating the provider, with the old removed line count and
new inserted line count. `frontier` is the first line not yet proven current;
`advance(until_line: 200)` lets an event loop schedule incremental progress.
`last_scanned_lines` reports actual lexical work, and `checkpoint_bytes` reports
normalized checkpoint payload bytes. Highlighter instances are not thread safe.

| Strategy | Behavior |
|---|---|
| `:auto` | Uses the bundled, exact-Rouge-version compatibility verdict. Unknown versions and lexers use `:window`. |
| `:incremental` | Forces state snapshots and convergence. Use for certified lexers; forcing a failed lexer can return incorrect classifications. |
| `:window` | Restarts from root up to 200 lines before the requested range. Explicitly approximate for long-running constructs. |
| `:full` | Runs ordinary Rouge over the complete bounded document after every edit; use for exact results on small files with failed incremental lexers. |

`Antares.compatible?(Rouge::Lexers::Python)` returns `:incremental` or `:window`.
Every registered lexer has an entry in `COMPATIBILITY` and a reproducible result
in `COMPATIBILITY_DETAILS`; see the [complete compatibility table](docs/compatibility.md).
Do not infer support merely because a lexer subclasses `Rouge::RegexLexer`.

## State, limits, and correctness

Antares reuses Rouge's rule interpreter and deep-copies persistent instance
state, including nested arrays/hashes, their subclasses, delegate lexers, heredoc
queues, sets and structs. Immutable rule templates are shared. Per-call scanners
and callbacks are excluded. Dynamic rule closures compare conservatively by
identity, and opaque state is rejected rather than shallow-copied.

Checkpoints are placed approximately every 64 completed lines, **after entire
rule callbacks**. State fingerprints between checkpoints allow early convergence;
edits shift cached suffixes and invalidate stale boundaries. Calling
`continue_lex` separately for each line is insufficient: Rouge regexes may consume
several lines or inspect surrounding text. The driver therefore materializes a
bounded source String on demand, uses a fixed-anchor scanner, and resumes lexical
work at a checkpoint. It retains no array of provider lines. Source materialization
is O(document bytes) after an edit and is included in reported timings.

Some grammars are inherently nonlocal: for example, adding a distant `=end` makes
Rouge classify an earlier unmatched Ruby `=begin` differently. These lexers fail
the delayed-closure probes and select `:window`; the fallback is intentional.
Other failures are classified as token mismatch (lookahead/state dependencies) or
unsupported custom stream driver. The matrix is an empirical corpus guarantee,
not a proof for every possible input or non-default lexer option.

Default limits are 100,000 lines, an 8 MiB source snapshot, 16 KiB per line,
256 KiB per checkpoint, and 250 ms per scan. Configure them with `max_lines`,
`max_bytes`, `max_line_bytes`, `max_checkpoint_bytes`, and `max_seconds`.
Exceeding a source limit switches to window mode; oversized individual lines and
timed-out ranges return plain-text tokens without truncating content.
`fallback_reason` explains the transition. These limits also apply to `:full`.

## Development and verification

```sh
bundle install
bundle exec rake test
bundle exec ruby script/compatibility --write
BUDGET=1 bundle exec ruby --yjit bench/highlighting.rb
```

The matrix enumerates every Rouge lexer, uses three source variants based on
Rouge's bundled MIT-licensed demos, applies 50 deterministic insert/delete/replace
mutations to each, and compares all per-line tokens against a fresh full lex.
Three extra distant-closure probes catch backward reclassification. The test suite
reruns the complete matrix. `MUTATIONS=5 ruby script/compatibility python rust`
is a short diagnostic run; `DETAILS=1` prints the full JSON failure details.
Only full runs with 50 or more mutations may replace the bundled matrix.

Scheduled CI updates Rouge, regenerates the matrix, reruns tests, and uploads the
generated source/table for review. It does not silently publish a gem or modify a
release. Regular CI tests Ruby 3.1–4.0 on Linux, macOS and Windows.

On the development Mac with Ruby 4.0.0/YJIT, the 5,000-line Python benchmark
measured 10.771 ms for the first 60 lines and 1.325 ms median for a one-line edit
including source materialization and convergence. One line was rescanned, with
80 checkpoints and 10,560 normalized payload bytes. Run the benchmark for current
timings and retained-object memory; budgets are 15 ms / 5 ms / 2 MiB.

Released under the [MIT license](LICENSE.txt).
