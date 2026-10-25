# Repo-local credo checks

A check in this directory makes a rule this repo already states in prose — in CLAUDE.md, a
`.claude/rules/*.md` file, or a skill — into a gate failure. `.credo.exs` loads the directory
through `requires:` and enables each check by name, one at a time, like any other.

Why here and not `lib/`: `lib/` compiles into the release, a dev-only lint has no business there,
and a check under `lib/` would want a boundary declaration and count against `rules_check`'s
uncovered-file budget.

The checks the harness ships — `Tack.Credo.Check.NoCaptureOperator`, `PublicFunctionDoc`,
`SyncTestBlocker`, `AsyncEnvMutation`, `SleepInTest`, `TimestampRewriteInTest`, `CorePurity` —
are compiled from `dev/tack/`, Tack's code copied in, and need no copy here. Add a file here
only for a rule specific to this repo.

Four things hold a new check together (`.claude/rules/dependencies.md` has the full version):

1. **Don't restate what the `boundary` compiler already holds.** Credo is for what Boundary
   cannot see: the standard library inside the pure core, and conventions with no type-level shape.
2. **Scoping lives in `.credo.exs`**, in the check's `files:` filter with its reason beside it. A
   per-check `excluded:` string is resolved as a file or directory, not a prefix — use a regex.
3. **Test it in both directions.** A check that fires on everything and one that fires on nothing
   both pass a one-sided test. The tests go in `test/credo_checks_test.exs` (`use Credo.Test.Case`,
   `to_source_file/1`, `run_check/2`, `assert_issue/1`, `refute_issues/1`), the one file that
   `Code.require_file`s the checks in this directory, and only one may: requiring the same source
   twice in one VM redefines the module, and the warning fails the gate. It starts the `credo`
   application the helpers need, and asserts an issue's line, column and trigger as well as that
   it is raised.
4. **Size a candidate by running it, scoped as its sibling is, never by grep.** A grep ignores the
   scoping and matches prose, including the comment documenting the rule being counted.

`mix format` covers this directory (`.formatter.exs` lists `.credo/**/*.ex`).
