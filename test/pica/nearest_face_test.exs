defmodule Pica.NearestFaceTest do
  use ExUnit.Case, async: true

  alias Pica.NearestFace

  describe "choose/3" do
    test "each face is its family's font of that kind" do
      faces = [
        installed("Family", 400, false),
        installed("Family", 700, false),
        installed("Family", 400, true),
        installed("Family", 700, true)
      ]

      for {face, weight, italic} <- [
            {:plain, 400, false},
            {:bold, 700, false},
            {:italic, 400, true},
            {:bold_italic, 700, true}
          ] do
        assert {:ok, %{weight: ^weight, italic: ^italic}} =
                 NearestFace.choose(faces, "Family", face)
      end
    end

    test "the family must be one of a font's names exactly, in any of its languages" do
      faces = [installed(["Family", "Famille"], 400, false), installed("Family Mono", 400, false)]

      assert {:ok, %{families: ["Family", "Famille"]}} =
               NearestFace.choose(faces, "Famille", :plain)

      assert NearestFace.choose(faces, "family", :plain) == :error
      assert NearestFace.choose(faces, "Fam", :plain) == :error
    end

    test "plain is the weight nearest 400 below 600, a tie going to the heavier" do
      assert weight_chosen([300, 500, 600], :plain) == 500
      assert weight_chosen([200, 500], :plain) == 500
      assert weight_chosen([300, 550], :plain) == 300
      assert weight_chosen([100], :plain) == 100
    end

    test "bold is the weight nearest 700 at 600 and above, a tie going to the heavier" do
      assert weight_chosen([600, 800, 500], :bold) == 800
      assert weight_chosen([600, 900], :bold) == 600
      assert weight_chosen([950], :bold) == 950
    end

    test "a family with no font of the kind asked for has no such face" do
      regular_only = [installed("Family", 400, false)]
      assert NearestFace.choose(regular_only, "Family", :bold) == :error
      assert NearestFace.choose(regular_only, "Family", :italic) == :error

      bold_only = [installed("Family", 700, false)]
      assert NearestFace.choose(bold_only, "Family", :plain) == :error

      italic_only = [installed("Family", 400, true)]
      assert NearestFace.choose(italic_only, "Family", :plain) == :error
    end

    test "among equal weights, the width nearest normal is chosen, a tie going to the narrower" do
      faces = [
        installed("Family", 400, false, width: 7),
        installed("Family", 400, false, width: 4),
        installed("Family", 400, false, width: 6)
      ]

      assert {:ok, %{width: 4}} = NearestFace.choose(faces, "Family", :plain)
    end

    test "the choice does not depend on the order the fonts are listed in" do
      faces = [
        installed("Family", 400, false, path: "/fonts/b.ttf"),
        installed("Family", 400, false, path: "/fonts/a.ttf")
      ]

      assert {:ok, %{path: "/fonts/a.ttf"}} = NearestFace.choose(faces, "Family", :plain)

      reversed = Enum.reverse(faces)
      assert {:ok, %{path: "/fonts/a.ttf"}} = NearestFace.choose(reversed, "Family", :plain)
    end

    test "no installed fonts have no face" do
      assert NearestFace.choose([], "Family", :plain) == :error
    end
  end

  defp weight_chosen(weights, face) do
    {:ok, chosen} =
      weights
      |> Enum.map(fn weight -> installed("Family", weight, false) end)
      |> NearestFace.choose("Family", face)

    chosen.weight
  end

  defp installed(families, weight, italic, overrides \\ []) do
    Map.merge(
      %{
        path: "/fonts/family-#{weight}.ttf",
        index: 0,
        families: List.wrap(families),
        weight: weight,
        italic: italic,
        width: 5
      },
      Map.new(overrides)
    )
  end
end
