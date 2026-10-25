# Measures where the test suite's time goes. Run from anywhere in the repo:
#
#     elixir .claude/skills/test-timing/measure.exs [--runs N] [--no-sweep] [--no-trace]
#
# Prints a Markdown report on stdout. SKILL.md (beside this file) says how to read it and when not
# to trust it. The runs are all ordinary `mix test` invocations against the shared test database;
# nothing here writes to the tree.

defmodule TestTiming do
  @repo Path.expand("../../..", __DIR__)
  @finished ~r/Finished in ([\d.]+) seconds \((?:([\d.]+)s on load, )?([\d.]+)s async, ([\d.]+)s sync\)/
  @outlier_ms 250.0

  # Code signals for why a sync file is sync, checked against non-comment lines. A heuristic, and a
  # generic one — add this repo's own singletons and process starters as you learn them. The report
  # prints each file's header beside its bucket so a person confirms it.
  @config ~r/TestEnv\.(put|merge|delete)_app_env|Application\.(put_env|delete_env|put_all_env)\(/
  @process ~r/start_supervised!?\(|start_link\(|GenServer\.start|DynamicSupervisor\.start_child/
  @singleton ~r/Presence\.|:telemetry\.attach|:ets\.|:persistent_term\.|Registry\.register/

  # The same questions asked of the header, for a file whose blocker is one call away (a LiveView
  # that starts a real process, a stub that writes env).
  @header_config ~r/app env|application env|app-wide .*config|config|put_env/i
  @header_process ~r/process|GenServer|server|worker|sandbox/i
  @header_singleton ~r/singleton|presence|telemetry|ETS|Registry key/i

  def main(arguments) do
    {options, _rest} =
      OptionParser.parse!(arguments, strict: [runs: :integer, sweep: :boolean, trace: :boolean])

    runs = Keyword.get(options, :runs, 3)
    File.cd!(@repo)

    preflight()
    IO.puts("# Test timing — #{Date.utc_today()}\n")
    plain_runs(runs)
    load_floor()
    if Keyword.get(options, :sweep, true), do: sweep()
    if Keyword.get(options, :trace, true), do: trace()
  end

  defp preflight do
    others =
      case System.cmd("pgrep", ["-af", "mix test"], stderr_to_stdout: true) do
        {output, 0} -> String.split(output, "\n", trim: true)
        {_output, _status} -> []
      end

    [load | _rest] = String.split(File.read!("/proc/loadavg"))

    IO.puts(:stderr, "schedulers #{System.schedulers_online()}, load average #{load}")

    if others != [] do
      IO.puts(
        :stderr,
        "WARNING: other `mix test` processes are running — timings will be skewed:"
      )

      Enum.each(others, fn line -> IO.puts(:stderr, "  " <> line) end)
    end
  end

  defp mix_test(arguments, label) do
    IO.puts(:stderr, "running mix test #{Enum.join(arguments, " ")} (#{label})…")
    {output, _status} = System.cmd("mix", ["test" | arguments], stderr_to_stdout: true)

    case Regex.run(@finished, output) do
      [_match, total, load, async, sync] ->
        {output,
         %{total: float(total), load: float(load), async: float(async), sync: float(sync)}}

      nil ->
        raise "no `Finished in` line from mix test #{Enum.join(arguments, " ")}:\n" <>
                String.slice(output, -2_000, 2_000)
    end
  end

  defp float(""), do: 0.0
  defp float(text), do: text |> Float.parse() |> elem(0)

  defp plain_runs(runs) do
    splits =
      Enum.map(1..runs, fn run ->
        {_output, split} = mix_test([], "plain run #{run}/#{runs}")
        split
      end)

    IO.puts("## Wall split (plain runs)\n")
    IO.puts("| run | total | async | sync |\n|---|---|---|---|")

    splits
    |> Enum.with_index(1)
    |> Enum.each(fn {split, run} ->
      IO.puts("| #{run} | #{split.total}s | #{split.async}s | #{split.sync}s |")
    end)

    IO.puts(
      "| median | #{median(splits, :total)}s | #{median(splits, :async)}s | #{median(splits, :sync)}s |\n"
    )
  end

  defp median(splits, field) do
    sorted = splits |> Enum.map(fn split -> Map.fetch!(split, field) end) |> Enum.sort()
    Enum.at(sorted, div(length(sorted), 2))
  end

  defp load_floor do
    {_output, split} = mix_test(["--only", "no_such_tag"], "load only")

    IO.puts("## Load floor\n")

    IO.puts(
      "Loading the test files with every test excluded: #{split.total}s. ExUnit counts this " <>
        "inside the async figure, which can never drop below it.\n"
    )
  end

  defp sweep do
    rows =
      Enum.map([8, 64], fn cases ->
        {_output, split} = mix_test(["--max-cases", Integer.to_string(cases)], "sweep")
        {cases, split}
      end)

    IO.puts("## Concurrency sweep\n")
    IO.puts("| max_cases | async | sync |\n|---|---|---|")

    Enum.each(rows, fn {cases, split} ->
      IO.puts("| #{cases} | #{split.async}s | #{split.sync}s |")
    end)

    IO.puts(
      "\nA flat async column means the phase is not short of workers: work moved out of the sync " <>
        "tail mostly disappears into it. A falling one means it is, and moved work adds wall time.\n"
    )
  end

  # `--slowest-modules` forces trace mode (`max_cases: 1`), so every figure from this run is a
  # serial cost. That is exactly what a sync file costs in a normal run; for an async file it is a
  # sum that normally overlaps.
  defp trace do
    {output, split} = mix_test(["--slowest-modules", "1000"], "trace")
    module_times = module_times(output)
    test_times = test_times(output)
    sync_files = sync_files()

    rows =
      sync_files
      |> Enum.map(fn file ->
        milliseconds = Map.get(module_times, file, 0.0)
        {bucket, detail} = bucket(file)
        %{file: file, milliseconds: milliseconds, bucket: bucket, detail: detail}
      end)
      |> Enum.sort_by(fn row -> -row.milliseconds end)

    sync_total = rows |> Enum.map(fn row -> row.milliseconds end) |> Enum.sum()

    IO.puts("## Sync tail by blocker (trace run: #{split.sync}s sync)\n")
    IO.puts("| bucket | files | time | share |\n|---|---|---|---|")

    rows
    |> Enum.group_by(fn row -> row.bucket end)
    |> Enum.sort_by(fn {_bucket, members} ->
      -Enum.sum(Enum.map(members, fn row -> row.milliseconds end))
    end)
    |> Enum.each(fn {bucket, members} ->
      milliseconds = members |> Enum.map(fn row -> row.milliseconds end) |> Enum.sum()

      IO.puts(
        "| #{bucket} | #{length(members)} | #{seconds(milliseconds)} | " <>
          "#{percent(milliseconds, sync_total)} |"
      )
    end)

    IO.puts("\n### Every sync file\n")
    IO.puts("Confirm each bucket against the header before trusting a sum.\n")

    Enum.each(rows, fn row ->
      IO.puts("- **#{seconds(row.milliseconds)}** `#{row.file}` — #{row.bucket}: #{row.detail}")

      row.file
      |> header()
      |> Enum.each(fn line -> IO.puts("  > " <> line) end)
    end)

    IO.puts("\n### Slow tests inside sync files (≥ #{trunc(@outlier_ms)}ms)\n")

    IO.puts(
      "A slow test whose file is sync only because of *other* tests in it is the cheapest win: " <>
        "split it into an async file.\n"
    )

    rows
    |> Enum.flat_map(fn row ->
      test_times
      |> Map.get(row.file, [])
      |> Enum.filter(fn {milliseconds, _name} -> milliseconds >= @outlier_ms end)
      |> Enum.map(fn {milliseconds, name} -> {milliseconds, name, row} end)
    end)
    |> Enum.sort_by(fn {milliseconds, _name, _row} -> -milliseconds end)
    |> Enum.each(fn {milliseconds, name, row} ->
      IO.puts(
        "- #{seconds(milliseconds)} (#{percent(milliseconds, row.milliseconds)} of its file) " <>
          "`#{row.file}` — #{name}"
      )
    end)
  end

  defp module_times(output) do
    summary = output |> String.split("slowest (", parts: 2) |> List.last()

    ~r/^\S+ \(([\d.]+)ms\)\n \[(.+?)\]/m
    |> Regex.scan(summary)
    |> Map.new(fn [_match, milliseconds, file] -> {file, float(milliseconds)} end)
  end

  defp test_times(output) do
    body = output |> String.split("\nFinished in", parts: 2) |> List.first()

    body
    |> String.split(~r/\n(?=\S+ \[test\/)/)
    |> Enum.flat_map(fn block ->
      case Regex.run(~r/^\S+ \[(test\/[^\]]+)\]/, block) do
        [_match, file] ->
          # Trace prints each test twice on one line, pending and then timed; the name may not
          # cross a `[`, so the match starts at the timed copy.
          tests =
            ~r/\* test ([^\[\r\n]+?) \(([\d.]+)ms\) \[L/
            |> Regex.scan(block)
            |> Enum.map(fn [_match, name, milliseconds] -> {float(milliseconds), name} end)

          [{file, tests}]

        nil ->
          []
      end
    end)
    |> Map.new()
  end

  # A module-level `use … async: false` sits at two spaces; fabricated modules inside a test's
  # heredoc (a credo check test) sit deeper and are not the file's own.
  defp sync_files do
    "test/**/*_test.exs"
    |> Path.wildcard()
    |> Enum.filter(fn file -> File.read!(file) =~ ~r/^  use \S+, async: false/m end)
  end

  # Every blocker a file shows, not the worst one: a singleton hit in one test of ninety is a split
  # candidate, not a whole-file floor, and only the counts tell those apart. The bucket is the
  # combination; the detail carries the line counts and which singleton matched.
  defp bucket(file) do
    code_lines =
      file
      |> File.read!()
      |> String.split("\n")
      |> Enum.reject(fn line -> String.starts_with?(String.trim_leading(line), "#") end)

    counts = [
      {"config", count_lines(code_lines, @config)},
      {"process", count_lines(code_lines, @process)},
      {"singleton", count_lines(code_lines, @singleton)}
    ]

    case Enum.filter(counts, fn {_kind, count} -> count > 0 end) do
      [] ->
        text = Enum.join(header(file), " ")

        kinds =
          [
            {"config", text =~ @header_config},
            {"process", text =~ @header_process},
            {"singleton", text =~ @header_singleton}
          ]
          |> Enum.filter(fn {_kind, found?} -> found? end)
          |> Enum.map(fn {kind, _found?} -> kind end)

        {label(kinds), "from the header only"}

      found ->
        detail =
          Enum.map_join(found, ", ", fn {kind, count} -> "#{kind} ×#{count}" end) <>
            singleton_names(code_lines)

        {label(Enum.map(found, fn {kind, _count} -> kind end)), detail}
    end
  end

  defp count_lines(lines, pattern), do: Enum.count(lines, fn line -> line =~ pattern end)

  defp singleton_names(lines) do
    case lines |> Enum.flat_map(fn line -> Regex.scan(@singleton, line) end) |> Enum.uniq() do
      [] -> ""
      names -> " (" <> Enum.map_join(names, ", ", fn [name | _groups] -> name end) <> ")"
    end
  end

  defp label([]), do: "no blocker found"
  defp label(kinds), do: Enum.join(kinds, " + ")

  # The comment block above the `use` line, where the repo states a sync file's blocker.
  defp header(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.take_while(fn line -> not (line =~ ~r/^  use /) end)
    |> Enum.filter(fn line -> String.starts_with?(line, "  #") end)
    |> Enum.map(fn line -> String.trim_leading(line, "  # ") end)
  end

  defp seconds(milliseconds), do: "#{Float.round(milliseconds / 1000, 2)}s"

  defp percent(_part, whole) when whole == 0, do: "—"
  defp percent(part, whole), do: "#{Float.round(100 * part / whole, 1)}%"
end

TestTiming.main(System.argv())
