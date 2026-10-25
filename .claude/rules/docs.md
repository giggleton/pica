---
paths:
  - "CLAUDE.md"
  - ".claude/rules/**"
  - ".claude/skills/**"
  - ".claude/hooks/**"
  - "notes/**"
  - "README.md"
---

# The documentation system

The docs-sync skill is the procedure; this file is the shape. The failure it guards against: every
wrong claim in a set of agent-facing docs turns out to be a count, an ordinal, a step number, or a
sentence restated across surfaces, and the file that rots fastest is the one loaded every session.

## Rules

- **One home per kind of fact.** Cross-cutting rules and the status map live in CLAUDE.md. An
  area's invariants live in its `.claude/rules/<area>.md`, under `## Rules`; its mechanism in the
  module's documentation (an API module's moduledoc, an internal module's opening comment), never
  restated in the rules file. Decisions with rejected alternatives live in design-log §4; a
  change's story in its commit message, indexed by one §6 line; procedure in a skill. Only the
  rules files with no module behind them (this one, `dependencies.md`) keep a `## How it works`.
- **Short entries, read by name.** A §4 entry is about 150 words: the decision, a sentence or two
  of why, one line per rejected alternative. A §6 entry is one line: the date, a title, the
  commit, and the §4 entries it settled. Nobody reads the design log whole: a session orients from
  its plan's "Where we are", a few hundred words, and reads the §4 entries a rules file or the plan
  names, by their opening words. Context is the cost: every surface a fact is written to is also
  read back.
- **No count, ordinal, size or code-mirrored list in prose.** Point at the thing (`quality_steps`
  in `mix.exs`, a directory) or refer by label; every such number drifts.
- **No sentence about deployment state.** The repo cannot show which keys are set or which flags
  are on in production. Say where to look; never assert the value.
- **`mix tack.rules_check` is the ratchet.** CLAUDE.md may not exceed the line budget in
  `.claude/rules/BUDGET`; every `paths:` glob must match an existing file; the count of lib files
  no glob covers may not rise. Run `--tighten` after a slim. **Raising a budget is the user's
  decision**: the edit hook (`.claude/hooks/waiver-gate.sh`) stops on any BUDGET edit that increases
  a number and asks; the agent never raises one on its own. The alternative is almost always to move
  the text into an area file, or to add a glob.
- **A rules file's `paths:` mirror the tree.** Prefer a directory glob to a list of files. When a
  file moves, grep its old path as well as its old module name; the gate fails on a glob that
  matches nothing, and on a file that leaves every glob. A `dir/**` glob does not match the sibling
  `dir.ex`, so a namespace root needs its own entry beside its directory (`core.ex` + `core/**`).
- **Size a rename before making it: `mix xref callers Mod` for the code, grep for the prose.** The
  compiler's cross-reference data answers the one question grep cannot — which references the build
  will catch on its own — and it is exact where a text search guesses (it sees through aliases,
  `defdelegate` and macro expansion). It is also blind to most of a repo's surface: doc and comment
  prose, rules files, skills, config comments, and **`test/`**, whose files are not in the app's
  compile artifacts. So it sizes the job rather than doing it. Run `mix compile` first, since xref
  reads build artifacts. `mix xref callers` takes a module, never a function, so for a partial
  extraction it sizes the whole module and grep does the per-function work — complete only when no
  file `import`s the module or aliases it `as:` another name, which is the first thing to check.
- **A move keeps an alias's tail; a rename changes it; credo charges for both.** Moving `App.X`
  under `App.Core` edits only `defmodule`, fully-qualified references and brace-group alias lines,
  since `alias App.Core.X` still binds `X`. Renaming the last segment moves every bare call site
  too, so first confirm no file aliases both the old name and another module with the same tail.
  Then sweep by hand what neither the compiler nor a `\bApp\.X\b` grep reaches: `…Test` module
  names, templates, and — when the old name is an English word — string literals and prose.
  Budget a tree-wide alias pass: `AliasOrder` sorts a brace group on its *first* member's full
  name, downcased, so removing or renaming that member can move the whole line past its neighbours,
  and the churn lands in lines the change never touched.
- **Code and its rules file change together.** The commit gate denies a commit whose diff changes
  code inside an area's globs without changing that area's rules file, unless the docs mark is
  current — docs-sync ran against this exact diff and decided the rules needed nothing. A docs-only
  commit is exempt. The same `paths:` list tells the harness what to load and the gate what must
  move together.
- **A caveat that names reasons loses only the reason that died.** Before deleting a doc sentence
  because a change made it obsolete, read every reason it gives; a sentence often covers two cases,
  and the change killed one. Drop the dead clause and keep the sentence.
- **A claim about a relationship is re-checked when the relationship changes, not when its
  paragraph is touched.** Prose saying which way a dependency runs, who calls whom, or what a
  declaration permits is checked by nothing: the compiler checks the `use Boundary` line, not the
  paragraph beside it, and `mix docs --warnings-as-errors` checks that references resolve, not that
  they are true. A change that inverts an edge greps for the prose describing that edge (both
  module names), not only for names that moved.
- **Move, don't rewrite**, when restructuring docs: every sentence keeps a home, and the diff is
  checkable against the old text.
- **A rename updates the evergreen surfaces and leaves the dated ones alone.** The rules files,
  the skills and design-log §1–§5 describe the tree as it is, so they take the new name. A §6
  milestone entry describes what the tree was called when that change happened, so it keeps the
  old one — rewriting it would make the history false and `git log -S "<old name>"` useless.

## How it works

CLAUDE.md is the always-loaded file, so it holds only what every session needs: the cross-cutting
rules and a status map naming each area's rules file. Each area's invariants live in
`.claude/rules/<area>.md` behind a `paths:` frontmatter, so they load only when a matching file is
read (Claude Code's path-scoped rules). `mix tack.rules_check` runs as a `mix quality`
step so the root file cannot regrow and the globs cannot rot silently. When an area's invariants
grow past a few sentences, that is the signal to give it a rules file and a status-map line.
