---
paths:
  - "mix.exs"
  - "mix.lock"
  - ".tool-versions"
  - ".credo.exs"
  - ".credo/checks/**"
  - ".claude/hooks/waiver-gate.sh"
  - ".github/workflows/**"
  - "dev/**"
  - "native/pica/Cargo.toml"
  - "native/pica/Cargo.lock"
  - "native/pica/Cross.toml"
  - "native/pica/about.toml"
  - "native/pica/about.hbs"
  - "RELEASE.md"
  - "native/pica/.cargo/**"
---

# Dependencies, toolchain, lint and security waivers

Taking any dependency update: the `dependency-updates` skill (read the package diff, never trust
semver or the changelog).

## Rules

- **A new lint or security waiver stops and asks the user.** Before adding a
  `credo:disable-for-*`, or a `hex.audit` ignore, ask whether the code needs the flagged construct
  at all: a shell-out where the standard library has the function, an interpolated query where a
  bound parameter would do. If it does, two lines sit directly above the waiver, and the review
  report carries the same three answers:
  ```elixir
  # why: <what the code needs that trips the tool, and the invariant that keeps it safe>
  # instead of: <the alternative considered> — rejected because <reason>
  ```
  `.claude/hooks/waiver-gate.sh` denies the edit until both are there, then asks the user to
  approve with the diff in view; the commit gate re-checks the diff. **A marker quoted inside a
  `"""` heredoc is prose, not a waiver**, and both scanners skip it — documenting the invariant
  that keeps a waiver safe in a moduledoc is the pattern here, so a moduledoc explaining one must
  not read as one. An internal module's documentation is a comment, where a quoted marker would
  read as a waiver, so it explains its waiver without quoting one. A waiver whose rejected
  alternative was cheaper than the waiver is a finding on the construct, not the comment
  (`elixir-code-review`, `references/suppressions.md`). Scope a
  waiver as narrowly as the tool allows; a `.credo.exs` check moved to `disabled:` silences code
  not yet written.
- **The exact Elixir/Erlang toolchain is pinned in `.tool-versions`**, and CI reads it from there
  (`erlef/setup-beam` with `version-file`), so there is one place to bump. A Dockerfile, when one
  exists, is the second place and moves with it.
- **New credo checks are adopted deliberately through `.credo.exs`'s `enabled:` allowlist**, not by
  plugin default. The `ex_slop` plugin's recommended set is appended from the package so it stays
  in step; everything else is listed by hand.
- **Repo-local checks live in `.credo/checks/`, and each one makes a rule this repo already states
  in prose into a gate failure.** They are loaded by `.credo.exs`'s `requires:` and enabled one at
  a time like any other check. Outside `lib/` deliberately: `lib/` compiles into the release, a
  dev-only lint has no business there, and a check under `lib/` would want a boundary declaration
  and count against `rules_check`'s uncovered-file budget. The checks the harness ships
  (`Tack.Credo.Check.*`) are compiled from `dev/tack/` instead, with Tack's tests under
  `test/tack/`. Four things hold
  a new local check together:
  **(1) A rule the `boundary` compiler already holds is not restated** — a web module naming
  `Repo`, a core module calling a context. Two homes for one rule is one home too many, and the
  compiler's home is the stricter of the two. What credo is for is what Boundary cannot see: the
  **standard library** inside the pure core (`DateTime.utc_now/0`, `Application.get_env/3`,
  `spawn/1` are `:elixir`/`:kernel`, so a core module calling one compiles in silence), and
  conventions with no type-level shape at all.
  **(2) Scoping lives in `.credo.exs`**, in the check's `files:` filter with its reason beside it,
  never inside the check — so the exemption list reads next to every other piece of configuration.
  A per-check `excluded:` **string** is resolved as a file or a directory, not as a path prefix
  (`Credo.Sources.find_in_dir/3`), so a directory name silently leaves the `.ex` beside it in
  scope — use a regex. The file is evaluated as Elixir, so a check's parameter may be *derived*
  from the code rather than restated; guard any such call with `Code.ensure_loaded?/1` and
  **raise**, because `mix credo` requires only `loadpaths` and a cold `_build` has nothing to call
  — a fallback list would be the silent under-enforcement the derivation exists to avoid. **A
  single sanctioned site is waived inline instead**, at the code, where the `# why:` line names
  why it is sanctioned and the hook makes the next one a decision.
  **(3) Each check is tested in both directions**: a check that fires on everything and a check
  that fires on nothing both pass a one-sided test, and the second failure is the silent one — a
  rule that quietly stopped being enforced. One test file, `test/credo_checks_test.exs`,
  `Code.require_file`s the local checks, and only one may, since requiring the same source twice in
  one VM redefines the module and the warning fails the gate; it starts the `credo` application
  itself, since credo is a `runtime: false` dependency whose parsing services nothing else starts.
  An issue's place is asserted too, its line, column and trigger: credo finds the column by
  searching the reported line for the trigger, so a trigger that is not on that line leaves the
  issue pointing at no column, and nothing else would notice.
  **(4) Size a candidate check by running it, scoped as its nearest sibling is, never by grep.** A
  grep over-reports twice over: it ignores the scoping the check will take, and it matches prose,
  including the header comments that document the very rule being counted.
