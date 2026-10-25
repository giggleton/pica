defmodule Tack.BoundaryDeclarations do
  @moduledoc """
  Reads the `use Boundary` declarations out of Elixir source, so a test can assert on the shape of
  the architecture's enforcement.

  The boundary declarations fail in one direction only. A declaration that is too **narrow** fails
  loudly — a forbidden reference, and the gate's compile step goes red. One that is too **wide**
  compiles in silence, and nothing in the toolchain will ever report that more permission was
  granted than the code uses. So the options that make the compiler check *less* are pinned by the
  generated boundary declarations test against a list of sanctioned exceptions, and widening a
  `deps:`/`exports:` grant is gated at authoring time by `.claude/hooks/waiver-gate.sh`.

  One widening arrives the other way round — by deletion rather than addition — so it is read by
  its own function rather than by the escape-hatch list: see `strict?/1`.

  ## Only the declaration is read, never prose about one

  A declaration runs from a line whose first token is `use Boundary` until its brackets balance on
  a line that does not run on — one ending in neither `,` nor `:`, since `mix format` may leave a
  bare `use Boundary,` or a bare key such as `exports:` on a line of its own. The body of every
  `\"""` heredoc is skipped first. That matters more than it sounds: a moduledoc explaining why a
  module may never say `exports: :all`, a test module quoting every option it forbids, or an
  installer whose template strings hold whole declarations must all score nothing. A scanner that
  matched anywhere in the file would score each as a maximal grant.
  """

  @typedoc "A `use Boundary …` declaration, flattened to one line."
  @type declaration :: String.t()

  @typedoc "A check-disabling option: the token to search for, and what it does."
  @type hatch :: {Regex.t(), String.t(), String.t()}

  # Every option that reduces what the compiler checks. `deps:` and `exports:` are deliberately
  # absent: they are the declarations' ordinary content and widen one grant at a time rather than
  # switching a check off, so they are guarded by the hook instead.
  @escape_hatches [
    {~r/check:.*\bin:\s*false/, "check: [in: false]", "lets any boundary call into this one"},
    {~r/check:.*\bout:\s*false/, "check: [out: false]", "lets this boundary call anything"},
    {~r/check:.*\bapps:/, "check: [apps: …]", "exempts external applications"},
    {~r/check:.*\baliases:/, "check: [aliases: …]", "changes what counts as a reference"},
    {~r/dirty_xrefs:/, "dirty_xrefs:", "exempts named references one at a time"},
    {~r/top_level\?:/, "top_level?:", "lifts a module out of its parent boundary"}
  ]

  @doc "Every check-disabling option this module knows about, as `{pattern, token, effect}`."
  @spec escape_hatches() :: [hatch()]
  def escape_hatches, do: @escape_hatches

  @doc """
  The `use Boundary` declarations in `source`, each flattened to a single line.

  A declaration starts at a line whose first non-space token is `use Boundary` and ends when the
  brackets opened since then balance on a line ending in neither `,` nor `:`, so a multi-line
  declaration is returned whole — including `mix format`'s shape of a key alone on its line with
  the value below — and a comment or moduledoc mentioning one is ignored.
  """
  @spec declarations(String.t()) :: [declaration()]
  def declarations(source) do
    source
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> blank_heredoc_lines()
    |> Enum.reduce({[], :outside}, &collect_declaration_line/2)
    |> elem(0)
    |> Enum.reverse()
  end

  # Blank the body of every `"""` heredoc, so a declaration *quoted* in a moduledoc, a test fixture
  # or an installer's template string is not read as one — the same rule `.claude/hooks/waiver-gate.sh`
  # applies. A line with an odd number of fences toggles; lines are blanked rather than dropped so
  # the declaration's shape (which lines run on) is unchanged.
  defp blank_heredoc_lines(lines) do
    lines
    |> Enum.map_reduce(false, fn line, in_heredoc ->
      fences = length(String.split(line, ~s("""))) - 1
      toggled = if rem(fences, 2) == 1, do: not in_heredoc, else: in_heredoc
      {if(in_heredoc, do: "", else: line), toggled}
    end)
    |> elem(0)
  end

  defp collect_declaration_line(line, {finished, :outside}) do
    if String.starts_with?(line, "use Boundary") and not String.starts_with?(line, "#") do
      start_declaration(line, finished)
    else
      {finished, :outside}
    end
  end

  defp collect_declaration_line(line, {finished, {:inside, collected, depth}}) do
    close_or_continue(finished, collected <> " " <> line, depth + bracket_depth(line), line)
  end

  defp start_declaration(line, finished),
    do: close_or_continue(finished, line, bracket_depth(line), line)

  # A declaration ends where its brackets balance AND the line does not run on — it ends in neither
  # a comma nor a colon. The comma matters on its own: `use Boundary,` with the options on the lines
  # below opens no bracket at all, so a depth rule alone closes the declaration on its first line
  # and reads only "use Boundary,". The colon matters for the same reason one level down: `mix
  # format` puts a long value on the line after its key, so a declaration may read `exports:` alone
  # on a line, and a comma-only rule closed there — reading "use Boundary, exports:" and missing
  # any option written after the value. `.claude/hooks/waiver-gate.sh` reads declarations by the
  # same rule.
  defp close_or_continue(finished, collected, depth, last_line) do
    if depth <= 0 and not String.ends_with?(last_line, [",", ":"]) do
      {[collected | finished], :outside}
    else
      {finished, {:inside, collected, depth}}
    end
  end

  defp bracket_depth(line) do
    line
    |> String.graphemes()
    |> Enum.reduce(0, fn character, depth ->
      cond do
        character in ["[", "{"] -> depth + 1
        character in ["]", "}"] -> depth - 1
        true -> depth
      end
    end)
  end

  @doc """
  The check-disabling options used in `source`, as `{token, effect}` pairs.

  Each is a place where the compiler was told to enforce less than it could.
  """
  @spec disabled_checks(String.t()) :: [{String.t(), String.t()}]
  def disabled_checks(source) do
    for declaration <- declarations(source),
        {pattern, token, effect} <- @escape_hatches,
        Regex.match?(pattern, declaration),
        do: {token, effect}
  end

  @doc """
  Whether any declaration in `source` sets `type: :strict`.

  The mirror of `disabled_checks/1`, and the reason it needs its own function: every option that
  function scans for is a token whose *presence* weakens the check, so its arrival shows up in a
  diff. `type: :strict` weakens by *going away*. Boundary's default is `:relaxed`, which checks
  calls into an external application only when the boundary already names some other module from
  it — so deleting one word from a pure core's declaration drops the "nothing outside the standard
  library" half of its guarantee, and the deletion compiles clean, passes the gate, and scores
  nothing in `.claude/hooks/waiver-gate.sh`, which ranks `deps:`/`exports:` entries and does not
  read `type:`.
  """
  @spec strict?(String.t()) :: boolean()
  def strict?(source) do
    source
    |> declarations()
    |> Enum.any?(fn declaration -> Regex.match?(~r/type:\s*:strict/, declaration) end)
  end

  @doc """
  Whether any declaration in `source` exports everything with a bare `exports: :all`.

  Legal for the umbrella, and a trap for a sub-boundary: it makes every module public the moment
  it compiles, where an explicit list fails safe — a new module is private until a person admits
  it. `exports: {:all, except: […]}` is a narrowing of the same thing and does not count.
  """
  @spec exports_all?(String.t()) :: boolean()
  def exports_all?(source) do
    source
    |> declarations()
    |> Enum.any?(fn declaration -> Regex.match?(~r/exports:\s*:all/, declaration) end)
  end

  @doc """
  Whether `mix_exs_source` actually runs the boundary compiler.

  Comment lines are dropped first, because a `mix.exs` may also *describe* `compilers: [:boundary]`
  in a note above the dependency — a bare substring search passes on that prose after the setting
  itself is deleted, which is the single largest bypass in the scheme.
  """
  @spec compiler_configured?(String.t()) :: boolean()
  def compiler_configured?(mix_exs_source) do
    mix_exs_source
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line -> String.starts_with?(line, "#") end)
    |> Enum.any?(fn line -> Regex.match?(~r/^compilers:\s*\[:boundary\]/, line) end)
  end

  @doc "Every file under `root` that carries at least one `use Boundary` declaration."
  @spec source_files(String.t()) :: [String.t()]
  def source_files(root) do
    root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.filter(fn path -> declarations_in(path) != [] end)
  end

  @doc "`declarations/1` for a file on disk."
  @spec declarations_in(String.t()) :: [declaration()]
  def declarations_in(path) do
    source = File.read!(path)
    declarations(source)
  end

  @doc "`disabled_checks/1` for a file on disk."
  @spec disabled_checks_in(String.t()) :: [{String.t(), String.t()}]
  def disabled_checks_in(path) do
    source = File.read!(path)
    disabled_checks(source)
  end

  @doc "`strict?/1` for a file on disk."
  @spec strict_in?(String.t()) :: boolean()
  def strict_in?(path) do
    source = File.read!(path)
    strict?(source)
  end

  @doc "`exports_all?/1` for a file on disk."
  @spec exports_all_in?(String.t()) :: boolean()
  def exports_all_in?(path) do
    source = File.read!(path)
    exports_all?(source)
  end

  @doc "`compiler_configured?/1` for a file on disk."
  @spec compiler_configured_in?(String.t()) :: boolean()
  def compiler_configured_in?(path) do
    source = File.read!(path)
    compiler_configured?(source)
  end
end
