defmodule Mix.Tasks.Tack.RulesCheck do
  @shortdoc "Checks CLAUDE.md's line budget and the .claude/rules path globs"

  @moduledoc """
  Runs `Tack.RulesCheck` over the working tree and fails the gate on any finding.

      mix tack.rules_check [--tighten]

  Three checks: CLAUDE.md may not exceed its line budget; every `paths:` glob in
  `.claude/rules/*.md` must match at least one file; and the number of `lib/**/*.ex` files no glob
  covers may not exceed its budget. The budgets live in `.claude/rules/BUDGET` and are ratchets —
  `--tighten` lowers each to today's measurement and never raises one. Raising a budget is a
  deliberate edit to that file, visible in the diff.

  Globs are expanded with `Path.wildcard/2` against the working tree, dotfiles included, which is
  what the harness sees too: an untracked file counts. The rationale for each check is on
  `Tack.RulesCheck`; this task owns the IO.

  A `mix quality` step; runs in CI.
  """

  use Mix.Task

  use Boundary, classify_to: Tack
  alias Tack.RulesCheck

  @claude_md "CLAUDE.md"
  @rules_dir ".claude/rules"
  @budget_path ".claude/rules/BUDGET"
  @lib_glob "lib/**/*.ex"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [tighten: :boolean])

    claude_md = read!(@claude_md)

    budget =
      @budget_path
      |> read_or_empty()
      |> RulesCheck.parse_budget()

    inputs = %{
      claude_md_lines: line_count(claude_md),
      expanded: expanded_rules(),
      lib_files: files(@lib_glob),
      budget: budget
    }

    inputs =
      if Keyword.get(opts, :tighten, false), do: tighten!(inputs), else: inputs

    report = RulesCheck.evaluate(inputs)

    case report.findings do
      [] ->
        Mix.shell().info(
          "rules_check: CLAUDE.md #{report.measured.claude_md_lines} lines " <>
            "(budget #{inputs.budget["claude_md_lines"]}); " <>
            "#{map_size(inputs.expanded)} rules files, no orphan glob; " <>
            "#{report.measured.uncovered_lib_files} uncovered lib files " <>
            "(budget #{inputs.budget["uncovered_lib_files"]})"
        )

      findings ->
        Enum.each(findings, fn finding -> Mix.shell().error("rules_check: " <> finding) end)
        Mix.raise("rules_check: #{length(findings)} finding(s) — see above.")
    end
  end

  # Lower every budget to today's measurement (never raise), write the file, and carry the written
  # budget into the evaluation below.
  defp tighten!(inputs) do
    measured = RulesCheck.evaluate(inputs).measured

    budget =
      RulesCheck.tighten(inputs.budget, %{
        "claude_md_lines" => measured.claude_md_lines,
        "uncovered_lib_files" => measured.uncovered_lib_files
      })

    @budget_path
    |> Path.dirname()
    |> File.mkdir_p!()

    File.write!(@budget_path, RulesCheck.render_budget(budget))
    Mix.shell().info("rules_check: wrote #{@budget_path}")
    %{inputs | budget: budget}
  end

  # Each rules file → each of its globs → the regular files it matches today.
  defp expanded_rules do
    @rules_dir
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Map.new(fn rules_file ->
      by_glob =
        rules_file
        |> read!()
        |> RulesCheck.globs()
        |> Map.new(fn glob -> {glob, files(glob)} end)

      {rules_file, by_glob}
    end)
  end

  # `**` also matches directories; only files can be read, so only files count.
  defp files(glob) do
    glob
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
  end

  # The file's line count as an editor shows it: a trailing newline does not add an empty line.
  defp line_count(text) do
    text
    |> String.trim_trailing("\n")
    |> String.split("\n")
    |> length()
  end

  defp read!(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents

      {:error, reason} ->
        Mix.raise("rules_check: cannot read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp read_or_empty(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents

      {:error, :enoent} ->
        ""

      {:error, reason} ->
        Mix.raise("rules_check: cannot read #{path}: #{:file.format_error(reason)}")
    end
  end
end
