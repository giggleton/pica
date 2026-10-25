# CLAUDE.md — pica

Guidance for Claude Code (or any agent) working in this repo.

## What this is

Pica measures text from font files for Elixir: it shapes strings with HarfBuzz's Rust port
(harfrust) through a Rustler NIF and returns each glyph's id, cluster and advances, plus font-wide
metrics and glyph boxes, in font units or at a caller's scale. Nothing is drawn. Its first consumer
is Giggly (`~/repos/giggly`), which must match R's svglite widths; Pica never depends on it.

## Where the documentation lives

- **Area rules** (`.claude/rules/*.md`) — one file per area of the code, each with a `paths:`
  frontmatter so it loads only when a file matching its globs is read. **A feature's invariants
  live there, not here; its mechanism lives in the module's documentation.** This file holds
  only what applies to every session, plus the status map below. A change to an area updates its
  rules file; this file changes only for a cross-cutting rule or a status-map line.
- **[notes/design-log.md](notes/design-log.md)** — the design overview and decision log. **It is
  reference, not reading:** orient from the plan's "Where we are", and read a §4 entry when a rules
  file or the plan names it. A decision with its rejected alternatives goes in §4 (about 150
  words); a milestone is one §6 line naming its commit, whose message tells the story; open
  questions go in §7.
- **Plans do not live in this repo.** A working plan file goes in **`~/.claude/plans/`**, never
  under `notes/` and never inside a worktree — it is scaffolding for the current work, its "Where
  we are" a few hundred words, not a documentation surface. Anything durable a plan contains (a
  ratified decision, a rejected alternative and its reason) must be copied into design-log.md §4
  **before** the work is reported done, because that is the only copy that survives. The plan
  this package was started from is `~/.claude/plans/pica/text-shaping-package.md`.
- **Skills** (`.claude/skills/`) — task-triggered instructions: `dependency-updates` (taking
  anything `mix hex.outdated` offers — read the package diffs, never trust semver or the
  changelog), `docs-sync` (run after any substantive change, before reporting done — routes the
  change to the doc surfaces it must update), `elixir-code-review` (run before reporting done on
  any change touching `test/` or a GenServer — and on any new lint/security waiver; not only when
  a review is asked for), `test-timing` (measuring the suite, on demand only). **`docs-sync` and
  `elixir-code-review` are harness-enforced**: `.claude/hooks/commit-gate.sh` (a PreToolUse hook)
  denies `git commit` on a diff touching those gated paths until the review and docs passes are
  marked for its exact state.
- Module documentation is the per-module contract and is kept accurate; trust it: an API
  module's `@moduledoc`, or the comment block at the top of an internal module.

## Status map

Everything below is **built and merged to `main`** unless marked otherwise. Histories: the commit
messages, indexed in design-log.md §6. Each line names the area's rules file, which carries its
invariants. Add a line here when an area gets its rules file; nothing else about it belongs here.

- **Dependencies, toolchain, the quality gate's steps, lint and security waivers** —
  `.claude/rules/dependencies.md`; the `dependency-updates` skill.
- **The documentation system** (what goes where, the ratchet) — `.claude/rules/docs.md`; the
  `docs-sync` skill.
- **The public API** (`Pica`, `Pica.Font`; loading built so far, decisions in design-log §4) —
  `.claude/rules/api.md`.
- **The NIF** (`Pica.Native`, the crate in `native/pica`) — `.claude/rules/native.md`.

## Approach & architecture

