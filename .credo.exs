# This file contains the configuration for Credo. It was written by `mix tack.install`
# and is yours to edit.
#
# It is evaluated as Elixir (`Code.eval_string/1`), not read as a literal — which is what lets the
# ex_slop check list below come from the package rather than a copy of it. A check's parameter may
# be *derived* from the code the same way; guard any such call with `Code.ensure_loaded?/1` and
# raise, because `mix credo` requires only `loadpaths` and a cold `_build` has nothing to call.
# Inside `mix quality` the question never arises: compile runs before credo.

%{
  #
  # You can have as many configs as you like in the `configs:` field.
  configs: [
    %{
      #
      # Run any config using `mix credo -C <name>`. If no config name is given
      # "default" is used.
      #
      name: "default",
      #
      # These are the files included in the analysis:
      files: %{
        #
        # You can give explicit globs or simply directories.
        # In the latter case `**/*.{ex,exs}` will be used.
        #
        included: [
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      #
      # Load and configure plugins here:
      #
      plugins: [{ExSlop, []}],
      #
      # If you create your own checks, you must specify the source files for
      # them here, so they can be loaded by Credo before running the analysis.
      #
      # The repo-local checks, each one a rule this repo already states in prose (CLAUDE.md, a
      # `.claude/rules/*.md` file, a skill) made into a gate failure. They live outside `lib/`
      # deliberately: `lib/` compiles into the release, and a dev-only lint has no business there.
      # The checks the harness ships (`Tack.Credo.Check.*`) come from the package and need
      # no file here. See `.credo/checks/README.md`.
      requires: [".credo/checks/"],
      #
      # If you want to enforce a style guide and need a more traditional linting
      # experience, you can change `strict` to `true` below:
      #
      strict: false,
      #
      # To modify the timeout for parsing files, change this value:
      #
      parse_timeout: 5000,
      #
      # If you want to use uncolored output by default, you can change `color`
      # to `false` below:
      #
      color: true,
      #
      # You can customize the parameters of any check by adding a second element
      # to the tuple.
      #
      # To disable a check put `false` as second element:
      #
      #     {Credo.Check.Design.DuplicatedCode, false}
      #
      checks: %{
        enabled:
          [
            #
            ## Consistency Checks
            #
            {Credo.Check.Consistency.ExceptionNames, []},
            {Credo.Check.Consistency.LineEndings, []},
            {Credo.Check.Consistency.ParameterPatternMatching, []},
            {Credo.Check.Consistency.SpaceAroundOperators, []},
            {Credo.Check.Consistency.SpaceInParentheses, []},
            {Credo.Check.Consistency.TabsOrSpaces, []},

            #
            ## Design Checks
            #
            # You can customize the priority of any check
            # Priority values are: `low, normal, high, higher`
            #
            {Credo.Check.Design.AliasUsage,
             [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 0]},
            {Credo.Check.Design.TagFIXME, []},
            # You can also customize the exit_status of each check.
            # If you don't want TODO comments to cause `mix credo` to fail, just
            # set this value to 0 (zero).
            #
            {Credo.Check.Design.TagTODO, [exit_status: 2]},

            #
            ## Readability Checks
            #
            {Credo.Check.Readability.AliasOrder, []},
            {Credo.Check.Readability.FunctionNames, []},
            {Credo.Check.Readability.LargeNumbers, []},
            {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
            {Credo.Check.Readability.ModuleAttributeNames, []},
            {Credo.Check.Readability.ModuleDoc, []},
            {Credo.Check.Readability.ModuleNames, []},
            {Credo.Check.Readability.ParenthesesInCondition, []},
            {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
            {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
            {Credo.Check.Readability.PredicateFunctionNames, []},
            {Credo.Check.Readability.PreferImplicitTry, []},
            {Credo.Check.Readability.RedundantBlankLines, []},
            {Credo.Check.Readability.Semicolons, []},
            {Credo.Check.Readability.SpaceAfterCommas, []},
            {Credo.Check.Readability.StringSigils, []},
            {Credo.Check.Readability.TrailingBlankLine, []},
            {Credo.Check.Readability.TrailingWhiteSpace, []},
            {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
            {Credo.Check.Readability.VariableNames, []},
            {Credo.Check.Readability.WithSingleClause, []},

            #
            ## Refactoring Opportunities
            #
            {Credo.Check.Refactor.Apply, []},
            {Credo.Check.Refactor.CondStatements, []},
            {Credo.Check.Refactor.CyclomaticComplexity, []},
            {Credo.Check.Refactor.FilterCount, []},
            {Credo.Check.Refactor.FilterFilter, []},
            {Credo.Check.Refactor.FunctionArity, []},
            {Credo.Check.Refactor.LongQuoteBlocks, []},
            {Credo.Check.Refactor.MapJoin, []},
            {Credo.Check.Refactor.MatchInCondition, []},
            {Credo.Check.Refactor.NegatedConditionsInUnless, []},
            {Credo.Check.Refactor.NegatedConditionsWithElse, []},
            {Credo.Check.Refactor.Nesting, []},
            {Credo.Check.Refactor.RedundantWithClauseResult, []},
            {Credo.Check.Refactor.RejectReject, []},
            {Credo.Check.Refactor.UnlessWithElse, []},
            {Credo.Check.Refactor.WithClauses, []},

            #
            ## Warnings
            #
            {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
            {Credo.Check.Warning.BoolOperationOnSameValues, []},
            {Credo.Check.Warning.Dbg, []},
            {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
            {Credo.Check.Warning.IExPry, []},
            {Credo.Check.Warning.IoInspect, []},
            {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []},
            {Credo.Check.Warning.OperationOnSameValues, []},
            {Credo.Check.Warning.OperationWithConstantResult, []},
            {Credo.Check.Warning.RaiseInsideRescue, []},
            {Credo.Check.Warning.SpecWithStruct, []},
            {Credo.Check.Warning.StructFieldAmount, []},
            {Credo.Check.Warning.UnsafeExec, []},
            {Credo.Check.Warning.UnusedEnumOperation, []},
            {Credo.Check.Warning.UnusedFileOperation, []},
            {Credo.Check.Warning.UnusedKeywordOperation, []},
            {Credo.Check.Warning.UnusedListOperation, []},
            {Credo.Check.Warning.UnusedMapOperation, []},
            {Credo.Check.Warning.UnusedPathOperation, []},
            {Credo.Check.Warning.UnusedRegexOperation, []},
            {Credo.Check.Warning.UnusedStringOperation, []},
            {Credo.Check.Warning.UnusedTupleOperation, []},
            {Credo.Check.Warning.WrongTestFilename, []},

            #
            ## Jump.CredoChecks (jump_credo_checks). The package also carries LiveView, Plug and
            ## Ecto checks; those are listed only when the project has something for them to read.
            #
            {Jump.CredoChecks.AssertReceiveTimeout,
             min_assert_receive_timeout: 1_000, max_refute_receive_timeout: 100},
            {Jump.CredoChecks.AvoidFunctionLevelElse, []},
            {Jump.CredoChecks.AvoidLoggerConfigureInTest, []},
            {Jump.CredoChecks.ConditionalAssertion, []},
            {Jump.CredoChecks.DoctestIExExamples, []},
            {Jump.CredoChecks.ForbiddenFunction, functions: []},
            {Jump.CredoChecks.TestHasNoAssertions, []},
            {Jump.CredoChecks.TooManyAssertions, max_assertions: 20},
            {Jump.CredoChecks.TopLevelAliasImportRequire, []},
            {Jump.CredoChecks.UndeclaredExternalResource, []},
            {Jump.CredoChecks.VacuousTest, []},
            {Jump.CredoChecks.WeakAssertion, []},

            #
            ## The harness's checks (tack)
            ##
            ## Each makes a rule CLAUDE.md states in prose into a gate failure. What the `boundary`
            ## compiler already holds is deliberately *not* restated here — no check for `Repo` in a
            ## web module, none for a core module calling a context — because a rule enforced in two
            ## places is a rule with two homes to update.
            #
            {Tack.Credo.Check.NoCaptureOperator, []},
            # `test/` only: a sync file says in its header what stops it. `test/support` case
            # templates are in scope too, since a template's own `use` is where a whole family of
            # files inherits its default.
            {Tack.Credo.Check.SyncTestBlocker, [files: %{included: ["test/"]}]},
            # Its other half — an async file may not change config — and `test/` only, since the
            # rule is about ExUnit's scheduling and nothing else is scheduled by it.
            {Tack.Credo.Check.AsyncEnvMutation, [files: %{included: ["test/"]}]},
            # `test/` only, and not `test/support/` — that is where `eventually/2`, the one polling
            # loop, lives. A regex, since a per-check `excluded:` string is resolved as a path
            # rather than a prefix.
            {Tack.Credo.Check.SleepInTest,
             [files: %{included: ["test/"], excluded: [~r"/test/support/"]}]},
            # The same exclusions `Credo.Check.Readability.Specs` takes below, for the same reason:
            # the convention is about the documented public API, and the web tier, the mix tasks
            # and the tests conventionally go undocumented.
            {Tack.Credo.Check.PublicFunctionDoc,
             [files: %{excluded: [~r"/test/", ~r"/lib/mix/"]}]},
            # Every file under `lib/` is read: a function of fonts and strings reads no config, no
            # clock and no process. A module that must be impure (the registry, if it holds
            # global state) is excluded here by name, with its reason.
            {Tack.Credo.Check.CorePurity, [files: %{included: ["lib/"]}]},

            #
            ## The repo-local checks (`.credo/checks/`), each a rule CLAUDE.md states in prose
            #
            # Zip and map in one pass (`Enum.zip_with/2,3`), everywhere credo reads, as credo's own
            # `MapJoin` is scoped.
            {PicaCredo.Check.ZipMap, []},

            #
            ## Formerly-disabled "controversial and experimental" checks, each enabled deliberately.
            ## The ones that stay off (a deliberate design/style choice) live in `disabled:` below,
            ## each with a documented rationale.
            #
            # Named unused vars (`_reason`) document intent in lib; bare `_` in test pattern-matches
            # (`{:ok, {_, _}}`, `[_, _] = …`) is idiomatic throwaway, so tests are exempt.
            {Credo.Check.Consistency.UnusedVariableNames, [files: %{excluded: [~r"/test/"]}]},
            {Credo.Check.Design.SkipTestWithoutComment, []},
            {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
            {Credo.Check.Readability.AliasAs, []},
            {Credo.Check.Readability.StrictModuleLayout, []},
            {Credo.Check.Refactor.AppendSingleItem, []},
            {Credo.Check.Refactor.PassAsyncInTestCases, []},
            {Credo.Check.Refactor.PipeChainStart, []},
            {Credo.Check.Readability.ImplTrue, []},
            {Credo.Check.Readability.NestedFunctionCalls, []},
            {Credo.Check.Readability.OneArityFunctionInPipe, []},
            {Credo.Check.Readability.OnePipePerLine, []},
            {Credo.Check.Readability.SinglePipe, []},
            # CLAUDE.md requires @spec on public API. The web layer (Phoenix components, controllers,
            # LiveViews), mix tasks, and tests conventionally go unspec'd, so they're excluded here.
            {Credo.Check.Readability.Specs, [files: %{excluded: [~r"/test/", ~r"/lib/mix/"]}]},
            {Credo.Check.Readability.WithCustomTaggedTuple, []},
            {Credo.Check.Refactor.DoubleBooleanNegation, []},
            {Credo.Check.Refactor.IoPuts, []},
            {Credo.Check.Refactor.MapMap, []},
            {Credo.Check.Warning.LeakyEnvironment, []},
            {Credo.Check.Warning.MapGetUnsafePass, []},
            {Credo.Check.Warning.MixEnv, []},
            {Credo.Check.Warning.UnsafeToAtom, []}
            # ex_slop's recommended checks (the plugin auto-registers them, but this config uses an
            # explicit `enabled:` allowlist — which is the complete set, so Credo ignores the plugin's
            # default config and its `extra:`. Appending here is what actually turns them on;
            # `recommended_checks/0` keeps the set in sync with the package.)
          ] ++ Enum.map(ExSlop.recommended_checks(), fn check -> {check, []} end),
        disabled: [
          # Only applies to the paid Oban Pro; the free Oban is the default assumption. Delete this
          # line if the project adopts Pro.
          {Jump.CredoChecks.UseObanProWorker, []},
          # Mutually exclusive with `Credo.Check.Refactor.CondStatements` (enabled above), which
          # recommends the opposite — if/else over a trivial 2-branch cond. We keep CondStatements
          # (it matches the house style of guards + if/else over cond), so this one stays off.
          {Credo.Check.Refactor.CondInsteadOfIfElse, []},
          # We deliberately group aliases (`alias MyApp.{Repo, Mailer}`), so this stays off.
          {Credo.Check.Readability.MultiAlias, []},
          # Rebinding a variable through a sequence of transformations (`game = reveal(game)`,
          # `changeset = put_change(changeset, …)`) is idiomatic Elixir state-threading — clearer than
          # numbered variants (`game1`, `game2`).
          {Credo.Check.Refactor.VariableRebinding, []},
          # Arbitrary max-dependency threshold (default 10). The high-count modules are inherently
          # central — the router, the OTP application, the LiveViews, the context modules — and
          # splitting them to cut a dependency count would harm cohesion.
          {Credo.Check.Refactor.ModuleDependencies, []},
          # Arbitrary complexity threshold that overlaps the already-enabled CyclomaticComplexity.
          {Credo.Check.Refactor.ABCSize, []},
          # Off because it cannot tell a shared rule from a coincidental match: two adapters whose
          # bodies match today over inputs that change on separate schedules should stay apart, and
          # the check flags exactly those. Run it by hand (`mix credo -c DuplicatedCode`) as a
          # review aid rather than a gate.
          {Credo.Check.Design.DuplicatedCode, []}
          #
          # {Credo.Check.Warning.UnusedOperation, [{MyMagicModule, [:fun1, :fun2]}]}

          # {Credo.Check.Refactor.MapInto, []},

          #
          # Custom checks can be created using `mix credo.gen.check`.
          #
        ]
      }
    }
  ]
}
