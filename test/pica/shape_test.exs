defmodule Pica.ShapeTest do
  use ExUnit.Case, async: true

  @fonts "test/fonts"

  # Golden: test/fixtures/shaping.exs is hb-shape's shaping of every test string in every test
  # font, with the options each case sets (its header names the HarfBuzz version), written by
  # test/support/ground_truth/shaping.py, which says how hb-shape was run; each glyph's nominal
  # advance is fontTools' reading of hmtx. A changed test font, a changed test string or a
  # regenerated fixture moves it; nothing in Pica does.
  @fixture "test/fixtures/shaping.exs"
  @external_resource @fixture
  {expected_shaping, _bindings} = Code.eval_file(@fixture)

  # Known differences between harfrust 0.15 and HarfBuzz, each {file, index, text, options}.
  # Where a font has no anchors for a mark, HarfBuzz stacks the mark a gap off its base glyph, the
  # gap the scale over 16 in whole units (62 at scale 1000); harfrust scales the font's units per
  # em over 16 and rounds, so 62.5 becomes 63 and each such mark sits one unit further off. Only
  # a scale that is not a multiple of 16 shows it, and only a mark's y_offset. These fonts lack
  # Hebrew, so its points are marks on .notdef. Each case must differ from hb-shape by exactly
  # that, so a harfrust that fixes it fails here and its entry is removed.
  @harfrust_differences MapSet.new(
                          for {file, index} <- [
                                {"Lato-Bold.ttf", 0},
                                {"Lato-Regular.ttf", 0},
                                {"Roboto-Bare.ttf", 0},
                                {"Roboto-Collection.ttc", 0},
                                {"Roboto-Collection.ttc", 1},
                                {"Roboto[wdth,wght].ttf", 0}
                              ],
                              do: {file, index, "שָׁלוֹם", [scale: 1000]}
                        )

  for {{file, index}, cases} <-
        Enum.group_by(expected_shaping, fn expected -> {expected.file, expected.index} end) do
    @file_name file
    @index index
    {known, agreed} =
      Enum.split_with(cases, fn expected ->
        MapSet.member?(@harfrust_differences, {file, index, expected.text, expected.options})
      end)

    @agreed agreed

    test "#{file}, font #{index}, shapes every test string as hb-shape does" do
      font = load_font(@file_name, index: @index)

      mismatches =
        for expected <- @agreed,
            actual = glyph_tuples(Pica.shape(font, expected.text, expected.options)),
            actual != expected.glyphs,
            do: %{
              text: expected.text,
              options: expected.options,
              actual: actual,
              expected: expected.glyphs
            }

      assert mismatches == []
    end

    if known != [] do
      @known known

      test "#{file}, font #{index}, differs from hb-shape only where harfrust is known to" do
        font = load_font(@file_name, index: @index)

        for expected <- @known do
          actual = glyph_tuples(Pica.shape(font, expected.text, expected.options))
          assert actual != expected.glyphs
          assert length(actual) == length(expected.glyphs)

          Enum.zip_with(actual, expected.glyphs, fn actual_glyph, expected_glyph ->
            assert mark_one_unit_further_off?(actual_glyph, expected_glyph)
          end)
        end
      end
    end
  end

  describe "Lato Regular" do
    setup do
      %{font: load_font("Lato-Regular.ttf")}
    end

    # Text past 1,000 bytes goes to the NIF on a dirty scheduler, which shares the normal one's
    # function; this catches shape/3 sending long text to a name that shapes it otherwise.
    test "text past 1,000 bytes shapes as the normal-scheduler NIF shapes it", %{font: font} do
      text = String.duplicate("AVATAR To ", 120)
      assert byte_size(text) > 1000

      {:ok, expected} =
        font
        |> Pica.Font.resource()
        |> Pica.Native.shape(text, [], nil, nil, nil, nil)

      assert Pica.shape(font, text) == expected
    end

    test "no text shapes to no glyphs", %{font: font} do
      assert Pica.shape(font, "") == []
    end

    # The option's check accepts it too; this catches the NIF taking a narrower integer, which
    # would refuse the value with a bare ArgumentError.
    test "the largest feature value a font can be given is accepted", %{font: font} do
      assert [_a, _v] = Pica.shape(font, "AV", features: [salt: 0xFFFFFFFF])
    end
  end

  describe "misuse" do
    setup do
      %{font: load_font("Lato-Regular.ttf")}
    end

    test "text that is not UTF-8 is refused, showing it", %{font: font} do
      error = assert_raise ArgumentError, fn -> Pica.shape(font, <<0xFF, 0xFE>>) end
      assert error.message =~ inspect(<<0xFF, 0xFE>>)
    end

    # The NIF would refuse some of these too, so each message is checked for the value refused
    # and the option named, which only the option's check puts there.
    test "an option not of its form is refused, naming the option and the value", %{font: font} do
      for {option, value, refused} <- [
            {:features, [kerning: true], :kerning},
            {:direction, :top_to_bottom, :top_to_bottom},
            {:script, "Arabic", "Arabic"},
            {:language, "en US", "en US"},
            {:scale, 0, 0}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Pica.shape(font, "AV", [{option, value}])
          end

        assert error.message =~ inspect(option)
        assert error.message =~ inspect(refused)
      end
    end
  end

  # The same glyph, or the same glyph with its y_offset one unit further from the baseline.
  defp mark_one_unit_further_off?(glyph, glyph), do: true

  defp mark_one_unit_further_off?(
         {glyph_id, cluster, x_advance, nominal_advance, x_offset, actual_y_offset},
         {glyph_id, cluster, x_advance, nominal_advance, x_offset, expected_y_offset}
       ) do
    abs(actual_y_offset) == abs(expected_y_offset) + 1
  end

  defp mark_one_unit_further_off?(_actual_glyph, _expected_glyph), do: false

  defp glyph_tuples(glyphs) do
    Enum.map(glyphs, fn glyph ->
      {glyph.glyph_id, glyph.cluster, glyph.x_advance, glyph.nominal_advance, glyph.x_offset,
       glyph.y_offset}
    end)
  end

  defp load_font(file, options \\ []) do
    {:ok, font} =
      @fonts
      |> Path.join(file)
      |> File.read!()
      |> Pica.load(options)

    font
  end
end
