defmodule Tack.Credo.Check.NoCaptureOperator do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Anonymous functions are written out, never with the capture shorthand.

      CLAUDE.md, Conventions:

      > **No capture-operator anonymous functions.** Always write anonymous functions as
      > `fn descriptive_name -> body end` — never the `&`/`&1` shorthand (e.g. `& &1.id`,
      > `&(&1 + 1)`). `&Mod.fun/arity` references are ok. Prefer descriptive argument names
      > over positional `&1`.

      The convention buys the same thing the "no abbreviations" rule buys: at every call site
      the argument has a name that says what it is, so a reader of `Enum.filter(bids, fn bid ->
      bid.accepted? end)` never has to look up what `&1` was bound to.

          # not ok
          Enum.map(listings, & &1.code)
          Enum.filter(prices, &(&1 > 0))

          # ok
          Enum.map(listings, fn listing -> listing.code end)
          Enum.filter(prices, fn price -> price > 0 end)

          # ok — a named function reference is not an anonymous function
          Enum.map(codes, &String.upcase/1)
          Enum.reduce(amounts, 0, &Kernel.+/2)
      """
    ]

  @message "Write this as `fn descriptive_name -> … end`. The `&`/`&1` shorthand is not used " <>
             "in this codebase (CLAUDE.md, Conventions); `&Mod.fun/arity` references are fine."

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, fn ast, issues -> traverse(ast, issues, issue_meta) end)
  end

  # `&Mod.fun/2`, `&fun/1`, `&+/2` — a reference to a named function, which the convention allows.
  defp traverse({:&, _meta, [{:/, _slash_meta, [_target, arity]}]} = ast, issues, _issue_meta)
       when is_integer(arity) do
    {ast, issues}
  end

  # `&1`, `&2` — a placeholder *inside* a shorthand function. The enclosing `&` is the finding,
  # and it has already been reported by the clause below, so this one is silent.
  defp traverse({:&, _meta, [position]} = ast, issues, _issue_meta) when is_integer(position) do
    {ast, issues}
  end

  defp traverse({:&, meta, [_body]} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_number) do
    format_issue(issue_meta, message: @message, trigger: "&", line_no: line_number)
  end
end
