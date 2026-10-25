defmodule Tack.Credo.Check.TimestampRewriteInTest do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      A test that needs an old row moves its stamp with the suite's `backdate/3` helper
      (`test/support/backdate.ex`), not an `update_all`.

      `elixir-code-review`, `references/test-quality.md`:

      > **Age a row with `backdate/3`, never a local `update_all`.** A test that places a row in
      > time calls `backdate/3`: `{amount, unit}` always means "that long ago", the instant is
      > truncated to the column's precision, and a query matching no rows fails.

      Left alone, a suite grows one `backdate` helper per file, with incompatible signatures: some
      add the offset and are called with a negative number, some subtract it; half truncate and
      half do not; some return silently when nothing matched, so a test that backdated no row
      asserts against fresh stamps and passes. Each new test copies whichever sits nearest.

      This flags any `update_all` whose `set:` names a literal `*_at` key — the way every
      timestamp column is named. A domain-named wrapper (`joined_at/2`, `move_expiry/2`) is fine
      as long as its body calls `backdate/3`, which writes its keys dynamically and so is never
      flagged itself. Scope the check to `test/` in `.credo.exs`; `lib/` writes `updated_at` in
      bulk on purpose.
      """
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, fn ast, issues -> traverse(ast, issues, issue_meta) end)
  end

  # `Repo.update_all(query, set: [...])`, `query |> Repo.update_all(set: [...])` (the pipe leaves
  # the call one argument short), and the three-argument form with options.
  defp traverse({{:., _dot, [_module, :update_all]}, meta, arguments} = ast, issues, issue_meta)
       when is_list(arguments) do
    case Enum.find_value(arguments, fn argument -> timestamp_key(argument) end) do
      nil -> {ast, issues}
      field -> {ast, [issue_for(issue_meta, field, meta[:line]) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp timestamp_key(updates) when is_list(updates) do
    Enum.find_value(updates, fn
      {:set, changes} when is_list(changes) ->
        Enum.find_value(changes, fn change -> timestamp_field(change) end)

      _other ->
        nil
    end)
  end

  defp timestamp_key(_argument), do: nil

  defp timestamp_field({field, _value}) when is_atom(field) do
    timestamp? =
      field
      |> Atom.to_string()
      |> String.ends_with?("_at")

    if timestamp?, do: field
  end

  defp timestamp_field(_change), do: nil

  defp issue_for(issue_meta, field, line_number) do
    format_issue(
      issue_meta,
      message:
        "Rewriting `#{field}` with `update_all` in a test is the hand-rolled backdate. Use " <>
          "`backdate/3` from test/support: `{amount, unit}` means that long ago, the instant " <>
          "matches the column's precision, and a query that matches no rows fails.",
      trigger: "update_all",
      line_no: line_number
    )
  end
end
