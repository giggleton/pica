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

  for {{file, index}, cases} <-
        Enum.group_by(expected_shaping, fn expected -> {expected.file, expected.index} end) do
    @file_name file
    @index index
    @cases cases

    test "#{file}, font #{index}, shapes every test string as hb-shape does" do
      font = load_font(@file_name, index: @index)

      mismatches =
        for expected <- @cases,
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
  end

  describe "Lato Regular" do
    setup do
      %{font: load_font("Lato-Regular.ttf")}
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
            {:language, "en US", "en US"}
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
