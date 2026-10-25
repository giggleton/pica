defmodule Tack.RulesCheckTest do
  use ExUnit.Case, async: true

  alias Tack.RulesCheck

  @rules_file """
  ---
  paths:
    - "lib/my_app/rooms/**"
    - "lib/my_app_web/live/open_games_live.ex"
    - lib/my_app/nudge.ex
  ---

  # Rooms

  - a body line that mentions "paths:" and - "lib/not/a/glob.ex" must not be parsed
  """

  describe "globs/1" do
    test "reads the paths list out of the frontmatter, quoted or not" do
      assert RulesCheck.globs(@rules_file) == [
               "lib/my_app/rooms/**",
               "lib/my_app_web/live/open_games_live.ex",
               "lib/my_app/nudge.ex"
             ]
    end

    test "a file without frontmatter or without a paths key declares no globs" do
      assert RulesCheck.globs("# Just a heading\n\nprose") == []
      assert RulesCheck.globs("---\nname: unscoped\n---\nprose") == []
    end
  end

  describe "orphan_globs/1 and uncovered/2" do
    @expanded %{
      ".claude/rules/rooms.md" => %{
        "lib/my_app/rooms/**" => [
          "lib/my_app/rooms/room.ex",
          "lib/my_app/rooms/room/lobby.ex"
        ],
        "lib/my_app/gone.ex" => []
      },
      ".claude/rules/web.md" => %{
        "lib/my_app_web/**" => ["lib/my_app_web/live/draft_live.ex"]
      }
    }
    @lib_files [
      "lib/mix/tasks/my_app.notice.ex",
      "lib/my_app/rooms/room.ex",
      "lib/my_app/rooms/room/lobby.ex",
      "lib/my_app_web/live/draft_live.ex",
      "lib/my_app/settings.ex"
    ]

    test "a glob that expanded to nothing is an orphan, named with its rules file" do
      assert RulesCheck.orphan_globs(@expanded) == [
               {".claude/rules/rooms.md", "lib/my_app/gone.ex"}
             ]
    end

    test "uncovered lists the lib files no expansion contains, sorted" do
      assert RulesCheck.uncovered(@lib_files, @expanded) == [
               "lib/mix/tasks/my_app.notice.ex",
               "lib/my_app/settings.ex"
             ]
    end

    test "a glob covering nearly every lib file is cross-cutting and does not count as coverage" do
      # Without this, one `lib/**/*.ex` rule would zero the ratchet and every later move would pass.
      expanded = Map.put(@expanded, ".claude/rules/waivers.md", %{"lib/**/*.ex" => @lib_files})

      assert RulesCheck.uncovered(@lib_files, expanded) ==
               RulesCheck.uncovered(@lib_files, @expanded)

      assert RulesCheck.orphan_globs(expanded) == RulesCheck.orphan_globs(@expanded)
    end
  end

  describe "the budget file" do
    test "parses key value lines, ignores comments, blanks and malformed lines" do
      text = """
      # a comment
      claude_md_lines 260

      uncovered_lib_files 27
      not_a_number seven
      lonely_key
      """

      assert RulesCheck.parse_budget(text) == %{
               "claude_md_lines" => 260,
               "uncovered_lib_files" => 27
             }
    end

    test "render then parse is stable, so tighten produces a minimal diff" do
      budget = %{"uncovered_lib_files" => 27, "claude_md_lines" => 260}
      rendered = RulesCheck.render_budget(budget)
      reparsed = RulesCheck.parse_budget(rendered)

      assert reparsed == budget
      assert RulesCheck.render_budget(reparsed) == rendered
      assert rendered =~ "mix tack.rules_check"
    end

    test "tighten lowers, never raises, and seeds a missing key" do
      budget = %{"claude_md_lines" => 260, "uncovered_lib_files" => 27}
      measured = %{"claude_md_lines" => 240, "uncovered_lib_files" => 30, "new_ratchet" => 5}

      assert RulesCheck.tighten(budget, measured) == %{
               "claude_md_lines" => 240,
               "uncovered_lib_files" => 27,
               "new_ratchet" => 5
             }
    end
  end

  describe "evaluate/1" do
    @inputs %{
      claude_md_lines: 260,
      expanded: %{
        ".claude/rules/rooms.md" => %{"lib/my_app/rooms/**" => ["lib/my_app/rooms/room.ex"]}
      },
      lib_files: ["lib/my_app/rooms/room.ex", "lib/my_app/settings.ex"],
      budget: %{"claude_md_lines" => 260, "uncovered_lib_files" => 1}
    }

    test "passes at the budget exactly" do
      report = RulesCheck.evaluate(@inputs)

      assert report.findings == []
      assert report.measured.claude_md_lines == 260
      assert report.measured.uncovered == ["lib/my_app/settings.ex"]
      assert report.measured.orphans == []
    end

    test "one line over the budget is a finding that names both numbers and where to move text" do
      report = RulesCheck.evaluate(%{@inputs | claude_md_lines: 261})

      assert report.measured.claude_md_lines == 261
      assert [finding] = report.findings
      assert finding =~ "261"
      assert finding =~ "260"
      assert finding =~ ".claude/rules"
    end

    test "an orphan glob and a newly uncovered file are each a finding" do
      inputs = %{
        @inputs
        | expanded: %{
            ".claude/rules/rooms.md" => %{
              "lib/my_app/rooms/**" => ["lib/my_app/rooms/room.ex"],
              "lib/my_app/moved.ex" => []
            }
          },
          lib_files: [
            "lib/my_app/rooms/room.ex",
            "lib/my_app/settings.ex",
            "lib/my_app/core/moved.ex"
          ]
      }

      report = RulesCheck.evaluate(inputs)

      assert report.measured.orphans == [{".claude/rules/rooms.md", "lib/my_app/moved.ex"}]

      assert report.measured.uncovered == [
               "lib/my_app/core/moved.ex",
               "lib/my_app/settings.ex"
             ]

      assert [_orphan_finding, _coverage_finding] = report.findings

      # The orphan finding names the glob; the coverage finding names the file that left its glob.
      assert Enum.any?(report.findings, fn finding -> finding =~ ~s("lib/my_app/moved.ex") end)
      assert Enum.any?(report.findings, fn finding -> finding =~ "lib/my_app/core/moved.ex" end)
    end

    test "a missing budget key is a finding rather than a silent pass" do
      [finding] = RulesCheck.evaluate(%{@inputs | budget: %{"claude_md_lines" => 260}}).findings
      assert finding =~ "uncovered_lib_files"
      assert finding =~ "--tighten"
    end
  end
end