- **`boundary` is the one dev tool that is not `only: [:dev, :test]`**, and must stay that way: it
  is a compiler, so it has to exist wherever `mix compile` runs, including a `:prod` release
  build. Scoping it away from prod makes the release build fail on an unknown compiler.
- **`dev/` is Tack's code, copied, and stays Tack's.** The gate's runner, the rules check, the
  boundary scanner, the credo checks and their tests (`test/tack/`) are copies of Tack's
  (`dev/tack.ex` names the commit), kept byte for byte, so a fix in Tack is copied across with a
  diff and a Pica-only change is a decision to state in `dev/tack.ex`. They are copied rather than
  depended on because Tack's repository is private and CI cannot fetch it. `dev/` compiles in the
  dev and test environments only and is not in the Hex package.
- **The Hex package `rustler` and the crate `rustler` move together, on the same minor.** The
  Hex side compiles the crate and the crate implements the NIF interface it loads, so a bump of
  one is a bump of both, through `dependency-updates`. `rustler` is `optional: true` in `mix.exs`:
  a user who downloads a prebuilt binary never compiles Rust, and only a source build needs it.
- **`THIRD_PARTY_NOTICES.md` lists every crate compiled into the NIF with its licence's text**,
  generated by cargo-about (`native/pica/about.toml`, `about.hbs`), shipped in the Hex package,
  and regenerated whenever `native/pica/Cargo.lock` changes. `about.toml`'s `accepted` list is a
  licence gate: adding a licence to it is the user's decision.
- **The release workflow builds the NIF versions `Pica.Native` lists**, 2.15 alone, for
  `RustlerPrecompiled`'s ten default targets, and attaches them to a version tag's release;
  RELEASE.md is the only thing that holds a release's order.
- **The Rust toolchain floor is `rust-version` in `native/pica/Cargo.toml`**, the highest any
  crate in the tree needs; CI and the release workflow build with stable. A crate that raises it
  is a bump to state in the change.
- **Rust lint waivers stop and ask, as credo's do.** An `#[allow(...)]` or `#[expect(...)]`
  attribute, or a `clippy` lint relaxed in `Cargo.toml`, is a waiver: it carries the same
  `// why:` and `// instead of:` lines above it, and it is the user's decision. The waiver gate
  does not read Rust, so this rule is held by review, not by the hook.
