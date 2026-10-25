defmodule PicaCredo.ChecksTest do
  # The one file that loads the repo-local credo checks: requiring a source twice in one VM
  # redefines its module, and the warning fails the gate (`.credo/checks/README.md`).
  use Credo.Test.Case, async: true

  checks = Path.expand("../.credo/checks/*.ex", __DIR__)

  for path <- Path.wildcard(checks) do
    Code.require_file(path)
  end

  alias PicaCredo.Check.ZipMap

  # Credo is a `runtime: false` dependency, so its services, which parse a source, start here.
  setup_all do
    {:ok, _applications} = Application.ensure_all_started(:credo)
    :ok
  end

  # A module whose one function's body is `body`, as a source file credo can read.
  defp source(body) do
    to_source_file("""
    defmodule Sample do
      def run(positions, labels) do
        #{body}
      end
    end
    """)
  end

  describe "ZipMap" do
    test "a zip piped into a map is reported at the map, naming the one-pass function" do
      """
      positions
        |> Enum.zip(labels)
        |> Enum.map(fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue(fn issue ->
        assert {issue.line_no, issue.column, issue.trigger} == {5, 6, "Enum.map"}
        assert issue.message =~ "Enum.zip_with"
      end)
    end

    test "a zip of a list of enumerables piped into a map is reported" do
      """
      [positions, labels]
        |> Enum.zip()
        |> Enum.map(fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a zip call piped into a map is reported" do
      """
      Enum.zip(positions, labels) |> Enum.map(fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a zip and map in the middle of a longer pipe are reported" do
      """
      positions
        |> Enum.sort()
        |> Enum.zip(labels)
        |> Enum.map(fn {position, label} -> {position, label} end)
        |> Enum.reverse()
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a zip passed to a map is reported" do
      """
      Enum.map(Enum.zip(positions, labels), fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a piped zip passed to a map is reported" do
      """
      Enum.map(positions |> Enum.zip(labels), fn {position, label} -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> assert_issue()
    end

    test "a zip with in one pass is not reported" do
      """
      Enum.zip_with(positions, labels, fn position, label -> {position, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> refute_issues()
    end

    test "a zip piped into something other than a map is not reported" do
      """
      positions
        |> Enum.zip(labels)
        |> Map.new()
      """
      |> source()
      |> run_check(ZipMap)
      |> refute_issues()
    end

    test "a map of something other than a zip is not reported, piped or passed" do
      """
      sorted = positions |> Enum.sort() |> Enum.map(fn position -> position end)
      Enum.map(Enum.sort(labels), fn label -> label end)
      Enum.map(labels |> Enum.sort(), fn label -> {sorted, label} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> refute_issues()
    end

    test "a zip or a map from another module than Enum is not reported" do
      """
      lazy = positions |> Stream.zip(labels) |> Enum.map(fn pair -> pair end)
      positions |> Enum.zip(labels) |> Stream.map(fn pair -> {lazy, pair} end)
      """
      |> source()
      |> run_check(ZipMap)
      |> refute_issues()
    end
  end
end
