# Test quality

Tests are the safety net for a functional core that claims determinism and for a quality gate
that runs them with `--warnings-as-errors`. A test earns its place by **naming a bug it would
catch**. If you can't say what plausible regression would make it fail — while a correct
implementation passes — it's weight, not coverage.

Credo already polices the mechanical layer (`VacuousTest`, `WeakAssertion`,
`ConditionalAssertion`, `TestHasNoAssertions`, `TooManyAssertions`, explicit `async:`,
`SkipTestWithoutComment`, `AssertReceiveTimeout`, and the harness's `SyncTestBlocker`,
`AsyncEnvMutation` and `SleepInTest`). Don't re-flag those; this
check is the judgment calls a linter can't make.

## 1. Right layer — test behavior where it lives

The suite is deliberately tiered: **exhaustive at the pure core, thin smoke above it.**

- A pure-core rule gets its matrix of cases in the core test file (`test/pica/`),
  driven through the public functions of the module that owns it, API or not.
- A process layer tests only what the *process* adds: seed threading, broadcasts,
  clock/timeout behavior, crash recovery. One integration case per wiring concern, each with
  a comment naming the specific mutant it exists to kill; that comment style is the standard.
- A public entry point (a Mix task, a CLI, a top-level API function) asserts what only wiring can
  get wrong: arguments parsed, options threaded, the right lower function called — not the rule
  that function already pins.

**Finding:** an upper layer re-testing core logic case-by-case (a task test looping over every
variant, a process test re-deriving results already pinned in the core test). The fix is usually
deletion at the upper layer, not addition at the lower.

## 2. Assert the contract, not the incidentals

The question for every assertion: *would this still pass after a harmless refactor?*

- **Determinism is a property, not an RNG transcript.** Assert same-seed ⇒ equal results, and
  both-outcomes-reachable across a seed range. Never pin "seed 7 produces `:one`" — except as a
  labeled golden (below).
- **A test of what a random draw may pick from pins the pool, not only the picks.** Asserting
  only which items were drawn passes or fails on the luck of the draw.
- **Goldens are allowed, with a license plate.** A hardcoded value (`result.total == 6152.0`)
  must be labeled `Golden:` and carry a comment naming what legitimately moves it (a ruleset
  change, a fixture refresh) and, ideally, the mutant it kills. An unlabeled magic number in an
  assertion is a finding. An expected font value (a metric, a glyph box, a shaped advance, a
  width R measures) comes from an outside tool — fontTools, `hb-shape`, R — never from Pica's
  own output and never worked out by hand: the generator script under
  `test/support/ground_truth/` names its Docker command in its header, its output lives under
  `test/fixtures/`, and the label names the tool's and the font's versions.
- **Match on text only where the text is the contract.** An error a caller pattern-matches on is
  contract: assert the error struct or the reason atom, not the sentence. A log line, a `Mix.shell`
  message or a help text is prose: assert that the datum appears (`=~ "261"`), not the wording
  around it, and never regex over a whole rendered output with layout in it — a reflow rewrites the
  test for nothing.
- **A refute of text passes whenever that string is absent — so once the wording moves, it
  guards nothing.** Rewording "a" to "b" is tested by the assert on "b"; a `refute output =~ "a"`
  beside it only catches someone retyping the exact old string, then sits in the suite passing
  whatever prints. Don't write it, and a new one is a finding. Absence as a product decision
  ("this mode prints no warning") is asserted on the structure instead — the empty list, the
  `:ok` with no message — or paired with the positive case in a sibling test.
- **External-service stubs: assert grounding, not phrasing.** A stub's job is determinism, not
  fixed wording — assert the datum appears, not the sentence.
- **Struct internals** are fair game only where the shape *is* the contract: codec round-trips
  (`decoded == document`) and versioned-document tests. Elsewhere, go through the public
  accessors.

## 3. Duplication — layered on purpose vs. redundant by accident

Two tests of the same behavior are fine when each would catch a failure the other can't (the
core test catches the math, the process test catches the seed not being threaded). They're
redundant when both fail for the same reason. Quick test: imagine one plausible bug — if it
fails both, one of them goes. The recurring concrete case: a message asserted in the test of the
module that produces it *and* re-asserted by every caller's test — keep it in the producer's test
only.

## 4. Deletion — tests must re-earn their keep after a change

When reviewing a diff that changes behavior, ask what the change *orphaned*:

- Behavior removed or moved ⇒ its tests move or die in the same diff. A test kept green by a
  legacy shim for a path nothing reaches is dead weight (exception: tests that pin a
  still-supported decode path for old persisted data — those are the contract for that data, and
  they die only when the data does).
- A test that would still pass with the feature deleted (run the mental mutant) is not covering
  that feature — fix it or remove it.
- A change that adds a gate turning a path *off* orphans the tests that drove that path
  unconditionally: they stay green and stop reaching the code, so grep the suite for them. When
  a fake needs to answer both ways, keep one fake per answer rather than a flag on one.
- **Never delete a test because it fails.** A red test is either a regression or a contract
  change; the review must say which, and only the latter licenses deletion.

## 5. Hygiene (repo mechanics)