- **A boundary declaration is a layering decision, so widening one asks the user** — the same
  standing as a lint waiver, but enforced **harder**: `.claude/hooks/waiver-gate.sh` scores each
  declaration's grants and **always denies** an edit that raises the score. An Edit is scored
  against the **whole file** it would leave, not its fragments, since a formatted declaration keeps
  its `exports:` list on the lines below `use Boundary,` and a fragment holding only list entries
  would otherwise score nothing. **Removing a declaration is a widening too**, though the score reads
  it as 0 → 0 (a boundary exporting only its root scores 0, and so does no declaration): it folds
  the boundary's modules into the parent, where anything may call them. So the hook also counts
  declarations and denies a drop, and the commit gate flags a declaring file deleted while modules
  remain under its namespace — deleting the whole namespace widens nothing. No comment satisfies
  the deny, and the commit gate re-scans the working tree so a Bash edit cannot slip past.
  Narrowing is always free. Two gentler designs fail
  the same way: `ask` is auto-approved by the session's permission mode, so the widening reaches
  nobody; and a required `# why:` comment is the agent writing a justification, meeting its own
  rule with it, and approving it — a control with no second party. So the explanation belongs
  **in conversation with the user, in plain language**: which list grew, which module joined it,
  what can now call what, and whether changing the *caller* was the alternative. One widening per
  ask, never a batch: the interruption is the control. A forbidden-reference warning usually means
  a caller is reaching past a seam, not that the seam is too tight. **The score is a proxy; relay
  the deny message's caveats with it.** When a change also adds or removes an option the score
  does not read (`type:`, `top_level?:`, `check:`, `dirty_xrefs:`), or involves `exports: :all`
  — which the score ranks as maximal even on a nested boundary — the message says so, and the
  explanation to the user must cover the whole change, not the number. **Move a declared file with
  `git mv`**: the commit check pairs a staged rename and scores it against its old declaration,
  while a plain `mv` reads as a new file whose every grant is new.
- **A change to a hook is written as a patch, tested on a copy, and applied by the user.** Claude
  Code's auto mode may refuse the agent's edit to `.claude/hooks/waiver-gate.sh`; revert any
  half-made edit, never leave the hook between states. Prove the patch on a copy (or a throwaway
  clone, where staging, approving and committing touch no real marks) with a case that must pass
  and one that must still be stopped.
- **`exports: :all` is for the umbrella root only.** On a sub-boundary the list is written out one
  module at a time, because the list is an approval gate, not bookkeeping: an explicit list fails
  **safe** — a new module is private until a person admits it — while `:all` makes it public the
  moment it compiles. The hook scores a listed module at 1 and a bare `:all` at 1000, so the mass
  form on a sub-boundary is denied outright. The generated boundary declarations test pins this.
