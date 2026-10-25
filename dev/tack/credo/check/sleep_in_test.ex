defmodule Tack.Credo.Check.SleepInTest do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A test that waits for something asynchronous polls the condition with the suite's
      `eventually/2` helper (`test/support/eventually.ex`), never a sleep.

      `elixir-code-review`, `references/test-quality.md`:

      > **Wait with `eventually/2`, never a hand-rolled loop.** A test that waits for an
      > asynchronous condition calls `eventually/2` (or `eventually_render/3` against a LiveView):
      > one documented budget, and it always flunks when time runs out.

      A bare `Process.sleep(n)` in a test is one of two things, and both are findings:

        * **a guess** — "the cast has surely landed by now". It is flaky under load and slow when
          idle, and the fix is to wait on the condition itself with `eventually/2`.
        * **a polling loop** — the sleep inside a hand-written retry. Every such loop picks its
          own budget, and some return `false` or `:ok` on timeout and rely on every caller to
          `assert`, so a test whose condition never came true can pass. Each new test copies
          whichever loop sits nearest.

      Scope the check to `test/` and exclude `test/support/` in `.credo.exs`: that is where the one
      sanctioned loop lives. `Process.sleep(:infinity)` is out of scope too — it parks a process
      (a holder that must stay alive until the test kills it) and guesses at no timing.

      What remains is a sleep that *is* the subject: an absence held for a window ("the supervisor
      must not restart it"), a TTL that must lapse on the wall clock, a gap staged between two
      events with no signal to wait on. Those carry an inline waiver that says so.
      """
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, fn ast, issues -> traverse(ast, issues, issue_meta) end)
  end

  # `Process.sleep(duration)` and `:timer.sleep(duration)` — any duration but the literal `:infinity`.
  defp traverse({{:., _dot, [module, :sleep]}, meta, [duration]} = ast, issues, issue_meta)
       when duration != :infinity do
    case sleep_call(module) do
      nil -> {ast, issues}
      trigger -> {ast, [issue_for(issue_meta, trigger, meta[:line]) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp sleep_call({:__aliases__, _meta, [:Process]}), do: "Process.sleep"
  defp sleep_call(:timer), do: ":timer.sleep"
  defp sleep_call(_module), do: nil

  defp issue_for(issue_meta, trigger, line_number) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}` in a test is a guess at timing. Wait on the condition itself with " <>
          "`eventually/2` (or `eventually_render/3` for a LiveView) from test/support; a sleep " <>
          "that is the subject of the test — an absence held for a window, a TTL lapsing — " <>
          "carries an inline waiver saying so.",
      trigger: trigger,
      line_no: line_number
    )
  end
end
