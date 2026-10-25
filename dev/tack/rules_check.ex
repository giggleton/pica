defmodule Tack.RulesCheck do
  @moduledoc """
  The checks behind `mix tack.rules_check`: the agent-facing documentation may not regrow
  into the shape that rots, and the path-scoped area rules under `.claude/rules/` may not silently
  stop applying.

  Three checks, two of them ratchets:

    * **CLAUDE.md's line budget.** The always-loaded file is cross-cutting rules plus a status
      map; a feature's narrative belongs in its area file. A checked-in budget caps the line count,
      and `--tighten` only ever lowers it, so every slim is locked in and every growth is a red gate
      rather than a tendency. Raising the number is allowed — it is a visible one-line edit.
    * **No orphan glob.** Every `paths:` entry in a rules file must match at least one file. The
      harness gives no signal when a glob matches nothing: the rule simply never loads. A move that
      empties a glob turns the gate red instead.
    * **No newly uncovered lib file.** The count of `lib/**/*.ex` files matched by no rules glob
      may not exceed its budget. A glob that still matches *something* hides the file that moved
      out from under it; this catches that case, since the moved file joins the uncovered set.

  ## Pure — the reader is `Mix.Tasks.Tack.RulesCheck`

  This module reads no file and calls no `Mix` function. The task expands each glob with
  `Path.wildcard/2` (the same `*`, `**`, `?` and `{a,b}` family the harness's `paths:` frontmatter
  uses, with dotfiles matched) and hands this module the results, the lib file list, the line count
  and the budget text; it returns findings. That keeps the checks testable against fabricated trees.
  """

  @typedoc "A `paths:` entry from a rules file's frontmatter."
  @type glob :: String.t()

  @typedoc "Rules-file path → each of its globs → the files that glob matched."
  @type expanded :: %{String.t() => %{glob() => [String.t()]}}

  @typedoc "The budget file's keys and their ceilings."
  @type budget :: %{String.t() => non_neg_integer()}

  @typedoc "Everything `evaluate/1` needs, gathered by the task."
  @type inputs :: %{
          claude_md_lines: non_neg_integer(),
          expanded: expanded(),
          lib_files: [String.t()],
          budget: budget()
        }

  @typedoc "What `evaluate/1` measured and concluded."
  @type report :: %{
          findings: [String.t()],
          measured: %{
            claude_md_lines: non_neg_integer(),
            uncovered_lib_files: non_neg_integer(),
            uncovered: [String.t()],
            orphans: [{String.t(), glob()}]
          }
        }

  @budget_keys ["claude_md_lines", "uncovered_lib_files"]
  @catch_all_share 0.8

  @doc """
  The `paths:` globs declared in a rules file's YAML frontmatter.

  Reads only the block between the opening and closing `---` fences, and only the `- "…"` items
  under the `paths:` key. A file with no frontmatter or no `paths:` key declares no globs (it is an
  unscoped rule, loaded at launch) and yields `[]`.
  """
  @spec globs(String.t()) :: [glob()]
  def globs(rules_file_text) do
    rules_file_text
    |> frontmatter_lines()
    |> Enum.drop_while(fn line -> not Regex.match?(~r/^paths:\s*$/, line) end)
    |> Enum.drop(1)
    |> Enum.take_while(fn line -> Regex.match?(~r/^\s+-\s/, line) end)
    |> Enum.map(fn line ->
      line
      |> String.replace(~r/^\s+-\s*/, "")
      |> String.trim()
      |> String.trim("\"")
    end)
    |> Enum.reject(fn glob -> glob == "" end)
  end

  @doc """
  Every `{rules_file, glob}` whose expansion is empty, in file then declaration order.

  An orphan glob is a rule that never loads and a check that never runs.
  """
  @spec orphan_globs(expanded()) :: [{String.t(), glob()}]
  def orphan_globs(expanded) do
    for {rules_file, by_glob} <- Enum.sort(expanded),
        {glob, []} <- by_glob,
        do: {rules_file, glob}
  end

  @doc """
  The lib files no *area* glob's expansion contains, sorted.

  These files load no area rules when read. The count is ratcheted, not forbidden: mix tasks and
  infrastructure modules are legitimately uncovered, and the check exists so that number cannot
  grow unnoticed.

  A glob whose expansion covers more than four fifths of the lib files is a cross-cutting rule,
  not an area, and does not count as coverage — otherwise one `lib/**/*.ex` glob would zero the
  ratchet and every later move would pass. Such a glob still counts for the orphan check.
  """
  @spec uncovered([String.t()], expanded()) :: [String.t()]
  def uncovered(lib_files, expanded) do
    lib_set = MapSet.new(lib_files)
    catch_all_threshold = MapSet.size(lib_set) * @catch_all_share

    covered =
      expanded
      |> Map.values()
      |> Enum.flat_map(&Map.values/1)
      |> Enum.map(fn matches ->
        matches
        |> MapSet.new()
        |> MapSet.intersection(lib_set)
      end)
      |> Enum.reject(fn lib_matches -> MapSet.size(lib_matches) > catch_all_threshold end)
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    lib_files
    |> Enum.reject(fn path -> MapSet.member?(covered, path) end)
    |> Enum.sort()
  end

  @doc """
  Parses the budget file: one `key value` per line, `#` comments and blank lines ignored.

  Unknown keys are kept, so a future ratchet needs no parser change; the two the checks read are
  `claude_md_lines` and `uncovered_lib_files`. A missing key is a finding, not a default — a
  ratchet with no ceiling enforces nothing.
  """
  @spec parse_budget(String.t()) :: budget()
  def parse_budget(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line -> line == "" or String.starts_with?(line, "#") end)
    |> Enum.flat_map(&budget_entry/1)
    |> Map.new()
  end

  @doc """
  Renders a budget back to the file's format, keys sorted, under a comment that says what the
  numbers are for. `render_budget(parse_budget(text))` is stable, so `--tighten` produces a
  minimal diff.
  """
  @spec render_budget(budget()) :: String.t()
  def render_budget(budget) do
    lines =
      budget
      |> Enum.sort()
      |> Enum.map_join("\n", fn {key, value} -> "#{key} #{value}" end)

    """
    # Ratchets enforced by `mix tack.rules_check` (a `mix quality` step).
    # Each number may only go down without an explicit edit; `--tighten` lowers it to today's value.
    #{lines}
    """
  end

  @doc """
  `budget` with every ceiling lowered to what was measured, never raised.

  A key the budget lacks is added at its measured value, so a first run can seed the file.
  """
  @spec tighten(budget(), %{String.t() => non_neg_integer()}) :: budget()
  def tighten(budget, measured) do
    Enum.reduce(measured, budget, fn {key, value}, acc ->
      Map.update(acc, key, value, fn ceiling -> min(ceiling, value) end)
    end)
  end

  @doc """
  Runs all three checks over already-gathered inputs.

  `findings` is empty when the gate should pass. Each finding is one sentence naming what was
  measured, its ceiling, and the fix.
  """
  @spec evaluate(inputs()) :: report()
  def evaluate(%{
        claude_md_lines: lines,
        expanded: expanded,
        lib_files: lib_files,
        budget: budget
      }) do
    orphans = orphan_globs(expanded)
    uncovered_files = uncovered(lib_files, expanded)

    measured = %{
      claude_md_lines: lines,
      uncovered_lib_files: length(uncovered_files),
      uncovered: uncovered_files,
      orphans: orphans
    }

    findings =
      budget_findings(budget) ++
        ceiling_findings("claude_md_lines", lines, budget, fn ->
          "CLAUDE.md is #{lines} lines; its budget is #{budget["claude_md_lines"]}. Move the " <>
            "narrative into the area's .claude/rules file, or raise the budget in " <>
            ".claude/rules/BUDGET deliberately."
        end) ++
        Enum.map(orphans, fn {rules_file, glob} ->
          "#{rules_file} declares the path glob #{inspect(glob)}, which matches no file, so that " <>
            "rule never loads for it. Fix or delete the glob."
        end) ++
        ceiling_findings("uncovered_lib_files", length(uncovered_files), budget, fn ->
          "#{length(uncovered_files)} lib/**/*.ex files match no rules glob; the budget is " <>
            "#{budget["uncovered_lib_files"]}. A file moved out from under its area's glob: " <>
            "widen or add a glob in .claude/rules/. Uncovered now: " <>
            Enum.join(uncovered_files, ", ")
        end)

    %{findings: findings, measured: measured}
  end

  # A ratchet with no ceiling enforces nothing, so a missing key is itself a finding.
  defp budget_findings(budget) do
    @budget_keys
    |> Enum.reject(fn key -> Map.has_key?(budget, key) end)
    |> Enum.map(fn key ->
      ".claude/rules/BUDGET has no #{key} line; run `mix tack.rules_check --tighten` " <>
        "to seed it."
    end)
  end

  defp ceiling_findings(key, measured, budget, describe) do
    case Map.fetch(budget, key) do
      {:ok, ceiling} when measured > ceiling -> [describe.()]
      _within_budget_or_missing -> []
    end
  end

  # `key value` → `[{key, value}]`; anything else (a lone key, a non-integer, a negative) → `[]`.
  defp budget_entry(line) do
    with [key, value] <- String.split(line, ~r/\s+/, parts: 2),
         {number, ""} when number >= 0 <- Integer.parse(value) do
      [{key, number}]
    else
      _malformed -> []
    end
  end

  # The frontmatter is the block between the first two `---` lines; a file that does not open
  # with a fence has none.
  defp frontmatter_lines(text) do
    case String.split(text, "\n") do
      ["---" | rest] -> Enum.take_while(rest, fn line -> String.trim(line) != "---" end)
      _no_fence -> []
    end
  end
end