- **Moving a module between boundaries is a grant too.** A mix task belongs to no architectural
  tier, so `classify_to:` assigns it to one by hand — and changing that target changes what the
  module may call. `waiver-gate.sh` denies any change to a `classify_to:` target and the commit
  gate re-checks it, on the same footing as widening `deps:`/`exports:`, because neither direction
  of a move is obviously "more" and a permission score cannot rank it. **One `classify_to:` is not
  a move: a `defimpl` classifying itself into the boundary of the protocol it implements**, on the
  line straight after the `defimpl` line, naming the protocol as that line writes it. Boundary
  checks nothing an unclassified protocol implementation calls, so that line only narrows, and the
  hook passes it (Giggly's copy of the hook, which Pica's is; Tack's stops it). Every `defimpl`
  of one of Pica's own protocols opens with it. Leaving it out compiles in silence, so
  `test/pica/boundary_declarations_test.exs` fails on any implementation of one of Pica's own
  protocols not classified into its protocol's boundary. An implementation of a protocol from
  outside Pica has no protocol boundary and stays unclassified, so nothing checks what it calls.
- **Disabling a check is pinned by a test, not scored by the hook** (the hook only *lists* one in a
  widening's deny message). `check: [in/out/apps/aliases]`, `dirty_xrefs:` and `top_level?:` are
  the options that make the compiler enforce *less*, and `test/pica/boundary_declarations_test.exs`
  fails on any of them that is not in its `@sanctioned` list with a stated reason. A test rather
  than a hook because these must be caught on a **first** write, not only on a widening edit — a
  declaration that is too narrow fails loudly, while one that is too wide compiles in silence, so
  nothing else in the toolchain would ever report it. The same test fails the other way on a
  `@sanctioned` entry whose declaration is gone, so a stale permission cannot outlive what it
  permitted: an exemption found unnecessary is deleted from the list, not re-justified.
- **After editing a boundary declaration, `mix compile --force` before trusting the gate.**
  Boundary's incremental state does not fully invalidate when a *declaration* changes: modules that
  do not recompile keep their recorded classification, so the next incremental build can report a
  forbidden reference that no longer exists, or an unused `dirty_xrefs:` entry that is gone. The
  error is in the safe direction — a real violation *is* caught incrementally — so this costs a
  confusing red gate, never a false pass. The same holds when `boundary` itself is bumped.
- **To find what calls into a namespace, ask the compiler — not grep, not xref.** Boundary checks
  calls and struct expansions and skips typespec and alias references, so `mix xref graph` (which
  records typespec edges) over-counts and a text sweep mis-attributes. The probe that works is a
  temporary `top_level?: true, deps: []` on the namespace, which turns every inbound call into a
  forbidden reference; revert it before the gate, which the declarations test enforces anyway.
  `exports: []` does not work: a boundary always exports its own root module, so calls to the
  root — usually most of them — stay legal.
- **`hex.audit` waivers carry a removal condition, not just a justification.** An ignore is keyed
  by advisory **ID, not version**, so it silences that CVE for every future version of the package
  too. And `hex.audit` reports a now-pointless ignore as a *warning* on a step that still exits 0,
  so nothing fails when the waiver expires: it is noticed only by someone reading the gate's
  output, which is another reason never to pipe it. A suspected bad-data advisory is proven from
  the package and the matched OSV record, never from the changelog alone.

## How it works

- The harness was copied from Giggly's, not installed with `mix tack.install`, because Giggly's
  copies of Tack's files carry changes not yet in Tack's templates, and a re-install must keep
  them: `waiver-gate.sh` counts declarations, so a removed one is a widening, sorts paths before
  hashing an approval, and passes a `defimpl`'s own `classify_to:`; `elixir-code-review` scopes
  its review against the local `main`; `docs-sync` routes a milestone to one §6 line and mechanism
  to module documentation. Giggly's mutation testing was left out: its `muex` dependency, its
  skill, and the commit gate's mutation rule and `post-commit` hook. The code Pica runs from
  Tack — `mix tack.quality`, `mix tack.rules_check`, the credo checks, the boundary scanner — is
  copied into `dev/` (the rule above), so Tack is not a dependency.
- The `elixir:` requirement in `mix.exs` is the floor; the **exact** toolchain is pinned in
  `.tool-versions`, which CI reads.
- The gate's tools: `ex_doc`, `credo` (with the `jump_credo_checks` and `ex_slop` plugins and
  the `tack` checks), and `boundary`; for the crate, `cargo fmt`, `cargo clippy -D warnings` and
  `cargo test`, each pointed at `native/pica/Cargo.toml`. Dependency-advisory scanning is Hex's
  own `mix hex.audit` — no scanner dependency.
- **The quality gate's steps** are the `quality_steps` list in `mix.exs`, run in order by
  `mix quality` and, minus the formatting write, by CI's `mix quality --check` — so a step added
  there reaches CI with no second list to keep in sync. Why the less obvious ones are there:
  - `mix format` and `cargo fmt` run **first**, so an unformatted file is fixed up front instead
    of surfacing only at the trailing check steps after the whole suite has already run.
  - **`mix hex.audit` runs every time**, not just when `mix.exs`/`mix.lock` change: a new advisory
    can be published against a dependency you already have, so an unchanged tree can go from
    clean to vulnerable with no code change. It fails on retired packages as well as advisories.
    Triage a false positive via the `:hex` project key's `ignore_advisories` list in `mix.exs`,
    never by skipping the step. **Requires Hex ≥ 2.5** — older Hex checks retirements only and
    exits 0, so the gate refuses to run under it (`mix local.hex --force` to update).
  - `mix deps.unlock --check-unused` fails when `mix.lock` carries an entry for a package `mix.exs`
    no longer declares. This is the one failure that **cannot** surface locally otherwise: the
    stale `deps/` directory stays on disk, so every other step is happy, while CI fetches only the
    declared tree and finds it missing. Offline and instant; fix with `mix deps.unlock --unused`.
  - Both `mix compile --warnings-as-errors` (in `:dev` and in `:test`) warm the two build dirs; a
    compile warning is a hard failure, matching CI. `mix test --warnings-as-errors` makes a warning
    in any test file fail the gate too, so stray test-file warnings can't pile up unnoticed.
  - `mix compile` builds the crate from source, since the version in `mix.exs` is a `-dev`
    pre-release (`RustlerPrecompiled` forces a source build for one), so the suite always runs
    against the Rust in the tree, never a downloaded binary.
- **Architecture as a compile-time check** (`boundary`): `compilers: [:boundary]` in `mix.exs`
  checks the `use Boundary` declarations, so a forbidden cross-namespace call is a compiler
  warning and therefore a gate failure. The root is `Pica`, with each domain a sub-boundary
  beneath it. `Pica.Native` lists `Mix`, `Rustler` and `RustlerPrecompiled` as `:compile` deps,
  since `use RustlerPrecompiled` calls them only while the module compiles; `Rustler` only when
  it is loaded, as it is not in a project that downloads the binary, so Boundary there finds no
  unknown dependency (design-log §4, "Rustler is a boundary dependency only when it is loaded").
  It is strict everywhere — `boundary: [default: [type: :strict]]` in `mix.exs`, pinned by the
  declarations test, which also fails on any declaration setting `type: :relaxed` — with each
  domain a sub-boundary whose `deps:` is its contract, and an outside library listed by the one
  domain that owns it and by the root. `mix boundary.spec` prints the current graph. Six
  constraints govern
  any change to it, each found by compiling rather than by reading the docs: **(1)** `check: [in:
  false]` / `[out: false]` is legal **only on a top-level boundary**, and such a boundary may not
  contain sub-boundaries; **(2)** a boundary with `check.in` false may not be exported from, nor
  listed as anyone's dep; **(3)** a top-level boundary may not name a *sub*-boundary in `deps:` —
  only siblings, its parent, and its ancestors' deps; **(4)** a parent re-exports a sub-boundary's
  modules, and a sub-boundary still lists its exports explicitly, because the list is an approval
  gate; **(5)** strictness belongs to each boundary: a strict parent does not check an
  outside-library call made from a sub-boundary that is not strict itself, which is why the
  default is set once in `mix.exs` rather than on a declaration; **(6)** a sub-boundary may list
  an outside library, or a top-level boundary, only when its parent lists it too — so the root
  lists each library its owner does, which opens it to the modules directly in the root (`Pica`
  alone) and to no domain, since each is strict and calls only what it lists (Giggly's design log
  §4, the entry beginning "A library's owner nests under the umbrella"). The checker ignores plain **alias
  references** by default (`check: [aliases: true]` is off), so passing a module as a value
  crosses a boundary silently; only calls and struct use are caught. And it checks nothing a
  **protocol implementation** calls until the implementation is classified with `classify_to:`
  (`unclassified_protocol_impl?` in its checker; found by compiling a `defimpl` that called a
  module its family does not list), nor any call *to* one.
