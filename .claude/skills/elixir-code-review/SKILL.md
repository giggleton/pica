---
name: elixir-code-review
description: Reviews Elixir code for known architectural problems this codebase cares about — logic in the wrong module, a namespace's internals reached past its public API, a `use Boundary` declaration widened instead of a caller fixed, OTP process hygiene, test quality (brittle, duplicative, or valueless tests), and suppressed lint/security findings (credo disables, hex.audit ignores). Use this whenever the user asks for a code review, asks you to look over a diff/PR/branch, asks where some logic should live, asks whether tests are worth keeping or are brittle/duplicative, or is about to commit changes touching test files or GenServers. Also use it proactively after you yourself write or modify OTP code or tests, widen a boundary declaration, or add any lint/security suppression, before reporting the work as done.
---

# Elixir Code Review

Reviews changed Elixir code against a set of architectural rules that matter in this
codebase. Each rule lives in its own reference file so the review stays focused and the
rule set can grow without bloating this file.

## Available checks

| Check | Reference file | Applies to |
|---|---|---|
| Module boundaries | `references/module-boundaries.md` | `lib/pica/**/*.ex` |
| OTP process hygiene | `references/otp-processes.md` | `lib/pica/**/*.ex` |
| Test quality | `references/test-quality.md` | `test/**/*_test.exs`, `test/support/**` |
| Suppressions & waivers | `references/suppressions.md` | `lib/**/*.ex`, `.credo.exs`, `mix.exs` |

Read only the reference files whose "Applies to" pattern matches files in scope. Reading
rules that can't apply wastes context and tends to produce stretched findings.

## Scope

Default to reviewing **changed code only** — what the branch has committed since it left
`main`, plus everything uncommitted or untracked, since review usually runs before the commit:

```bash
base=$(git merge-base HEAD main) && { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u
```

On `main` itself the merge base is `HEAD`, so the list is the working tree's changes; on a branch
it adds the branch's commits. The base is the local `main`, which exists whether or not a remote
does: a diff against `origin/main` in a repo without one failed inside `$(…)`, and the pipeline
still printed an empty list and exited 0 — a review of nothing, reported as clean. Here a failed
`git merge-base` prints its error and stops the command with a non-zero status, so an empty list
means there are no changes, never that the command broke.

Reviewing whole files, or the whole repo, only happens when the user explicitly asks for
it. This matters because pre-existing violations are usually known and deliberate; flagging
them on every unrelated PR is how a review tool gets muted. If a changed function sits next
to an obvious violation the author didn't touch, mention it once at the end under "Pre-existing,
not from this change" rather than mixing it into the findings.

## Process

1. **Determine scope.** Get the changed files with the command under Scope. Filter to
   `.ex`/`.exs` files. If nothing
   matches any check's file pattern, say so and stop — a clean "nothing in scope here" is a
   useful answer, not a failure.

2. **Load the relevant rules.** Read the reference files for the checks that apply.

3. **Read the code with its context.** For a module under review, also open the modules it
   calls and the root module of its namespace (`lib/pica/<namespace>.ex`). Most
   judgments here depend on what the public API already offers: three lines of orchestration in
   a caller read very differently when the namespace exposes a single function that would do the
   whole thing. For a test file under review, also open the module under test and any
   lower-layer test file covering the same behavior — the layer and duplication judgments
   depend on both.

4. **Judge each candidate.** Every reference file has a "not a finding" section. Work
   through it honestly before writing anything up. Precision is worth more than recall — a
   review with one real finding and zero noise gets acted on; a review with one real finding
   buried in six stylistic quibbles gets skimmed and dismissed.

5. **Deduplicate.** Checks overlap by design. When one piece of code trips more than one
   rule, report it **once**, under the most specific check — the one whose suggested fix
   actually applies. Never file the same lines twice under two names; a report that says
   the same thing twice reads as noise and gets discounted wholesale. Each reference file
   names its own precedence in an "Overlap" section.

6. **Report** using the format below. If the diff adds a lint or security waiver, the report
   also carries that waiver's three answers from `references/suppressions.md` — what the code
   needs, what was considered instead and why it was rejected, and the invariant — even when the
   waiver itself is not a finding. A waiver whose rejected alternative was cheaper than the waiver
   is a finding on the construct, not on the comment.

7. **If findings led to code changes**, run the `docs-sync` skill before finishing — a
   fix that moves or renames logic invalidates docs the same way any change does.

8. **Record the pass for the commit gate.** Run `mix format` (so the recorded state is the
   one quality's format step will keep), then:

   ```bash
   bash .claude/hooks/commit-gate.sh mark review
   ```

   A PreToolUse hook denies `git commit` on any diff touching `test/` or a GenServer
   until this mark matches the working tree — and the mark is a hash over every changed file, so
   it goes stale if anything changes after it, because a follow-up change owes its own pass. This
   step is the **only** sanctioned way to produce the mark: running it without having done the
   review above is falsifying the record, not passing the gate.

## Report format

Order findings by severity, highest first. If there are no findings, say that in one line
and stop — don't pad the report with things that are fine.

```markdown
## Review: <branch or file list>

### <severity>: <one-line description>
**`lib/my_lib/formatter.ex:42`**

<2-4 lines: what the code does, and why it belongs elsewhere. Point at the specific
consequence in this codebase — testable only through the whole pipeline, duplicated in a
second caller, a boundary the compiler can no longer hold — not "separation of concerns" in
the abstract.>

**Suggested shape:**
```elixir
# in MyLib.Parser — the namespace that owns the rule
def tokenize(source, options) do
  ...
end

# at the call site
MyLib.Parser.tokenize(source, options)
```
```

Severity levels:

- **High** — an invariant made unenforceable: state mutated from outside the module that owns
  it, a boundary widened to admit a call that belonged elsewhere, a test that passes with the
  behavior broken. These create correctness risk, not just untidiness.
- **Medium** — logic in the wrong home but contained: reachable from one caller only, or
  duplicated across two.
- **Low** — small leaks worth noting, e.g. a predicate inlined at a call site that the owning
  module should offer.

Suggested code is a sketch, not a patch. Don't rewrite the module unless asked. If the
right fix genuinely isn't obvious — the logic doesn't clearly belong to any existing
namespace — say that and name the options rather than inventing a module.
