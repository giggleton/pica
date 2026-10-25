# Suppressions & waivers

**Applies to:** `lib/**/*.ex`, `.credo.exs`, `mix.exs` (the `:hex` project
key's `ignore_advisories` / `ignore_retirements`).

Review only suppressions the change **adds or widens**. The repo's existing waivers are
deliberate and documented; re-flagging them on an unrelated diff is how a review check gets
muted.

## The rule

This is not "never suppress." `mix quality` runs credo and `hex.audit` as a hard
gate, and a handful of findings in any codebase are genuine false positives — a call that has to stay
dynamic because the module is an archive rather than a dependency trips credo's `Apply` check, and the codebase would be worse if
it contorted itself to avoid that.

The rule is: **a waiver must be scoped as narrowly as the tool allows, and must carry a
reason that is checkable.**

## The prior question: does the code need the flagged construct at all?

Ask this before any of the findings below, because a checkable reason can justify a waiver on a
construct that should not be there. The canonical case: a `System.cmd("git", ["ls-files"])`
arrives with a narrow credo waiver and a true, checkable comment about why the inherited
environment is harmless. It passes this review. An hour later the user asks whether a shell-out
was needed to list files, and `Path.wildcard` replaces it along with the waiver and sixty lines
of code. The review asked whether the waiver was justified; nobody asked whether the shell-out was.

So for every waiver the diff adds, the report answers three things, and a **new waiver with no
answer to the second is a finding on its own**:

1. **Need.** What does the code need that trips the tool? Name the construct and the job it does.
2. **Instead of.** What alternative avoids the construct entirely, and why was it rejected? If the
   honest rejection is weak (a fraction of a second, a few more lines), the finding is "remove the
   construct", not "improve the comment".
3. **Invariant.** What keeps the flagged thing safe, stated so it can be falsified later.

## The two fields the hooks check

Answers 1 and 3 go on a `# why:` line and answer 2 on a `# instead of:` line, directly above the
waiver:

```elixir
# why: `Hex` is an archive, not a dependency, so a direct `Hex.version()` is an
#   undefined-module warning under `--warnings-as-errors`; `apply/3` keeps the call dynamic.
# instead of: `Application.spec(:hex, :vsn)` — rejected because Mix never loads Hex as an
#   application, so it answers `nil` on every machine.
# credo:disable-for-next-line Credo.Check.Refactor.Apply
```

`.claude/hooks/waiver-gate.sh` enforces the shape twice. The `Edit|Write` hook **denies** an edit
that adds a waiver without both lines and, once they are present, **asks the user** to approve the
waiver with the diff in view — the decision is theirs, not the agent's. The commit gate re-scans the
diff so an edit made through Bash cannot bypass it. Only added waiver lines are checked.

"Checkable" is the load-bearing word. A comment saying `# reviewed, safe` records that
someone looked once. A comment saying *why* it's safe — naming the invariant, the trust
boundary, or the caller that guarantees it — can be re-evaluated by the next person, and
falsified if the code changes underneath it. Only the second kind survives contact with a
codebase that keeps moving.

## Findings

### 1. A waiver with no stated reason — High

Any added `# credo:disable-for-next-line`, `.credo.exs` check moved to
`disabled:`, or `hex.audit` ignore that arrives without a comment
explaining why the flagged thing is safe.

```elixir
# finding
# credo:disable-for-next-line Credo.Check.Warning.UnsafeExec
defp list_files(directory), do: System.cmd("ls", [directory])
```

The fix is a sentence, not a refactor. Ask for the specific reason: where does `path` come
from, and what prevents it coming from a request?

### 2. A reason that only asserts, rather than explains — Medium

```elixir
# finding — records that someone looked, gives the next reader nothing
# Reviewed and safe.
# credo:disable-for-next-line Credo.Check.Warning.LeakyEnvironment
```

Compare with a reason that can be checked and can go stale visibly:

```elixir
# The command is our own pinned binary and reads only the variables named in its moduledoc;
# the caller's environment is never forwarded — see the invariant there.
# credo:disable-for-next-line Credo.Check.Warning.LeakyEnvironment
```

Report this as a request to say *why*, and quote the existing house comments as the target
register. Keep it to one line; a paragraph of process commentary per waiver is what makes a
review exhausting.

### 3. A waiver scoped wider than necessary — High

Ranked by how much it hides:

- A check moved to `.credo.exs` `disabled:` when a single call
  site was the problem — this silences the whole repo, including code not yet written.
- A file-level or module-level skip (`credo:disable-for-this-file`) where a single-line one
  would do.
- A waiver on a public entry point (`run/1`, a task's `run/1`) rather
  than on the narrow private helper that actually makes the flagged call. A waiver on the
  entry point covers everything the function grows into later.

The question to ask: **what future code does this waiver silence in advance?** A per-function
skip on `defp write_file/2` silences almost nothing. A project-level skip silences everything.

### 4. A reason that wouldn't survive the code changing — Medium

The most valuable finding in this file, and the easiest to miss, because the code is correct
*today*.

A waiver justified by "this input is never user-controlled" is only true while that stays
true. If the function could plausibly grow an argument that changes the answer, the
constraint has to be written down somewhere durable — a moduledoc invariant, or better, a
test.

The worked shape: a file read waived as "the path is always one of our own fixtures" is true
until a public function forwards a caller's string to it. In a library the caller *is* the
untrusted input. So the module states the invariant in its `@moduledoc` **and** has a test
passing a path outside the fixture directory asserting it is refused.

Flag this when a waiver's justification depends on a property of the *callers* rather than a
property of the function itself, and nothing pins that property down.

### 5. A waiver standing in for a fix — Medium, High when the construct is avoidable

Cases where the finding is real and the suppression is avoiding the work: an
`Ecto.Adapters.SQL.query` with an interpolated string skipped rather than switched to a bound
parameter, a `hex.audit` advisory ignored rather than the dependency bumped — and the general form,
a construct the code does not need at all: a shell-out where the standard library has the
function, a file read where the data is already in memory, a dynamic `apply` where a plain call
would do. The `# instead of:` line is where this shows: if the rejected alternative was cheaper
than the waiver, report the construct as the finding and the waiver as its symptom.

Note the alternative concretely. Sometimes the tool's suggested fix genuinely doesn't apply,
and then finding #2 covers it — say so in the comment.

### 6. A new `ignore_advisories` / `ignore_retirements` entry — High

An advisory ignored without a note on why the vulnerable path isn't reachable, plus a
condition for revisiting (a version to upgrade to, an upstream issue). `mix hex.audit` runs
on every `mix quality`, so an ignore is permanent until someone deliberately removes it.

## Not a finding

- **Existing waivers the change didn't touch.** They are decisions already made.
  `grep -rln 'credo:disable-for' lib/` is the authority on where they are; a list
  in prose rots.
- **`.credo.exs`'s `enabled:` allowlist.** This codebase adopts credo checks deliberately
  rather than taking the plugin's defaults, so a check simply not being listed is the design,
  not a suppression. Only a check *moved* from `enabled:` to `disabled:` is a change worth
  reviewing.
- **`@moduledoc false`.** A statement about public surface, not a silenced check.
- **Test-only pragmas**, including the `@spec`'d type-erasing identity helpers that let
  guard tests pass a deliberately wrong type without tripping the set-theoretic type checker.
  That pattern is sanctioned in CLAUDE.md.

## Judgment calls

The question that resolves most cases: **if this function were changed next year by someone
who never read this review, would the waiver still be correct — and if not, would anything
stop them?**

If the honest answer is "it would silently become wrong," the finding isn't the waiver. It's
the missing invariant: a `@moduledoc` line, a guard, or a test that fails when the assumption
breaks. Ask for that rather than for the waiver's removal.

One report-level observation worth making if it applies: a change that adds several waivers to
one module usually means the module is doing file or binary work the tools can't reason about,
which is fine — but it's worth one sentence noting the concentration, rather than filing the
same finding six times.

## Overlap with other checks

A waiver on code that also violates a module boundary or puts business logic in a GenServer callback is
two separate problems. Report the structural one under its own rule; report the waiver here
only if the suppression itself is scoped wrong or unexplained.
