defmodule Pica.GlyphsTest do
  use ExUnit.Case, async: true

  alias PicaTest.TableDirectory

  @fonts "test/fonts"

  # Golden: test/fixtures/glyph_metrics.exs is fontTools' reading of every glyph of every test font
  # (its header names the version), written by test/support/ground_truth/glyph_metrics.py: hmtx's
  # advance widths, each glyph's control box (its header says how each outline format is read),
  # and the best Unicode character map. Every font has more than 64 glyphs, so its boxes are
  # measured on the dirty scheduler's NIF name.
  # A changed test font or a regenerated fixture moves it; nothing in Pica does.
  @fixture "test/fixtures/glyph_metrics.exs"
  @external_resource @fixture
  {expected_metrics, _bindings} = Code.eval_file(@fixture)

  for expected <- expected_metrics do
    @expected expected

    describe "#{expected.file}, font #{expected.index}, as fontTools reads it" do
      setup do
        font = load_font(@expected.file, index: @expected.index)
        %{font: font, all_glyph_ids: Enum.to_list(0..(length(@expected.advances) - 1))}
      end

      test "glyph_ids/2 maps each character as the character map does", %{font: font} do
        assert Pica.glyph_ids(font, @expected.text) == @expected.glyph_ids
      end

      test "nominal_advances/2 gives every glyph's hmtx advance", context do
        actual = Pica.nominal_advances(context.font, context.all_glyph_ids)
        assert mismatches(actual, @expected.advances) == []
      end

      test "glyph_boxes/2 gives every glyph's control box", context do
        actual = Pica.glyph_boxes(context.font, context.all_glyph_ids)
        assert mismatches(actual, @expected.boxes) == []
      end
    end
  end

  # Golden: the numbers R measures a line by, read from Lato 2.015 with fontTools in the plan's
  # survey of the test fonts, and in test/fixtures/glyph_metrics.exs. Only a different Lato moves
  # them.
  describe "Lato Regular's line measures" do
    setup do
      font = load_font("Lato-Regular.ttf")
      %{font: font}
    end

    test "the top of \"M\" is 1433 font units up", %{font: font} do
      assert [{_x_min, _y_min, _x_max, 1433}] = Pica.glyph_boxes(font, Pica.glyph_ids(font, "M"))
    end

    test "the deepest of \"gjpqyQ\" reaches 365 font units down", %{font: font} do
      deepest =
        font
        |> Pica.glyph_boxes(Pica.glyph_ids(font, "gjpqyQ"))
        |> Enum.map(fn {_x_min, y_min, _x_max, _y_max} -> y_min end)
        |> Enum.min()

      assert deepest == -365
    end
  end

  describe "glyph ids the font does not have" do
    setup do
      font = load_font("Lato-Regular.ttf")
      %{font: font, glyph_count: Pica.info(font).glyph_count}
    end

    # The NIF fails on these too, so each message is checked for what only Pica's own check
    # says: the font's last glyph id, or the value refused.
    test "an id at the glyph count is refused, naming the font's last glyph id", context do
      last_glyph_id = context.glyph_count - 1

      for measure <- [&Pica.nominal_advances/2, &Pica.glyph_boxes/2, &Pica.glyph_outlines/2] do
        error =
          assert_raise ArgumentError, fn ->
            measure.(context.font, [0, context.glyph_count])
          end

        assert error.message =~ inspect(last_glyph_id)
      end
    end

    test "a negative id or one that is not an integer is refused, naming it", %{font: font} do
      for measure <- [&Pica.nominal_advances/2, &Pica.glyph_boxes/2, &Pica.glyph_outlines/2],
          not_a_glyph_id <- [-1, 1.0, "A", nil] do
        error = assert_raise ArgumentError, fn -> measure.(font, [not_a_glyph_id]) end
        assert error.message =~ inspect(not_a_glyph_id)
      end
    end

    test "no glyph ids measure to an empty list", %{font: font} do
      assert Pica.nominal_advances(font, []) == []
      assert Pica.glyph_boxes(font, []) == []
      assert Pica.glyph_outlines(font, []) == []
    end
  end

  test "glyph_ids/2 refuses text that is not UTF-8, showing it" do
    font = load_font("Lato-Regular.ttf")
    error = assert_raise ArgumentError, fn -> Pica.glyph_ids(font, <<0xFF, 0xFE>>) end
    assert error.message =~ inspect(<<0xFF, 0xFE>>)
  end

  test "a glyph whose outline data lies outside its table raises, naming the glyph" do
    # Load reads the glyf table's place, not each glyph's data, so the font loads and the glyph
    # fails only when it is drawn.
    {:ok, font} =
      "Lato-Regular.ttf"
      |> read_font()
      |> TableDirectory.empty_table("glyf")
      |> Pica.load()

    [glyph_id] = Pica.glyph_ids(font, "M")

    for measure <- [&Pica.glyph_boxes/2, &Pica.glyph_outlines/2] do
      error = assert_raise ArgumentError, fn -> measure.(font, [glyph_id]) end
      assert error.message =~ "glyph #{glyph_id}"
    end
  end

  # The glyphs whose measures differ from the fixture's, as {glyph_id, actual, expected}.
  defp mismatches(actual, expected) do
    assert length(actual) == length(expected)

    [actual, expected, Stream.iterate(0, fn glyph_id -> glyph_id + 1 end)]
    |> Enum.zip_with(fn [actual_value, expected_value, glyph_id] ->
      {glyph_id, actual_value, expected_value}
    end)
    |> Enum.reject(fn {_glyph_id, actual_value, expected_value} ->
      actual_value == expected_value
    end)
  end

  defp load_font(file, options \\ []) do
    {:ok, font} =
      file
      |> read_font()
      |> Pica.load(options)

    font
  end

  defp read_font(file) do
    @fonts
    |> Path.join(file)
    |> File.read!()
  end
end
