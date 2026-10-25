defmodule Tack.Credo.ChecksTest do
  @moduledoc """
  The harness's credo checks, each run against a fabricated module.

  Each check is tested in both directions, because a check that fires on everything and a check
  that fires on nothing both pass a one-sided test, and the second failure is silent — a rule that
  quietly stopped being enforced. The scoping (which paths each check reads) lives in the generated
  `.credo.exs` and is not exercised here; `run_check/2` is handed the source directly.
  """
  use Credo.Test.Case, async: true

  alias Tack.Credo.Check.{
    AsyncEnvMutation,
    CorePurity,
    NoCaptureOperator,
    PublicFunctionDoc,
    SleepInTest,
    SyncTestBlocker,
    TimestampRewriteInTest
  }

  # `to_source_file/1` memoises parsed ASTs in a credo GenServer, so credo has to be running.
  # Starting it here is idempotent and reaches nothing else in the suite.
  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:credo)
    :ok
  end

  describe "NoCaptureOperator" do
    test "a shorthand anonymous function is a finding" do
      """
      defmodule MyApp.Records do
        def codes(listings), do: Enum.map(listings, & &1.code)
      end
      """
      |> to_source_file()
      |> run_check(NoCaptureOperator)
      |> assert_issue()
    end

    test "the parenthesised shorthand is a finding too, and reports one issue, not one per slot" do
      """
      defmodule MyApp.Bid do
        def gap(amounts), do: Enum.map(amounts, &(&1 - &2))
      end
      """
      |> to_source_file()
      |> run_check(NoCaptureOperator)
      |> assert_issue()
    end

    test "a reference to a named function is not a finding" do
      """
      defmodule MyApp.Labels do
        def shout(names), do: Enum.map(names, &String.upcase/1)
        def total(amounts), do: Enum.reduce(amounts, 0, &Kernel.+/2)
        def own(names), do: Enum.map(names, &label/1)
        defp label(name), do: name
      end
      """
      |> to_source_file()
      |> run_check(NoCaptureOperator)
      |> refute_issues()
    end

    test "an anonymous function written out is not a finding" do
      """
      defmodule MyApp.Records do
        def codes(listings), do: Enum.map(listings, fn listing -> listing.code end)
      end
      """
      |> to_source_file()
      |> run_check(NoCaptureOperator)
      |> refute_issues()
    end
  end

  describe "CorePurity" do
    test "a clock read is a finding" do
      """
      defmodule MyApp.Core.Day do
        def today, do: date_of(DateTime.utc_now())
      end
      """
      |> to_source_file()
      |> run_check(CorePurity)
      |> assert_issue(fn issue ->
        assert issue.trigger == "DateTime.utc_now"
        assert issue.line_no == 2
      end)
    end

    test "a config read is a finding" do
      """
      defmodule MyApp.Core.Booster do
        def active, do: Application.get_env(:my_app, :active_boosters, [])
      end
      """
      |> to_source_file()
      |> run_check(CorePurity)
      |> assert_issue(fn issue -> assert issue.trigger == "Application.get_env" end)
    end

    test "randomness that reads the process dictionary is a finding" do
      """
      defmodule MyApp.Core.Negotiation do
        def coin, do: :rand.uniform(2)
        def pick(slots), do: Enum.random(slots)
      end
      """
      |> to_source_file()
      |> run_check(CorePurity)
      # One per call site. The list is in the check's accumulation order, which is not part of
      # its contract, so these assert how many rather than which is which.
      |> assert_issues(fn issues -> assert [_first, _second] = issues end)
    end

    test "a process, an IO call and a bare spawn are findings" do
      """
      defmodule MyApp.Core.Game do
        def announce(pid) do
          Process.send_after(pid, :tick, 1000)
          IO.puts("tick")
          spawn(fn -> :ok end)
          send(pid, :tick)
        end
      end
      """
      |> to_source_file()
      |> run_check(CorePurity)
      |> assert_issues(fn issues -> assert [_first, _second, _third, _fourth] = issues end)
    end

    test "a receive block is a finding" do
      """
      defmodule MyApp.Core.Game do
        def wait do
          receive do
            :tick -> :ok
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(CorePurity)
      |> assert_issue(fn issue -> assert issue.trigger == "receive" end)
    end

    test "randomness from an injected seed is not a finding" do
      """
      defmodule MyApp.Core.PlayerAgent do
        def weights(seed, slot) do
          rng = :rand.seed_s(:exsss, seed)
          {fraction, next} = :rand.uniform_s(rng)
          {fraction, next, :erlang.phash2({seed, slot, :weights})}
        end
      end
      """
      |> to_source_file()
      |> run_check(CorePurity)
      |> refute_issues()
    end

    test "pure date arithmetic on an instant taken as an argument is not a finding" do
      """
      defmodule MyApp.Core.Day do
        def date_of(instant, offset) do
          instant
          |> DateTime.add(offset, :hour)
          |> DateTime.to_date()
        end
      end
      """
      |> to_source_file()
      |> run_check(CorePurity)
      |> refute_issues()
    end
  end

  describe "PublicFunctionDoc" do
    test "an undocumented public function is a finding, once however many clauses it has" do
      """
      defmodule MyApp.Recap do
        def moments(nil, _enrichment), do: []
        def moments(summary, enrichment), do: enrich(summary, enrichment)
      end
      """
      |> to_source_file()
      |> run_check(PublicFunctionDoc)
      |> assert_issue(fn issue -> assert issue.line_no == 2 end)
    end

    test "each arity is its own function and wants its own @doc" do
      """
      defmodule MyApp.Recap do
        @doc "The beats."
        def moments(summary), do: moments(summary, :none)

        def moments(summary, enrichment), do: enrich(summary, enrichment)
      end
      """
      |> to_source_file()
      |> run_check(PublicFunctionDoc)
      |> assert_issue(fn issue -> assert issue.line_no == 5 end)
    end

    test "a private function needs no @doc" do
      """
      defmodule MyApp.Recap do
        defp enrich(summary, _enrichment), do: summary
      end
      """
      |> to_source_file()
      |> run_check(PublicFunctionDoc)
      |> refute_issues()
    end

    test "@doc, @doc false and @impl each satisfy it" do
      """
      defmodule MyApp.Room do
        @doc "Starts the room."
        def start_link(options), do: GenServer.start_link(__MODULE__, options)

        @doc false
        def child_spec(options), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}}

        @impl GenServer
        def init(options), do: {:ok, options}
      end
      """
      |> to_source_file()
      |> run_check(PublicFunctionDoc)
      |> refute_issues()
    end

    test "a definition inside quote belongs to whatever expands it" do
      """
      defmodule MyAppWeb do
        def controller do
          quote do
            def action(conn, _params), do: conn
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(PublicFunctionDoc)
      |> assert_issue(fn issue -> assert issue.trigger == "controller" end)
    end
  end

  describe "SleepInTest" do
    test "a timed sleep is a finding, through either module" do
      """
      defmodule MyApp.RoomsTest do
        test "leaves" do
          Room.leave(code, seat)
          Process.sleep(50)
          :timer.sleep(timeout)
          refute Room.whereis(code)
        end
      end
      """
      |> to_source_file()
      |> run_check(SleepInTest)
      |> assert_issues(fn issues ->
        lines = Enum.map(issues, fn issue -> issue.line_no end)
        assert Enum.sort(lines) == [4, 5]
      end)
    end

    test "parking a process forever is not a finding" do
      """
      defmodule MyApp.PresenceTest do
        test "tracks" do
          holder = spawn(fn -> Process.sleep(:infinity) end)
          :timer.sleep(:infinity)
        end
      end
      """
      |> to_source_file()
      |> run_check(SleepInTest)
      |> refute_issues()
    end

    test "a function of another module that happens to be called sleep is not a finding" do
      """
      defmodule MyApp.RoomsTest do
        test "naps" do
          Agent.sleep(50)
          sleep(50)
        end
      end
      """
      |> to_source_file()
      |> run_check(SleepInTest)
      |> refute_issues()
    end
  end

  describe "TimestampRewriteInTest" do
    test "setting an `_at` key is a finding — called, piped, beside other keys, or with options" do
      """
      defmodule MyApp.RoomsTest do
        test "ages" do
          Repo.update_all(query, set: [inserted_at: aged])
          query |> MyApp.Repo.update_all(set: [status: :final, completed_at: at])
          Repo.update_all(query, [set: [expires_at: at]], timeout: 1_000)
        end
      end
      """
      |> to_source_file()
      |> run_check(TimestampRewriteInTest)
      |> assert_issues(fn issues ->
        lines = Enum.map(issues, fn issue -> issue.line_no end)
        assert Enum.sort(lines) == [3, 4, 5]
      end)
    end

    test "other columns, other operations and dynamic keys are not findings" do
      """
      defmodule MyApp.GamesTest do
        test "corrupts" do
          Repo.update_all(query, set: [status: :abandoned, day: day])
          Repo.update_all(query, inc: [wins: 1])
          Repo.update_all(query, set: [{field, instant}])
          Repo.update_all(query, set: changes)
        end
      end
      """
      |> to_source_file()
      |> run_check(TimestampRewriteInTest)
      |> refute_issues()
    end
  end

  describe "SyncTestBlocker" do
    test "a sync file with nothing said about why is a finding" do
      """
      defmodule MyApp.NotificationsTest do
        use MyApp.DataCase, async: false

        test "sends" do
          assert true
        end
      end
      """
      |> to_source_file()
      |> run_check(SyncTestBlocker)
      |> assert_issue(fn issue -> assert issue.line_no == 2 end)
    end

    test "a header comment is the statement" do
      """
      defmodule MyApp.NotificationsTest do
        # async: false — flips `:push_enabled`, which every send reads at call time.
        use MyApp.DataCase, async: false
      end
      """
      |> to_source_file()
      |> run_check(SyncTestBlocker)
      |> refute_issues()
    end

    test "a moduledoc is the statement too" do
      """
      defmodule MyApp.NotificationsTest do
        @moduledoc \"\"\"
        Sync because it swaps the app-wide push adapter.
        \"\"\"
        use MyApp.DataCase, async: false
      end
      """
      |> to_source_file()
      |> run_check(SyncTestBlocker)
      |> refute_issues()
    end

    test "an async file is asked for nothing" do
      """
      defmodule MyApp.GamesTest do
        use MyApp.DataCase, async: true
      end
      """
      |> to_source_file()
      |> run_check(SyncTestBlocker)
      |> refute_issues()
    end

    test "a comment belonging to the module above does not count for this one" do
      """
      defmodule MyApp.FirstTest do
        # async: false — swaps the provider base_url.
        use MyApp.DataCase, async: false
      end

      defmodule MyApp.SecondTest do
        use MyApp.DataCase, async: false
      end
      """
      |> to_source_file()
      |> run_check(SyncTestBlocker)
      |> assert_issue(fn issue -> assert issue.line_no == 7 end)
    end
  end

  describe "AsyncEnvMutation" do
    test "changing config in an async file is a finding, once per call" do
      """
      defmodule MyApp.EnrichmentTest do
        use MyApp.DataCase, async: true

        setup do
          Application.put_env(:my_app, :dossiers_enabled, true)
          on_exit(fn -> Application.delete_env(:my_app, :dossiers_enabled) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(AsyncEnvMutation)
      |> assert_issues(fn issues ->
        triggers = Enum.map(issues, fn issue -> issue.trigger end)
        assert Enum.sort(triggers) == ["Application.delete_env", "Application.put_env"]
      end)
    end

    test "the helper is a finding too, qualified or imported — it restores, it does not isolate" do
      """
      defmodule MyApp.NotificationsTest do
        use MyApp.DataCase, async: true
        import MyApp.TestEnv, only: [merge_app_env: 2]

        test "sends" do
          MyApp.TestEnv.put_app_env(:push_enabled, true)
          merge_app_env(MyApp.Client, base_url: "http://localhost")
        end
      end
      """
      |> to_source_file()
      |> run_check(AsyncEnvMutation)
      |> assert_issues(fn issues -> assert [_first, _second] = issues end)
    end

    test "a sync file may change config — that is what the scheduling rule is for" do
      """
      defmodule MyApp.NotificationsTest do
        # async: false — flips `:push_enabled`, which every send reads at call time.
        use MyApp.DataCase, async: false

        setup do
          MyApp.TestEnv.put_app_env(:push_enabled, true)
          Application.put_env(:my_app, :push_stub, self())
        end
      end
      """
      |> to_source_file()
      |> run_check(AsyncEnvMutation)
      |> refute_issues()
    end

    test "an async file that only reads config is not a finding" do
      """
      defmodule MyApp.GamesTest do
        use MyApp.DataCase, async: true

        test "boosters" do
          assert Application.get_env(:my_app, :active_boosters) != []
        end
      end
      """
      |> to_source_file()
      |> run_check(AsyncEnvMutation)
      |> refute_issues()
    end

    test "each module is judged by its own use line" do
      """
      defmodule MyApp.SyncTest do
        # async: false — swaps the provider base_url.
        use MyApp.DataCase, async: false
        setup do: Application.put_env(:my_app, :enabled, [])
      end

      defmodule MyApp.AsyncTest do
        use MyApp.DataCase, async: true
        setup do: Application.put_env(:my_app, :enabled, [])
      end
      """
      |> to_source_file()
      |> run_check(AsyncEnvMutation)
      |> assert_issue(fn issue -> assert issue.line_no == 9 end)
    end
  end
end
