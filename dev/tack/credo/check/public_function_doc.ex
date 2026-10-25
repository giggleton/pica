defmodule Tack.Credo.Check.PublicFunctionDoc do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Every public function carries a `@doc`.

      CLAUDE.md, Conventions:

      > **Document public API.** Every module gets a `@moduledoc` and every public function a
      > `@doc` (and a `@spec`); these are the pure core's contract and feed `ex_doc`. Use
      > `@moduledoc false` only for modules with no public surface. Private functions (`defp`)
      > don't need `@doc`; clarify them with a brief comment when non-obvious.

      Two thirds of that sentence are enforced elsewhere — `Credo.Check.Readability.ModuleDoc` for
      the moduledoc and `Credo.Check.Readability.Specs` for the spec, both taking the same `files:`
      exclusions as this check. This is the third.

      A function counts as documented when a `@doc` precedes it (`@doc false` included — it is a
      deliberate statement that the function has no public documentation) or when it carries
      `@impl`, since a callback implementation takes its contract from the behaviour. Only the
      first clause of a function needs one; each arity is its own function and wants its own.
      """
    ]

  @message "Public functions should have a @doc. (`@doc false` is a documented decision; `@impl` " <>
             "takes its contract from the behaviour.)"

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    documented = Credo.Code.prewalk(source_file, fn ast, acc -> find_documented(ast, acc) end)

    context =
      Context.build(source_file, params, __MODULE__, %{documented: documented, reported: []})

    source_file
    |> Credo.Code.prewalk(fn ast, acc -> walk(ast, acc) end, context)
    |> Map.fetch!(:issues)
  end

  # `@doc`/`@impl` marks the *next* definition, so the accumulator carries the mark forward until
  # a definition consumes it — the shape `Credo.Check.Readability.Specs` uses for `@impl`.
  defp find_documented({:@, _meta, [{attribute, _attribute_meta, [value]}]} = ast, documented)
       when attribute in [:doc, :impl] and value != false do
    {ast, [:documented | documented]}
  end

  # `@doc false` is a decision about the public surface, so it documents the function too.
  defp find_documented({:@, _meta, [{:doc, _doc_meta, [false]}]} = ast, documented) do
    {ast, [:documented | documented]}
  end

  defp find_documented(
         {:def, meta, [{:when, _guard, definition} | _rest]},
         [:documented | _documented] = documented
       ) do
    find_documented({:def, meta, definition}, documented)
  end

  defp find_documented({:def, _meta, [{name, _name_meta, arguments} | _rest]} = ast, [
         :documented | documented
       ])
       when is_list(arguments) or is_nil(arguments) do
    {ast, [{name, arity(arguments)} | documented]}
  end

  defp find_documented(ast, documented), do: {ast, documented}

  # A definition inside `quote` belongs to whatever expands it, which is where its docs belong too.
  defp walk({:quote, _meta, _arguments}, context), do: {nil, context}

  defp walk({:def, meta, [{:when, _guard, definition} | _rest]}, context) do
    walk({:def, meta, definition}, context)
  end

  defp walk({:def, meta, [{name, _name_meta, arguments} | _rest]} = ast, context)
       when is_list(arguments) or is_nil(arguments) do
    function = {name, arity(arguments)}

    # One missing `@doc` is one finding, however many clauses the function has: the fix is a single
    # attribute above the first of them.
    if function in context.documented or function in context.reported do
      {ast, context}
    else
      {ast,
       context
       |> unshift(:reported, function)
       |> put_issue(issue_for(context, meta, name))}
    end
  end

  defp walk(ast, context), do: {ast, context}

  defp arity(nil), do: 0
  defp arity(arguments), do: length(arguments)

  defp issue_for(context, meta, trigger) do
    format_issue(context, message: @message, trigger: to_string(trigger), line_no: meta[:line])
  end
end