- **The compiler holds the library's shape.** The architecture is declared with `boundary`
  (`use Boundary` in each domain's root module; `compilers: [:boundary]` in `mix.exs`), so a
  forbidden reference is a compiler warning and therefore a gate failure under
  `--warnings-as-errors`. Every boundary is strict (the `mix.exs` default, pinned by
  `boundary_declarations_test.exs`), so a boundary's `deps:` is the whole of what it may call,
  outside libraries included. `Pica` is the root; every domain is its own boundary beneath it,
  carved when its first module lands, and its `deps:` is its contract. What boundary cannot see —
  the standard library — the `CorePurity` credo check covers over `lib/`: no clock, config,
  unseeded randomness, process or IO, an impure module excluded by name in `.credo.exs` with its
  reason. **`mix boundary.spec` prints the graph**, and no list here restates it. Widening a
  boundary's `deps:` or `exports:` is a decision for the user, and
  `.claude/hooks/waiver-gate.sh` stops the edit until it has been explained in conversation
  (`.claude/rules/dependencies.md`).
- **Fonts are read in Rust, never in Elixir.** The NIF reads, decodes and shapes; the Elixir side
  validates options, names errors and holds the registry (`.claude/rules/native.md`).
- **Expected values come from outside tools** — fontTools, `hb-shape`, R — never from Pica's own
  output, and never worked out by hand (design-log §5).
- **The public API raises on misuse; everything beneath it is assertive.** Public functions
  validate their options with NimbleOptions. The functions beneath take already-validated data,
  return **plain structs** or tuples, and raise (`FunctionClauseError`, via guards) on programmer
  error. Validation uses guards (incl. custom `defguard`s) rather than `cond`. `:none` is the
  "absent" sentinel where one is needed, not `nil`.

## Conventions

- **Never commit, push, merge or publish without the user's express authorization for that act.**
  It covers only the act it names, once: "commit" is not "push", and a request to make a change
  authorizes neither. Never prompt the user to commit. A commit message: subject, wrapped body.
- **Quality gate — run `mix quality` before every commit and keep it green.** It runs the
  `quality_steps` list in `mix.exs` in order and **stops at the first failing step**, ending with a
  `❌ mix quality FAILED at step: <name>` banner; CI runs the same list with `mix quality --check`.
  Why each step is there is in `.claude/rules/dependencies.md`. The two failures ordinary work
  hits: `deps (unused)`, fixed with `mix deps.unlock --unused`; and a `hex.audit` advisory against
  an unchanged tree, which goes to the user — never a skipped step.

  **Run `mix quality` bare — never pipe it (or any single step) through `tail`, `head`, or
  `grep`.** A pipe hides the failing step's output and makes the shell report the *pipe's* exit
  status (`0`), masking the gate's failure. When a step fails, read the output directly ABOVE the
  final `❌ … FAILED` banner. To iterate on one check in isolation, run that single `mix` or
  `cargo` command directly — still bare.
- **Merging a feature branch:** if the branch has just one commit, merge it fast-forward (no merge
  commit). Use a `--no-ff` merge commit only when the branch carries two or more commits.
- Work in **small, verifiable increments** and keep the suite green. Prefer async tests wherever
  possible; a file that is `async: false` says in its header what stops it.
- **Document the public API, and mark everything else as not API.** The API is what a user
  calls. An API module has a `@moduledoc`; an internal module has `@moduledoc false` and keeps its
  documentation as a comment block at its top. Every public function has a `@spec` and says
  whether it is API, wherever it is: a `@doc` string, whose examples run as doctests, or
  `@doc false`, its explanation a comment. A function that is not API is tested by ordinary
  tests, never doctests. Private functions (`defp`) don't need `@doc`; clarify them with a brief
  comment when non-obvious. API docs never mention Giggly or R; a guide may.
- **Follow credo conventions.** If credo flags a style requirement, remember that and don't make
  the same mistake again. **A new lint or security waiver stops and asks the user**, a Rust
  `#[allow]` included — `.claude/rules/dependencies.md`.
- **No capture-operator anonymous functions.** Always write anonymous functions as
  `fn descriptive_name -> body end` — never the `&`/`&1` shorthand (e.g. `& &1.id`, `&(&1 + 1)`).
  `&Mod.fun/arity` references are ok. Prefer descriptive argument names over positional `&1`.
- **Zip and map in one pass:** `Enum.zip_with/2,3`, never `Enum.zip` piped or passed into
  `Enum.map`. `PicaCredo.Check.ZipMap` (`.credo/checks/`) fails the gate on it.
- **Descriptive names; no abbreviations or single letters**, in Elixir and Rust alike. Spell names
  out: `position` not `pos`, `glyph_id` not `gid`, `value` not `v`. Never single-letter variables.
  Spell out domain terms in code too; acronyms are fine only in prose where defined. Define a font
  term in plain language the first time it appears in a doc or a message to the user.
- **One name per module kind; no two in a family share a last segment** — a shared tail collides
  silently at `alias`. A process module ends in `Server`, `Worker`, `Watcher` or `Poller`; a
  singular name is a pure type or fold, its plural the context owning the table.
- **Decisions go to the user one at a time**, in plain language, with an honest recommendation
  first.

## Publishing

- **Claude never has access to the keys** — publishing to Hex (`mix hex.publish`), and anything
  else that needs a secret, is a step the user runs.
- **A release goes in one order**: tag and push; CI builds and attaches every binary; then
  `mix rustler_precompiled.download Pica.Native --all --print` writes the checksum file; only then
  publish to Hex. Publishing before the checksum file is regenerated makes every user's download
  fail its check, and nothing but this order prevents it.
