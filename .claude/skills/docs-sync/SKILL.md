---
name: docs-sync
description: Keeps every documentation surface current after a change — CLAUDE.md, the .claude/rules area files, notes/design-log.md, the ExDoc guides, moduledocs, and the skills themselves. Run this AFTER completing any substantive change (feature, refactor, rename, schema/config change, decision), BEFORE reporting the work done or when the user asks to commit. Not needed for trivial fixes that change no behavior, name, or claim.
---

# Docs sync — after a change, before "done"

Documentation drifts one skipped update at a time; every stale claim traces to a change that
shipped without its doc update. The rule: **docs update in the same change** — or you say
explicitly, when reporting done, what was deferred and where. Never silent.

## Step 0 — if the change touched code, review it before documenting it

If the change touched `test/` or a GenServer — or added any lint or
security waiver — run the **`elixir-code-review`** skill *first*, and act on what it finds.
Two reasons it belongs here rather than being left to judgment: its findings routinely change
the code, and docs written before that describe a draft; and this skill fires reliably on
"before reporting done" while a review is easy to skip at exactly the moment you want to wrap
up. If it's already been run for this change, carry on.

**Not a loop.** `elixir-code-review`'s "If findings led to code changes" step says to run
docs-sync — that step is *this* run, continuing at Step 1. Don't re-invoke either
skill from the other a second time.

## Step 1 — grep for dead names (the highest-value check)

If the change **renamed, moved, or deleted** anything referenceable — a module, function,
route, config key, column, mix task, worker, section label, flag — grep the old name
across every doc surface.

If you have not already, `mix xref callers <OldModule>` first (after `mix compile`): it names
the call sites the compiler will catch, so whatever the greps below turn up *beyond* that list is
the prose only you can fix. The ratio is usually the opposite of what it looks like — most
references to a name live in text, not code. xref cannot see `test/`, so the greps still stand on
their own there.

The two greps:

```bash
grep -rn 'OldName' CLAUDE.md .claude/rules/ .claude/skills/ notes/ README.md
grep -rn 'OldName' lib --include='*.ex'
```

(`lib` is the second sweep because moduledoc/`@doc` *prose* references other modules by name.)

**A move out of a module that survives needs one more grep: the module it left.** An extraction
leaves no dead identifier behind. The moved functions are easy to find, but a sentence saying the
old module owns the moved responsibility still names a live module, and the sweep above passes
over it. Grep the source module's name and read each hit for a claim of ownership it no longer
holds. Fix every hit or justify it.

**Two commands, and it must stay two — do not "tidy" them back into one.** `--include`
filters *every* path given to that `grep`, not just the one it trails. Folded together, the
`*.ex` filter excludes every `.md` surface in the list, and the command reports a confident
`clean` while the stale claims sit untouched — the exact failure this step exists to catch,
wearing a pass.

## Step 2 — route the change to its doc surfaces

| The change | Update |
|---|---|
| An area's invariant (a rule the code must keep) | The area's **`.claude/rules/<area>.md`**, under `## Rules`, one or two sentences each. It is path-scoped, so it loads only when that area's code is read; that is where the invariant belongs, never CLAUDE.md. An area without a rules file yet gets one, plus a status-map line in CLAUDE.md. How the area works is not restated there: it is the module's documentation (the row below). |
| Milestone-worthy feature or refactor | **One line** in **notes/design-log.md §6**: the date, the commit's subject as its title (so `git log --grep` finds it), and the §4 entries it settled. The story goes in the commit message, the decisions in §4, the invariants in the rules files. CLAUDE.md changes **only** for a cross-cutting rule or a status-map line. |
| A decision with a rejected alternative | **design-log.md §4** (the "why, so we don't relitigate" log), about 150 words: the decision, a sentence or two of why, one line per rejected alternative. |
| New/changed module or public function | Whether it is API (CLAUDE.md, Conventions), then its documentation accurate to the *final* behavior (not the first draft's): an API module's `@moduledoc` and an API function's `@doc` and doctests; an internal module's opening comment under `@moduledoc false` and a non-API function's comment under `@doc false`; a `@spec` on every public function. |
| Schema, migration, lifecycle/status change | The persistence guide under `guides/`, if the project has one; otherwise the area's rules file. |
| Supervision tree / process shape | The processes guide under `guides/`, if the project has one; otherwise the area's rules file. |
| A new mix task, cron schedule, or ops workflow | The ops skill or rules file that lists them — those tables are live doc surfaces. |
| A new `mix quality` step | `quality_steps` in `mix.exs` **is** the list; CLAUDE.md gets a sentence only if the step needs explaining. |
| A new guide or doc file | README's Documentation section + `mix.exs` `extras:`. |

**§6 is an index, not a record:** one line per milestone, never a paragraph. A session
orients from its plan's "Where we are" and reads §4 entries by name, never the whole log.

## Step 3 — skills are docs too

If the change invalidates a claim in any `.claude/skills/*/SKILL.md` (a task name, a
config key, a sanctioned-exception list, a trigger path), update the skill
in the same change. When in doubt, grep step 1 already covered `.claude/skills/`.

## Step 4 — prove the doc references resolve

Run the reference check (bare, never piped — same rule as the quality gate):

```bash
mix docs --formatter html --warnings-as-errors
```

ExDoc re-resolves every cross-reference in moduledoc/`@doc` prose, so this catches what
step 1's grep can't: a reference that *looks* alive but points at a private function, a
hidden module, or a callback/type missing its `c:`/`t:` prefix. It cannot be scoped to a
subset of files — it always walks the whole app — but the tree is kept at **zero
warnings**, so any warning it prints was introduced by the change at hand: fix it before
reporting done.

The fix patterns: `c:Mod.fun/arity` for callbacks, `t:Mod.type/arity` for types; for a
private function or a hidden module (`@moduledoc false`), link the containing/nearest public
module and demote the rest to plain prose or a file name, which ExDoc never tries to autolink.

## Step 5 — record the pass for the commit gate

Run `mix format` if any step above edited files, then:

```bash
bash .claude/hooks/commit-gate.sh mark docs
```

A PreToolUse hook denies `git commit` on any diff touching `test/` or a GenServer
until this mark (and elixir-code-review's) matches the working tree, and on any diff that changes
code inside an area's `.claude/rules/<area>.md` globs without changing that rules file, until this
mark alone is current — the mark is how you say "I looked, the rules needed nothing". The mark is a
hash over every changed file, so it goes stale when anything changes after it — a follow-up change
owes its own pass. This step is the **only** sanctioned way to produce the mark: running it without
having done the routing above is falsifying the record, not passing the gate.

## Calibration

- **Substantive** = changes behavior, a name, a shape, or a documented claim. A typo fix,
  a test-only change, or a refactor invisible outside its module needs nothing.
- Don't pad design-log.md with entries for trivia; do log anything you'd want the next agent
  to know *why* about.
- A decision a later one replaces is deleted from the record, never marked superseded (Steve):
  two opposite claims in the log mislead the next reader, and git history keeps the old text.
- When reporting the work done, name the doc updates made (or explicitly deferred) — the
  user should never discover doc drift later.
