defmodule Pica do
  @moduledoc """
  Text shaping and font metrics for Elixir, through HarfBuzz's Rust port.

  Pica measures text from font files. A caller registers font files under a family name, then
  asks, by family and face, for each string's glyphs: which glyph, which characters it came from,
  how far it advances once kerning, ligatures and contextual forms are applied, and how far it
  would advance unshaped. It also reports font-wide metrics and glyph bounding boxes. Nothing is
  drawn.

  A family name is looked up first among the fonts given to Pica, then, unless the caller opts
  out, among the fonts installed on the machine. Pica never substitutes one font for another:
  names match exactly, a family found in neither place is an error, and a character the font
  lacks shapes to glyph 0.

  ## Font units

  A font draws on a grid of its own, `units_per_em` to the em, where the em is the font size: at
  12 points, a font with 2000 units per em has 2000 units to 12 points. Pica's numbers are in
  these font units.

  ## Loading a font

  `load/2` reads a font from its file's bytes, in any of the containers fonts ship in: a plain
  TrueType or OpenType font, a font collection (several fonts in one file, chosen by `:index`),
  WOFF or WOFF2. `info/1` reports what the font says about itself.
  """

  # The root boundary. It lists every outside library a sub-boundary does, since a sub-boundary
  # may list only what its parent lists (`.claude/rules/dependencies.md`).
  use Boundary,
    deps: [NimbleOptions, {Mix, :compile}, {Rustler, :compile}, {RustlerPrecompiled, :compile}],
    exports: []

  alias Pica.{Font, Native}

  @load_options NimbleOptions.new!(
                  index: [
                    type: :non_neg_integer,
                    default: 0,
                    doc: "Which font to load from a collection, counting from 0."
                  ]
                )

  @typedoc """
  Why a font did not load.

    * `:unknown_format` — the bytes do not begin with the signature of any font container.
    * `:truncated` — the data ends before a structure or a table it declares.
    * `{:index_out_of_range, font_count}` — the file has no font at the index asked for; it
      holds `font_count`.
    * `{:missing_table, tag}` — a table Pica reads to describe a font is absent.
    * `{:malformed, detail}` — anything else that does not read, such as WOFF data that does not
      decode.
  """
  @type load_error ::
          :unknown_format
          | :truncated
          | {:index_out_of_range, non_neg_integer()}
          | {:missing_table, String.t()}
          | {:malformed, String.t()}

  @typedoc """
  What a font says about itself, as `info/1` reports it. Every length is in font units.

    * `:family`, `:subfamily` — the font's family and style names: the typographic names (name
      IDs 16 and 17) where the font has them, else the legacy ones (1 and 2), in English where
      the font has an English name. `:none` when the font names neither.
    * `:units_per_em` — the size of the font's grid.
    * `:ascender`, `:descender`, `:line_gap` — the line metrics of the font's `hhea` table. The
      descender is negative, below the baseline.
    * `:weight_class` — from 100 (thin) to 900 (black), 400 being regular and 700 bold; `:none`
      when the font has no `OS/2` table.
    * `:italic` — whether the font says it is italic.
    * `:glyph_count` — how many glyphs the font holds.
    * `:axes` — a variable font's axes of variation, each with its range and default; empty for a
      font that does not vary.
    * `:container` — what the bytes were: `:sfnt` (a plain font), `:collection`, `:woff` or
      `:woff2`.
    * `:outlines` — what draws the glyphs: `:truetype` (`glyf`), `:cff`, `:cff2`, or `:none`.
    * `:index`, `:font_count` — which font of its file this is, and how many the file holds.
  """
  @type info :: %{
          family: String.t() | :none,
          subfamily: String.t() | :none,
          units_per_em: pos_integer(),
          ascender: integer(),
          descender: integer(),
          line_gap: integer(),
          weight_class: non_neg_integer() | :none,
          italic: boolean(),
          glyph_count: non_neg_integer(),
          axes: [axis()],
          container: :sfnt | :collection | :woff | :woff2,
          outlines: :truetype | :cff | :cff2 | :none,
          index: non_neg_integer(),
          font_count: pos_integer()
        }

  @typedoc "A variable font's axis: its four-letter tag, such as `\"wght\"`, and its range."
  @type axis :: %{tag: String.t(), minimum: float(), default: float(), maximum: float()}

  @doc """
  Loads a font from the bytes of a font file.

  Returns `{:ok, font}`, or `{:error, reason}` for bytes that are not a font Pica can read (see
  `t:load_error/0`). The bytes are copied, so the binary may be dropped afterwards.

  ## Options

  #{NimbleOptions.docs(@load_options)}

  ## Examples

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> Pica.info(font).family
      "Lato"

      iex> Pica.load("not a font")
      {:error, :unknown_format}
  """
  @spec load(binary(), keyword()) :: {:ok, Font.t()} | {:error, load_error()}
  def load(bytes, options \\ []) when is_binary(bytes) do
    options = NimbleOptions.validate!(options, @load_options)

    case Native.load(bytes, options[:index]) do
      {:ok, {resource, info}} -> {:ok, Font.new(resource, info)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  What a loaded font says about itself (see `t:info/0`).

  ## Examples

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Bold.ttf"))
      iex> info = Pica.info(font)
      iex> {info.family, info.subfamily, info.weight_class, info.units_per_em}
      {"Lato", "Bold", 700, 2000}
  """
  @spec info(Font.t()) :: info()
  def info(font), do: Font.info(font)
end
