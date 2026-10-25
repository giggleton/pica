---
name: dependency-updates
description: How to take a dependency update in this repo — read the package diff rather than trusting semver or the changelog, trace every change into our own tree, prove it with the suite, and follow through on the gate. Use this whenever the user asks what's outdated or to run `mix hex.outdated`, asks whether to take a specific version, when a `mix hex.audit` advisory forces a bump, or before any edit to `mix.lock` or a version constraint in `mix.exs`.
---

# Dependency updates

**The rule: read the diff.** A version number, a changelog entry, and a green `mix quality`
are all *claims* about what a dependency now does. Only the diff is evidence. Each of those
three claims has been wrong before, and each cost real time.

It cuts both ways, and the second half is the one that gets forgotten: reading diffs stops bad
bumps **and** clears harmless ones. It is what lets you say "this is inert, and here is why"
instead of "this looks fine".

## The pass

### 1. See what's offered

```bash
mix hex.outdated
```

It **exits non-zero whenever anything is updatable**. That is information, not a failure —
don't report it as one.

Both this and `hex.package diff` reach `repo.hex.pm`. Under a sandboxed shell they fail with
`nxdomain`; rerun with the sandbox disabled. **hex.pm is not a vendor API** — a standing "ask
before live external calls" rule is about the product's own providers, not the package registry,
and `mix deps.get` already talks to it.

### 2. Read each diff

```bash
mix hex.package diff oban 2.24.0..2.24.1
```

Three mechanical rules, all learned the hard way:

- **Never pipe it through `head`, `tail` or `grep` when you mean to read it** — same rule as
  the quality gate. A `| head -300` on a diff whose first files are rebuilt asset bundles reads
  convincingly as "this release is assets only" while every changed source file sits below the
  cut.
- **On a big diff the task truncates itself — fetch both versions and diff them locally.**
  `mix hex.package diff` streams through `Mix.Shell.cmd`, which dies with an `ArgumentError`
  from `:io.put_chars` partway through a large write. Redirecting to a file does not save you:
  a plain `> out.diff` can show five changed files where the release really changed thirty,
  with the crash buried at the end of the file. When the package carries a big generated
  payload (model catalogs, vendored bundles), do this instead:

```bash
mix hex.package fetch some_dep 1.21.1 --unpack --output /tmp/some_dep-1.21.1
mix hex.package fetch some_dep 1.22.0 --unpack --output /tmp/some_dep-1.22.0
diff -rqN /tmp/some_dep-1.21.1 /tmp/some_dep-1.22.0          # inventory
diff -ruN /tmp/some_dep-1.21.1/lib /tmp/some_dep-1.22.0/lib  # source only
```

  It is offline after the fetch, it cannot truncate, and it lets you diff a generated
  catalog with a script instead of reading it (see step 3).

- **Inventory first, then read.** Vendored bundles and minified JS swamp the source in
  packages like ex_doc and phoenix_live_dashboard:

```bash
mix hex.package diff ex_doc 0.40.3..0.40.4 | grep '^diff --git'
```

Then read the source files only:

```bash
mix hex.package diff ex_doc 0.40.3..0.40.4 | awk '/^diff --git/{p = ($0 ~ /\/(lib|src|mix\.exs)/)} p'
```

The changelog rides *inside* the diff — read it, but as the author's summary of their own work.
A one-line "prevent newer execution from overwriting" can leave out that a call which used to be
a no-op now raises.

### 3. Trace every change into our tree

For each changed public function, module, behaviour callback, struct field, or return type,
grep for it. Four places we are reachable, ordered by how often each is missed:

- **`test/` — most likely to break.** Tests are the only code that calls a dependency's
  internals *on purpose*.
- **`deps/` — another dependency may use the one you moved.** A return type that narrowed is
  fine if its one caller discards the return — but that is something you *read*, not assume.
- **The dependency's own `mix.exs`, in the diff — a moved requirement is a second update
  riding along, and it can be the whole substance of the bump.** Diff the transitive package
  **before** deciding, not after: it is part of this update, and `mix hex.outdated` never
  mentions it.
- **`config/` and `mix.exs`** — a constraint that now excludes the version, or a pin whose
  tripwire has finally come out.

**A generated data payload is diffed by script, against the entry your config actually
names.** A large catalog is far too big to read and too noisy to eyeball. Load both versions and
compare the one record you depend on — and resolve it the way the library does (follow its
aliases; index into the right provider block rather than grepping an id that appears under many).

Changes that earn a specific grep:

| In the diff | Grep for |
|---|---|
| A return type narrowed or widened | pattern matches on the old shape (`{:error,` on that call) |
| A struct field removed | the field name, in `deps/` as well as `lib/` |
| A new precondition on a query or call | direct callers — then **run** them |
| A function deleted or renamed | the old name across `lib/`, `test/`, `deps/` |

### 4. Prove it; don't argue it

Reasoning tells you where to look. The suite tells you whether you were right.

```bash
mix deps.update oban
```

One package at a time — **never `--all`** — so a failure stays attributable.

**Even one package unlocks its whole subtree, so read the lock diff after every update.** A
single `mix deps.update` can move several transitive packages, including a major admitted by an
open-ended `>= x.y.z` requirement. Put back the old lock line of any rider the new version does
not need, re-run `mix deps.get` to prove the tree still resolves, and take it later on its own
diff.

**A green suite cannot see a number going to zero.** A bump that touches something that computes
a figure we report rather than a behaviour we assert — a cost, a count, a price — can pass every
test while the figure reads `0.0`. Probe it offline before and after: a canned response through
the real call path and our own reader, diffed across versions. Keep that probe as a test.

**Stale beams lie.** When a dependency branches on another dependency at *compile* time
(`Code.ensure_loaded?` + `function_exported?`), an incremental `_build` keeps the branch it was
compiled with, and the tree behaves as neither version. `mix deps.compile <dep> --force` after
bumping either side.

**A page no test renders is proved by calling what it calls.** A green suite says nothing about a
dashboard mounted admin-only with one test asserting a link to it; a bump that changes what the
page calls compiles clean and raises on render. Call the changed functions directly.

When you report, keep the seam visible between what you reasoned and what you ran.

### 5. Follow through

- **`mix quality`**, bare.
- **`mix docs --warnings-as-errors`** when ex_doc itself moved — it is dev-only and outside
  the gate, so nothing else would catch a doc build it broke.
- **Check the lock diff for transitive movement**, and confirm in `mix.lock` that a raised
  requirement did or did not move anything.
- If the project keeps a third-party attribution file, regenerate it: a version bump makes it
  stale.

## Reporting

For each package, three things: **what actually changed**, **whether it reaches us**, and
**how you know** — read, grepped, or ran. "Up to date" is not a finding. "Five of six are
unreachable from our code, and here is why for each" is the finding.

## Documenting

A design-log §6 line (the story in the commit message) when the update changed behavior we
depend on, broke something, or taught something worth not rediscovering, and the lesson itself in
the rules file or skill where the next update will meet it. Not for a routine bump that touched nothing — but say in your
report that you decided that, rather than leaving it silent. Then `docs-sync` as usual; the bump
also owes `elixir-code-review` if fixing it touched a gated path.

## Not this skill

- **Adding a new dependency** — license review, attribution, and justifying the dependency at
  all are a different job with a different shape.
- **`mix hex.audit` findings** are a gate step and run on every commit. Triaging a false
  positive belongs in `mix.exs`'s `ignore_advisories`, with a removal condition. But when an
  advisory forces a real bump, this skill is how you take it.
