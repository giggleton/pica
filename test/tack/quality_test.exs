defmodule Tack.QualityTest do
  use ExUnit.Case, async: true

  alias Tack.Quality

  @configured [
    {"format (write)", "mix format", skip_on_check: true},
    {"hex.audit", "mix hex.audit"},
    {"test", "mix test --warnings-as-errors"},
    {"format", "mix format --check-formatted"}
  ]

  describe "steps/2" do
    test "runs every step locally, in the declared order" do
      assert Quality.steps(@configured, false) ==
               {:ok,
                [
                  {"format (write)", "mix format"},
                  {"hex.audit", "mix hex.audit"},
                  {"test", "mix test --warnings-as-errors"},
                  {"format", "mix format --check-formatted"}
                ]}
    end

    test "--check drops only the steps marked skip_on_check" do
      {:ok, steps} = Quality.steps(@configured, true)
      assert Enum.map(steps, fn {label, _command} -> label end) == ["hex.audit", "test", "format"]
    end

    test "a missing key is an error naming the fix, not an empty gate" do
      assert {:error, message} = Quality.steps(nil, false)
      assert message =~ "quality_steps"
      assert message =~ "tack.install"
    end

    test "a malformed step is an error, so a typo cannot silently drop a check" do
      assert {:error, message} = Quality.steps([{"credo", "mix credo"}, "mix test"], false)
      assert message =~ ~s("mix test")

      assert {:error, _message} = Quality.steps(%{}, false)
    end
  end

  describe "hex_version_check/1" do
    test "accepts a Hex that reports advisories" do
      assert Quality.hex_version_check("2.5.0") == :ok
      assert Quality.hex_version_check("2.6.1") == :ok
    end

    test "refuses an older Hex, since its hex.audit checks retirements only and exits 0" do
      assert {:error, message} = Quality.hex_version_check("2.4.9")
      assert message =~ "2.4.9"
      assert message =~ Quality.minimum_hex_version()
      assert message =~ "mix local.hex --force"
    end

    test "refuses to run without Hex at all" do
      assert {:error, message} = Quality.hex_version_check(:none)
      assert message =~ "mix local.hex --force"
    end
  end
end
