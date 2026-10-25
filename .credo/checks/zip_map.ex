defmodule PicaCredo.Check.ZipMap do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Zip and map in one pass with `Enum.zip_with/2,3`, not `Enum.zip/1,2` piped into
      `Enum.map/2` (CLAUDE.md, Conventions), as credo's own `MapJoin` asks for
      `Enum.map_join/3` rather than `Enum.map/2` piped into `Enum.join/2`.

      This should be refactored:

          positions
          |> Enum.zip(labels)
          |> Enum.map(fn {position, label} -> {position, String.upcase(label)} end)

      to look like this:

          Enum.zip_with(positions, labels, fn position, label ->
            {position, String.upcase(label)}
          end)

      `Enum.zip/2` builds a list of tuples only for `Enum.map/2` to walk it again, while
      `Enum.zip_with/3` calls the function as it zips. With more than two enumerables,
      `Enum.zip_with/2` takes them as a list and hands the function a list.

      The check reads the code as written: it sees a zip piped or passed straight into a map, not
      one bound to a variable first.
      """
    ]

  @message "Zip and map in one pass with `Enum.zip_with/2,3`, not `Enum.zip/1,2` then `Enum.map/2`."

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)
    walked = Credo.Code.prewalk(source_file, fn node, context -> walk(node, context) end, context)
    walked.issues
  end

  # A zip piped into a map, the zip itself piped: `positions |> Enum.zip(labels) |> Enum.map(…)`,
  # and `columns |> Enum.zip() |> Enum.map(…)`.
  defp walk({:|>, metadata, [{:|>, _, [_zipped, zip]}, map]} = node, context),
    do: found(node, context, metadata, zip, map)

  # A zip call piped into a map: `Enum.zip(positions, labels) |> Enum.map(…)`.
  defp walk({:|>, metadata, [zip, map]} = node, context),
    do: found(node, context, metadata, zip, map)

  # A zip passed to a map: `Enum.map(Enum.zip(positions, labels), …)`, the zip piped or not.
  defp walk(
         {{:., metadata, [{:__aliases__, _, [:Enum]}, :map]}, _, [zipped, _function]} = node,
         context
       ) do
    zip =
      case zipped do
        {:|>, _, [_zipped, piped_zip]} -> piped_zip
        unpiped_zip -> unpiped_zip
      end

    found(node, context, metadata, zip, node)
  end

  defp walk(node, context), do: {node, context}

  defp found(node, context, metadata, zip, map) do
    if enum_call?(zip, :zip) and enum_call?(map, :map) do
      {node, put_issue(context, issue_for(context, metadata))}
    else
      {node, context}
    end
  end

  defp enum_call?({{:., _, [{:__aliases__, _, [:Enum]}, name]}, _, _arguments}, name), do: true
  defp enum_call?(_node, _name), do: false

  # The issue is reported on the map's line, so the map is what credo finds there to point at.
  defp issue_for(context, metadata) do
    format_issue(context, message: @message, line_no: metadata[:line], trigger: "Enum.map")
  end
end
