---
name: test-timing
description: Measures where the test suite's time goes — the async/sync wall split, the test-file load floor, whether the async phase has room to absorb more work, and the sync tail broken down by what keeps each file sync — using a script that runs the suite and writes a Markdown report. Use it on demand only, when the user asks to measure or profile the test suite, asks how big the sync tail is or whether making files async is worth it, or before and after a change meant to make the suite faster. Not a gate; never run it as part of reporting other work done.
---

# Test timing

The suite's wall time splits into an async phase and a serial sync tail, and the obvious ways to
read that split are wrong in ways that cost a session to find: the profiling flags change what
they measure, a third of the "async" figure is not tests at all, and a file's header does not
always name everything that keeps it sync. The script below does the measuring; this file is how to
read what it prints.

## Before running

- **Nothing else may be running tests.** Worktrees share one test database and one machine, and
  another session's `mix test` skews every number here. The script lists any other `mix test`
  process it finds and prints the load average; if it warns, stop and ask.
- **It runs the whole suite several times** (`main/1` in the script lists which runs), so it takes
  minutes. `--runs N` sets the number of plain runs; `--no-sweep` and `--no-trace` drop those
  sections.
- It changes nothing in the tree. It does run the whole suite, so the usual test preconditions hold.

## Running it

Run it from the repo, writing the report to the session's scratchpad directory, never into the
repo:

```bash
elixir .claude/skills/test-timing/measure.exs > <scratchpad>/test-timing.md
```

Progress and warnings go to stderr, the report to stdout.

## Reading the report

- **Wall split (plain runs)** is the only real answer to "how long does the suite take". Use the
  median. It is also the only number that proves a change worked: measure before and after with
  plain runs, never with an estimate built from the sections below.
- **Load floor.** ExUnit counts loading the test files inside the async figure, so the async phase
  can never drop below it. An async figure close to the floor means the async tests themselves are
  nearly free.
- **Concurrency sweep.** If the async column barely moves from `--max-cases 8` to `64`, the phase
  is not short of workers, and work moved out of the sync tail mostly disappears into it. If it
  falls with more cases, moved work adds wall time roughly in proportion.
- **Sync tail by blocker** comes from the trace run. `--slowest-modules` and `--slowest` both force
  trace mode (`max_cases: 1`), which is why no other section uses them: an async file's trace time
  is a serial sum that a normal run overlaps. A sync file runs serially anyway, so its trace time is
  what it really costs.
- **The bucket is every blocker a file shows, with line counts** — `config`, `process`,
  `singleton`. Read the counts, not only the bucket. `singleton ×4` in a file with `process ×43`
  means a few tests pin an app-wide key and the rest could move with a split; `singleton ×11` means
  the file is the singleton's own test. The patterns are a heuristic. The file's header is printed
  under it: where they disagree, read the file. `from the header only` means no pattern matched and
  the bucket was guessed from the header, which usually means the blocker is one call away (a
  LiveView that starts a real process).
- **A split is proven by running it, not by the report.** No pattern matching a test does not mean
  nothing blocks it: a blocker one call away never appears in the test's own code. Flip, run the
  file, then run the whole suite a few times with different seeds.
- **An async phase that is slower and noisier than it was** is not in the sync tail's sections
  at all. Compare plain runs against the older commit, alternating the two on the same seeds, then
  bisect the commits between them with plain runs. The classic cause: two async files racing a
  library's lazy one-time load for a `:global` lock, where the loser sleeps through the lock's
  backoff and finishes the phase late — which widens the spread as well as moving the median.
- **Slow tests inside sync files** are the cheapest wins. A slow test that has no blocker of its
  own, sitting in a file that is sync because of *other* tests, moves to an async file for a few
  lines. The rule is `elixir-code-review`'s `test-quality.md` §5.

## What each blocker costs to remove

- **A slow test with no blocker:** split it into an async file. Minutes.
- **`config`:** the code under test takes the value as an option (`test-quality.md` §5), or the
  tests that write config split out so the rest of the file runs async. A per-process config
  override in the `Settings` module is a test hook in `lib/` — walk its design through with the
  user before any code, with a measurement that justifies it.
- **`process`:** a process whose start-up reads the database would have to carry the test's
  sandbox access (`$callers`, passed at start), and any shared topic would need isolating. Days,
  and it changes start-up.
- **`singleton`:** no fix frees it. Only a split, moving the tests that don't touch the singleton
  out, recovers anything.

## Limits

- **CI is not measured here.** CI's runner (`runs-on` in `.github/workflows/ci.yml`) has far fewer
  cores than a developer machine. Spare async capacity found here may not exist there, so a saving
  here can be smaller in CI. The Actions tab's `mix quality` step time is the CI number.
- A single trace run is noisy for small files. The ranking of the big ones is stable; differences
  of a few tens of milliseconds are not.

## Where results go

The report is scratch. The numbers go stale with the suite. Put a result in design-log only when it
backs a decision, and then write down the decision and the figure that drove it, not the whole
report.
