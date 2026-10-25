defmodule PicaTest.TableDirectory do
  @moduledoc """
  Damaging a test font's table directory, to make fonts that a test needs to fail in one named
  way.

  A plain font (not a collection, WOFF or WOFF2) opens with a 12-byte header whose bytes 4 and 5
  count its tables, then one 16-byte record per table: its four-letter tag, a checksum, and the
  table's offset and length. Only the records are changed, never a table's data, and checksums
  are left as they were, since Pica does not check them.

      font = File.read!("test/fonts/Lato-Regular.ttf")
      TableDirectory.rename_table(font, "loca", "locb")   # the font now has no loca table
      TableDirectory.empty_table(font, "glyf")            # glyf is now zero bytes long

  A table is looked up by binary search over the sorted tags, so a new tag must sort where the
  old one did; renaming to the next tag up keeps the order in practice.
  """

  use Boundary, deps: []

  @header_size 12
  @record_size 16

  @doc "The font with the table tagged `from` listed under the tag `to` instead."
  @spec rename_table(binary(), <<_::32>>, <<_::32>>) :: binary()
  def rename_table(font, <<_::binary-4>> = from, <<_::binary-4>> = to) do
    replace_in_record(font, from, 0, to)
  end

  @doc "The font with the table tagged `tag` declared zero bytes long."
  @spec empty_table(binary(), <<_::32>>) :: binary()
  def empty_table(font, <<_::binary-4>> = tag) do
    replace_in_record(font, tag, 12, <<0::32>>)
  end

  defp replace_in_record(font, tag, field_offset, replacement) do
    <<_version::32, table_count::16, _rest::binary>> = font
    position = @header_size + record_index!(font, tag, table_count) * @record_size + field_offset
    width = byte_size(replacement)
    <<before::binary-size(^position), _old::binary-size(^width), rest::binary>> = font
    before <> replacement <> rest
  end

  defp record_index!(font, tag, table_count) do
    Enum.find(0..(table_count - 1)//1, fn record_index ->
      binary_part(font, @header_size + record_index * @record_size, 4) == tag
    end) || raise ArgumentError, "the font lists no #{inspect(tag)} table"
  end
end
