defmodule Pica.GlyphOutlinesTest do
  use ExUnit.Case, async: true

  alias PicaTest.TableDirectory

  @fonts "test/fonts"

  # Within a thousandth of a font unit: CFF coordinates can fall between units, and skrifa keeps
  # them as 32-bit floats, where fontTools keeps 64-bit ones.
  @tolerance 0.001

  # Golden: test/fixtures/glyph_outlines.exs is fontTools' drawing of a sample of every test
  # font's glyphs (its header names the version, and says how each outline format is drawn and
  # why each glyph is in the sample), written by test/support/ground_truth/glyph_outlines.py.
  # A changed test font or a regenerated fixture moves it; nothing in Pica does.
  @fixture "test/fixtures/glyph_outlines.exs"
  @external_resource @fixture
  {expected_outlines, _bindings} = Code.eval_file(@fixture)

  for expected <- expected_outlines do
    @expected expected

    describe "#{expected.file}, font #{expected.index}, as fontTools draws it" do
      setup do
        font = load_font(@expected.file, index: @expected.index)
        glyph_ids = Enum.map(@expected.glyphs, fn glyph -> glyph.glyph_id end)
        %{outlines: Pica.glyph_outlines(font, glyph_ids)}
      end

      # fontTools starts a contour that begins off the curve elsewhere than FreeType does, so each
      # contour is compared as a closed loop, wherever it starts.
      test "glyph_outlines/2 draws each sampled glyph's contours", %{outlines: outlines} do
        assert length(outlines) == length(@expected.glyphs)

        mismatches =
          outlines
          |> Enum.zip_with(@expected.glyphs, fn actual, expected ->
            {expected, same_outline?(actual, expected.outline)}
          end)
          |> Enum.reject(fn {_expected, same?} -> same? end)
          |> Enum.map(fn {expected, _same?} -> {expected.glyph_id, expected.reasons} end)

        assert mismatches == []
      end

      test "every coordinate is a float", %{outlines: outlines} do
        coordinates = Enum.flat_map(outlines, &coordinates/1)

        assert coordinates != []
        assert Enum.all?(coordinates, &is_float/1)
      end

      test "no contour draws a line back to its start before closing", %{outlines: outlines} do
        closing_lines =
          for outline <- outlines,
              outline != :none,
              contour <- contours(outline),
              closes_with_line_to_start?(contour),
              do: contour

        assert closing_lines == []
      end
    end
  end

  # More than 64 glyphs go to the NIF on a dirty scheduler, which shares the normal one's
  # function; this catches glyph_outlines/2 sending many glyphs to a name that draws them
  # otherwise.
  test "more than 64 glyphs draw as the normal-scheduler NIF draws them" do
    font = load_font("Lato-Regular.ttf")
    glyph_count = Pica.info(font).glyph_count
    assert glyph_count > 64
    glyph_ids = Enum.to_list(0..(glyph_count - 1))

    {:ok, expected} =
      font
      |> Pica.Font.resource()
      |> Pica.Native.glyph_outlines(glyph_ids)

    assert Pica.glyph_outlines(font, glyph_ids) == expected
  end

  describe "a font with no outlines" do
    test "every glyph of a font with no outline table draws nothing, and has no box" do
      {:ok, font} =
        "Lato-Regular.ttf"
        |> read_font()
        |> TableDirectory.rename_table("glyf", "glyg")
        |> Pica.load()

      assert Pica.info(font).outlines == :none
      glyph_ids = Pica.glyph_ids(font, "AV M")
      assert Pica.glyph_outlines(font, glyph_ids) == [:none, :none, :none, :none]
      assert Pica.glyph_boxes(font, glyph_ids) == [:none, :none, :none, :none]
    end
  end

  # Whether two outlines draw the same contours in the same order, each the same closed loop.
  defp same_outline?(:none, :none), do: true
  defp same_outline?(:none, _expected), do: false
  defp same_outline?(_actual, :none), do: false

  defp same_outline?(actual, expected) do
    actual_loops = loops(actual)
    expected_loops = loops(expected)

    length(actual_loops) == length(expected_loops) and
      actual_loops
      |> Enum.zip_with(expected_loops, &same_loop?/2)
      |> Enum.all?()
  end

  defp loops(outline) do
    outline
    |> contours()
    |> Enum.map(&loop/1)
  end

  # An outline's contours, each its commands from `:move` up to, not including, `:close`.
  defp contours(outline) do
    Enum.chunk_while(
      outline,
      [],
      fn
        :close, contour -> {:cont, Enum.reverse(contour), []}
        command, contour -> {:cont, [command | contour]}
      end,
      fn [] -> {:cont, []} end
    )
  end

  # A contour as a closed loop: its segments, each `{kind, coordinates}`, the coordinates its
  # control points' then its end point's, with the line back to the start made explicit where
  # `:close` draws it. The start itself is the last segment's end, so a loop is the same drawing
  # whichever segment it is read from.
  defp loop([{:move, start_x, start_y} | commands]) do
    commands
    |> Enum.map(fn command ->
      [kind | coordinates] = Tuple.to_list(command)
      {kind, coordinates}
    end)
    |> Enum.reverse()
    |> close_loop([start_x, start_y])
    |> Enum.reverse()
  end

  # The segments, last first, with a line to `start` ahead of them unless the last ends there.
  defp close_loop([], _start), do: []

  defp close_loop([{_kind, coordinates} | _earlier] = segments_backward, start) do
    if near?(Enum.take(coordinates, -2), start),
      do: segments_backward,
      else: [{:line, start} | segments_backward]
  end

  # Whether one rotation of `actual`, read from another of its segments, is `expected`.
  defp same_loop?(actual, expected) when length(actual) != length(expected), do: false
  defp same_loop?([], []), do: true

  defp same_loop?(actual, expected) do
    Enum.any?(0..(length(actual) - 1), fn shift ->
      {head, tail} = Enum.split(actual, shift)

      (tail ++ head)
      |> Enum.zip_with(expected, fn {actual_kind, actual_coordinates},
                                    {expected_kind, expected_coordinates} ->
        actual_kind == expected_kind and near?(actual_coordinates, expected_coordinates)
      end)
      |> Enum.all?()
    end)
  end

  defp near?(actual, expected) do
    length(actual) == length(expected) and
      actual
      |> Enum.zip_with(expected, fn actual_value, expected_value ->
        abs(actual_value - expected_value) <= @tolerance
      end)
      |> Enum.all?()
  end

  defp closes_with_line_to_start?([{:move, start_x, start_y} | segments]) do
    case List.last(segments) do
      {:line, x, y} -> near?([x, y], [start_x, start_y])
      _other -> false
    end
  end

  # Every number in a command, control points and end point alike.
  defp coordinates(:none), do: []

  defp coordinates(outline) do
    outline
    |> Enum.reject(fn command -> command == :close end)
    |> Enum.flat_map(fn command ->
      [_kind | coordinates] = Tuple.to_list(command)
      coordinates
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
