defmodule Tack.Credo.Check.SyncTestBlocker do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      A test file that opts out of `async: true` says in its header what stops it.

      `elixir-code-review`, `references/test-quality.md`:

      > `async:` is explicit in every file, and **`async: true` is the default everywhere** — the
      > database sandbox isolates DB tests. A file is `async: false` only for a blocker the sandbox
      > can't isolate, named in a header comment: `Application.put_env`, an app-wide singleton or
      > whole-VM absence assertion, or a process whose start-up reads the database outside the
      > test's sandbox ownership. A new sync file without a stated blocker is a finding.

      Sync is not free, and that is why the reason is worth writing down. Every `async: true`
      module runs before the sync ones, and a suite comes to lean on that: an async test may read
      config that only sync files mutate. So a file that goes sync without a blocker slows the
      suite for nothing, and one that goes async while mutating config breaks readers somewhere
      else entirely — the two mistakes are not symmetric, and neither is visible at the file you
      are reading.

      The check reads the lines between `defmodule` and the `use` line and asks only whether a
      comment or a `@moduledoc` is there. Whether the stated blocker is the *real* one is a review
      judgment (and an empirical one — flip the file to `async: true` and see what fails).
      """
    ]

  @message "An `async: false` test file states its blocker in a header comment — application " <>
             "env, an app-wide singleton, a whole-VM absence assertion, or a process whose " <>
             "start-up reads the database outside the sandbox. The case template's moduledoc is " <>
             "the rubric."

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    lines = SourceFile.lines(source_file)

    source_file
    |> Credo.Code.prewalk(fn ast, acc -> find_sync_use(ast, acc) end)
    |> Enum.reject(fn line_number -> documented?(lines, line_number) end)
    |> Enum.map(fn line_number -> issue_for(issue_meta, line_number) end)
  end

  defp find_sync_use({:use, meta, arguments} = ast, sync_uses) when is_list(arguments) do
    if sync?(arguments), do: {ast, [meta[:line] | sync_uses]}, else: {ast, sync_uses}
  end

  defp find_sync_use(ast, sync_uses), do: {ast, sync_uses}

  defp sync?(arguments) do
    Enum.any?(arguments, fn argument ->
      is_list(argument) and Keyword.get(argument, :async) == false
    end)
  end

  # The header is everything between `defmodule` and the `use` line: a comment there, or a
  # moduledoc, is the statement. Comments are not in the AST, so this reads the source.
  defp documented?(lines, use_line) do
    lines
    |> Enum.filter(fn {line_number, _text} -> line_number < use_line end)
    |> Enum.reverse()
    |> Enum.take_while(fn {_line_number, text} -> not String.contains?(text, "defmodule ") end)
    |> Enum.any?(fn {_line_number, text} ->
      trimmed = String.trim_leading(text)
      String.starts_with?(trimmed, "#") or String.contains?(trimmed, "@moduledoc")
    end)
  end

  defp issue_for(issue_meta, line_number) do
    format_issue(issue_meta, message: @message, trigger: "async: false", line_no: line_number)
  end
end
