defmodule Pica.LoadTest do
  use ExUnit.Case, async: true

  alias PicaTest.TableDirectory

  @fonts "test/fonts"

  # Golden: test/fixtures/font_info.exs is fontTools' reading of every test font (its header names
  # the version), written by test/support/ground_truth/font_info.py. A changed test font or a
  # regenerated fixture moves it; nothing in Pica does.
  @fixture "test/fixtures/font_info.exs"
  @external_resource @fixture
  {expected_info, _bindings} = Code.eval_file(@fixture)

  for expected <- expected_info do
    @expected expected
    test "info/1 reads #{expected.file}, font #{expected.index}, as fontTools does" do
      bytes = read_font(@expected.file)
      {:ok, font} = Pica.load(bytes, index: @expected.index)
      assert Pica.info(font) == Map.delete(@expected, :file)
    end
  end

  describe "a font that does not load" do
    test "bytes that begin with no font container's signature are an unknown format" do
      assert Pica.load("") == {:error, :unknown_format}
      assert Pica.load("%PDF-1.7") == {:error, :unknown_format}
    end

    test "a font cut off inside its table directory is truncated" do
      cut_font =
        "Lato-Regular.ttf"
        |> read_font()
        |> binary_part(0, 20)

      assert Pica.load(cut_font) == {:error, :truncated}
    end

    test "a font cut off before the end of a table it lists is truncated" do
      cut_font =
        "Lato-Regular.ttf"
        |> read_font()
        |> binary_part(0, 300_000)

      assert Pica.load(cut_font) == {:error, :truncated}
    end

    test "an index past the end of a collection is out of range, naming how many fonts it holds" do
      collection = read_font("Roboto-Collection.ttc")
      assert Pica.load(collection, index: 2) == {:error, {:index_out_of_range, 2}}
    end

    test "a single font has no font at index 1" do
      font = read_font("Lato-Regular.ttf")
      assert Pica.load(font, index: 1) == {:error, {:index_out_of_range, 1}}
    end

    test "a font listing none of the tables Pica reads is missing the first of them" do
      # A TrueType table directory with no tables: version, table count, three search fields.
      empty_font = <<0x00010000::32, 0::16, 0::16, 0::16, 0::16>>
      assert Pica.load(empty_font) == {:error, {:missing_table, "head"}}
    end

    test "a font without advance widths is missing its hmtx table" do
      font =
        "Lato-Regular.ttf"
        |> read_font()
        |> TableDirectory.rename_table("hmtx", "hmty")

      assert Pica.load(font) == {:error, {:missing_table, "hmtx"}}
    end

    test "glyf outlines without the loca table that indexes them are malformed" do
      # The detail is prose for a person; only its presence is the contract.
      font =
        "Lato-Regular.ttf"
        |> read_font()
        |> TableDirectory.rename_table("loca", "locb")

      assert match?({:error, {:malformed, detail}} when is_binary(detail), Pica.load(font))
    end

    test "WOFF and WOFF2 data that does not decode is malformed, with a detail to read" do
      # The detail is prose for a person; only its presence is the contract.
      zeros = :binary.copy(<<0>>, 60)

      assert match?(
               {:error, {:malformed, detail}} when is_binary(detail),
               Pica.load("wOFF" <> zeros)
             )

      assert match?(
               {:error, {:malformed, detail}} when is_binary(detail),
               Pica.load("wOF2" <> zeros)
             )
    end
  end

  describe "load/2's options" do
    test "a negative index is refused at the call" do
      font = read_font("Lato-Regular.ttf")
      assert_raise NimbleOptions.ValidationError, fn -> Pica.load(font, index: -1) end
    end

    test "an unknown option is refused at the call" do
      font = read_font("Lato-Regular.ttf")
      assert_raise NimbleOptions.ValidationError, fn -> Pica.load(font, size: 12) end
    end
  end

  defp read_font(file) do
    @fonts
    |> Path.join(file)
    |> File.read!()
  end
end
