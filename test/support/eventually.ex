defmodule PicaTest.Eventually do
  @moduledoc """
  Waiting in a test for something asynchronous to become true — the one polling loop the suite uses.

  A test that has to wait (a process to exit, a cast to land) calls `eventually/2`. It polls
  until the condition holds and **fails the test when it never does**: there is no return value to
  forget to `assert` on, and no budget that runs out quietly into a pass.

      import PicaTest.Eventually

      eventually(fn -> Registry.lookup(Pica.TestRegistry, key) == [] end)

      # The truthy value comes back, so a wait doubles as a fetch.
      pid = eventually(fn -> GenServer.whereis(name) end)

  The default budget is one second, polled every 10ms. A condition that is slow on purpose — a
  window that closes on its own clock, a pool that loads over a stubbed network — passes a larger
  `:timeout` where it is called, so the number sits next to the reason for it.

  Why one helper: left alone, a suite grows a hand-rolled loop per file, each with its own budget,
  and some return `false` or `:ok` on timeout and rely on the caller to `assert` — a test whose
  condition never came true can pass. `Tack.Credo.Check.SleepInTest` flags a
  `Process.sleep` in a test file, which is what keeps the next loop from being written.

  This is for a condition that **will** hold. To assert that something does *not* happen — a
  process that must stay dead, a message that must never arrive — there is nothing to poll for;
  use `refute_receive` with a timeout, or a sleep carrying an inline waiver that says why.
  """

  # Test support, compiled only in the test environment: its own top-level boundary, named outside
  # `Pica` so that nothing in the library gains ExUnit.
  use Boundary, deps: [ExUnit]

  import ExUnit.Assertions, only: [flunk: 1]

  @timeout 1_000
  @interval 10

  @typedoc """
  `:timeout` — total milliseconds to wait (default #{@timeout}); `:interval` — milliseconds between
  attempts (default #{@interval}); `:message` — the failure message, in place of the generic one.
  """
  @type option :: {:timeout, pos_integer()} | {:interval, pos_integer()} | {:message, String.t()}

  @doc """
  Calls `check` until it returns a truthy value, and returns that value.

  Flunks with `:message` (or a generic one naming the budget) if `check` is still `false` or `nil`
  after `:timeout` milliseconds. `check` is always called at least once, and once more at the
  deadline, so a condition that comes true during the last interval is not missed.
  """
  @spec eventually((-> term()), [option()]) :: term()
  def eventually(check, options \\ []) when is_function(check, 0) do
    case poll(check, fn value -> value not in [false, nil] end, options) do
      {:ok, value} ->
        value

      {:timeout, _last_value} ->
        flunk(
          Keyword.get_lazy(options, :message, fn ->
            "the condition did not hold within #{timeout(options)}ms"
          end)
        )
    end
  end

  defp poll(attempt, done?, options) do
    deadline = System.monotonic_time(:millisecond) + timeout(options)
    poll(attempt, done?, deadline, Keyword.get(options, :interval, @interval))
  end

  defp poll(attempt, done?, deadline, interval) do
    value = attempt.()
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      done?.(value) ->
        {:ok, value}

      remaining <= 0 ->
        {:timeout, value}

      true ->
        # Never sleeps past the deadline, so the last attempt lands on it rather than after it.
        pause = min(interval, remaining)
        Process.sleep(pause)
        poll(attempt, done?, deadline, interval)
    end
  end

  defp timeout(options), do: Keyword.get(options, :timeout, @timeout)
end