- `async:` is explicit in every file, and **`async: true` is the default everywhere**. A file is
  `async: false` only for a blocker nothing isolates, named in a header comment:
  `Application.put_env`, an app-wide singleton or whole-VM absence assertion, or a named process
  the file starts that another file could also start. A new sync file without a stated blocker
  is a finding; so is flipping a config-mutating file async, because async tests may read config
  precisely on the guarantee that only sync files (which never overlap them) mutate it.
  **`Tack.Credo.Check.SyncTestBlocker` fails the gate when nothing is said at all**, so what is
  left here is the judgment it cannot make: whether the stated blocker is the *real* one. That is
  an empirical question — flip the file to `async: true` and see what fails.
  **`Tack.Credo.Check.AsyncEnvMutation` holds the other direction**: an `async: true` file calling
  `Application.put_env`/`delete_env` or a `TestEnv` helper fails the gate. What it cannot see is
  a mutation one call away — a `test/support` stub that calls `put_env` for its caller — so a new
  async file calling one of those is still the review's finding. The preferred remedy is the one
  that keeps the file async: the code under test takes the value as an option. When only some of
  a file's tests carry the blocker, the rest move to a file of their own that runs async. A sync
  file's time is serial, so a slow test with no blocker is a finding.
- **Config overrides go through `TestEnv`** (`test/support/test_env.ex`: `put_app_env/2`,
  `merge_app_env/2` for one option of a module-keyed entry, `delete_app_env/1`). A hand-written
  `get_env` → `put_env` → `on_exit(put_env(previous))` is a finding in new or touched code:
  restoring a key that was **unset** leaves it present holding `nil` instead of deleting it,
  which is a bug nobody sees until a `Keyword.get/2` reads that entry.
- **Wait with `eventually/2`, never a hand-rolled loop** (`test/support/eventually.ex`). A test
  that waits for an asynchronous condition calls `eventually/2`: one documented budget,
  overridden with `timeout:` where the condition is slow on purpose, and it always flunks when
  time runs out. A local helper that polls is a finding even when it flunks, and a finding twice
  over when it *returns* on timeout (`false`, `:ok`): that is a test that passes with its
  condition never met. **`Tack.Credo.Check.SleepInTest` fails the gate on a `Process.sleep` in a
  test file** outside `test/support/` (`:infinity`, parking a holder process, excepted), so the
  review's part is the waived ones: a sleep is legitimate only when the timing *is* the subject —
  an absence held for a window, a gap staged between two events with no signal to wait on — and
  the waiver says which. A wait with a condition to poll for is never one of those. A race
  between two processes is staged by ordering rather than timing wherever a trace can give the
  signal (`:erlang.trace/3`, `:sys.get_state/1` as a sync point). **A "nothing happened"
  assertion needs a sync point, not a delay.**
- **A fixture dated "today" takes the date from the same `Clock` the code reads, never
  `Date.utc_today/0` directly** — otherwise the test fails only in the hours where the UTC date
  and the domain's day disagree.
- **Offline always.** Stubbed external services, a test HTTP server for anything that speaks
  HTTP, the empty fixture directory for anything that reads disk. A new test that needs the
  network is a *design* finding in the code under test, not a `@tag` problem.
- **Fabricated inputs over real ones.** A test of something that reads the tree (a scanner, a
  check, a task) is handed a fabricated source or a temporary directory, never pointed at the
  repository itself — the repository changes, and the test then pins whatever it happened to
  contain. Build inputs with the fixture builders; inline hand-rolled structs drift.
- **Doctests are for the API.** A `@doc` example runs as a doctest only on an API function,
  where it is also the documentation users read (CLAUDE.md, Conventions). A function that is not
  API — `@doc false`, or any function of a `@moduledoc false` module — is tested by ordinary tests
  in its module's test file, with `===` where a doctest's pinned match would have told `2` from
  `2.0`; a `doctest` line for an internal module is a finding. An API example shows what a user
  sees, never an internal struct.
- Test names are behavioral sentences ("a missing budget key is a finding rather than a silent
  pass"), and deliberate wrong-type guard tests route through a `@spec`'d type-erasing helper
  so `--warnings-as-errors` holds.

## Not a finding

- Labeled goldens with their what-moves-this comment.
- The sanctioned multi-layer pattern: core matrix + one wiring smoke per layer.
- Assertions on contract text (an error reason, a locked term, the datum in a message).
- Exact-map assertions in codec/round-trip tests.
- `assert_raise FunctionClauseError` guard tests using the type-erasing helper pattern.
- A pre-existing brittle test the diff didn't touch (goes under "Pre-existing, not from
  this change").

## Overlap

If a test is hard to write because logic lives in a GenServer callback or at a call site
instead of the module that owns it, that's an **otp-processes** or **module-boundaries**
finding (the fix is moving the code), not a test-quality finding — report it there.

## Severity

- **High** — false confidence: a test that passes when the behavior is broken, or a
  coverage hole on a stated invariant (determinism, a documented contract).
- **Medium** — brittleness: assertions a harmless refactor breaks (wording, layout, unlabeled
  magic numbers); redundant re-testing at the wrong layer.
- **Low** — hygiene: naming, fixture use, missing golden labels.
