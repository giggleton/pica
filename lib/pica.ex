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

  ## Glyphs

  A font draws text with glyphs: shapes numbered by glyph id, from 0 to one less than the font's
  `glyph_count`. Glyph 0 is `.notdef`, the shape a font draws for a character it lacks. The
  font's character map ties each character to a glyph, which `glyph_ids/2` reads, though shaping
  may then replace glyphs, joining "f" and "i" into one, say.

  `nominal_advances/2` gives how far each glyph moves the pen on, as the font stores it, before
  shaping adjusts it for kerning or context. `glyph_boxes/2` gives the box around each glyph's
  outline. Both measure at the font's default location: a variable font, which can vary its
  weight or width, is measured as it is drawn when no variation is chosen.

  ## Shaping

  `shape/3` turns text into the glyphs a font draws it with, each positioned: a `Pica.Glyph`
  per glyph, saying which glyph, which characters it came from, and how far it moves the pen on.
  Shaping applies the font's rules through HarfBuzz, the standard shaping engine, in its Rust
  port, harfrust: kerning, which moves particular pairs of letters closer or apart, as in "AV";
  ligatures, one glyph standing for several characters, as in "fi"; letters whose form depends on
  their neighbours, as in Arabic; and accents placed over their letters.

  A font's rules are grouped into OpenType features, each named by a four-letter tag: `kern` for
  kerning, `liga` for the standard ligatures, `smcp` for small capitals. HarfBuzz turns on a
  default set for the text's script, its writing system, such as Latin or Arabic, and the
  `:features` option turns features on or off over it. The script and the direction the text runs
  in are guessed from the text unless given; a language, which picks a font's forms for one
  language, such as Turkish, is used only when given. Shaping is done at the font's default
  location, in font units.
  """

  # The root boundary. It lists every outside library a sub-boundary does, since a sub-boundary
  # may list only what its parent lists (`.claude/rules/dependencies.md`).
  use Boundary,
    deps: [NimbleOptions, {Mix, :compile}, {Rustler, :compile}, {RustlerPrecompiled, :compile}],
    exports: []

  alias Pica.{Font, Glyph, Native}

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
    * `{:missing_table, tag}` — a table Pica reads to describe a font or measure its glyphs is
      absent.
    * `{:malformed, detail}` — anything else that does not read, such as WOFF data that does not
      decode, or advance widths or outlines that do not read.
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

  @typedoc """
  A glyph's box, in font units: `{x_min, y_min, x_max, y_max}`, measured from the point where the
  glyph is drawn, on the baseline, with y rising upward, so `y_min` is negative for a glyph that
  descends below the baseline.

  It is the glyph's control box: the box around every point of its outline, including the
  off-curve points that steer its curves, computed from the outline rather than read from the box
  a font may store. Points are in whole font units: a TrueType glyph built from a scaled copy of
  another has each point rounded to the nearest unit, and a corner of a CFF glyph that falls
  between units is rounded outward.
  """
  @type glyph_box :: {integer(), integer(), integer(), integer()}

  @shape_options NimbleOptions.new!(
                   features: [
                     type: {:custom, Pica.ShapeOptions, :features, []},
                     default: [],
                     type_doc: "`t:keyword/0`",
                     doc: """
                     OpenType features to turn on or off over HarfBuzz's defaults, for the whole
                     text, as a keyword list of each feature's four-character tag and its value:
                     `true` or `false`, or a number, for a feature that chooses among alternate
                     glyphs. A feature the font does not have does nothing. For example
                     `[kern: false, liga: false, smcp: true]`.
                     """
                   ],
                   direction: [
                     type: {:in, [:left_to_right, :right_to_left]},
                     doc: """
                     The direction the text runs in. Guessed from the script when not given, and
                     left to right for text with no script, such as digits.
                     """
                   ],
                   script: [
                     type: {:custom, Pica.ShapeOptions, :script, []},
                     type_doc: "`t:String.t/0`",
                     doc: """
                     The text's script, as its four-letter ISO 15924 code in any case, such as
                     `"Latn"`, `"Arab"` or `"Hebr"`. Guessed from the first character that
                     belongs to a script when not given. A code HarfBuzz does not know shapes as
                     a script with no rules of its own.
                     """
                   ],
                   language: [
                     type: {:custom, Pica.ShapeOptions, :language, []},
                     type_doc: "`t:String.t/0`",
                     doc: """
                     The text's language, as a BCP 47 tag, such as `"tr"` or `"sr-Cyrl"`, which
                     picks the font's forms for that language where it has them. None when not
                     given, so the font's default forms apply.
                     """
                   ]
                 )

  defguardp is_glyph_id(glyph_id, glyph_count)
            when is_integer(glyph_id) and glyph_id >= 0 and glyph_id < glyph_count

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

  @doc """
  The glyph each character of `text` maps to through the font's character map, one per character
  (Unicode code point), with 0 for a character the font lacks.

  This is the font's own mapping, before shaping: a ligature or a contextual form appears only
  in what shaping returns. Raises `ArgumentError` for text that is not valid UTF-8.

  ## Examples

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> Pica.glyph_ids(font, "AV M")
      [3, 40, 2, 24]
  """
  @spec glyph_ids(Font.t(), String.t()) :: [non_neg_integer()]
  def glyph_ids(font, text) when is_binary(text) do
    check_text!(text)

    font
    |> Font.resource()
    |> Native.glyph_ids(text)
    |> measured!()
  end

  @doc """
  Each glyph's nominal advance, in font units: how far the glyph moves the pen on, as the font
  stores it, before shaping adjusts it.

  Raises `ArgumentError` for a glyph id the font does not have.

  ## Examples

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> Pica.nominal_advances(font, Pica.glyph_ids(font, "AV M"))
      [1354, 1354, 512, 1857]
  """
  @spec nominal_advances(Font.t(), [non_neg_integer()]) :: [non_neg_integer()]
  def nominal_advances(font, glyph_ids) when is_list(glyph_ids) do
    check_glyph_ids!(font, glyph_ids)

    font
    |> Font.resource()
    |> Native.nominal_advances(glyph_ids)
    |> measured!()
  end

  @doc """
  Each glyph's box (see `t:glyph_box/0`), or `:none` for a glyph with no outline, such as a
  space.

  Raises `ArgumentError` for a glyph id the font does not have, or for a glyph whose outline
  does not read.

  ## Examples

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> Pica.glyph_boxes(font, Pica.glyph_ids(font, "M g"))
      [{183, 0, 1674, 1433}, :none, {62, -365, 996, 1030}]
  """
  @spec glyph_boxes(Font.t(), [non_neg_integer()]) :: [glyph_box() | :none]
  def glyph_boxes(font, glyph_ids) when is_list(glyph_ids) do
    check_glyph_ids!(font, glyph_ids)

    font
    |> Font.resource()
    |> Native.glyph_boxes(glyph_ids)
    |> measured!()
  end

  @doc """
  Shapes `text` into the glyphs `font` draws it with (see `Pica.Glyph`), in the order they are
  drawn, from left to right, with every length in font units.

  HarfBuzz's default features for the text's script are on, and its direction and script are
  guessed from the text; the options override them. A character the font lacks shapes to glyph
  0, `.notdef`, with its cluster; Pica never draws it from another font. A character Unicode
  marks as default-ignorable, one meant never to be drawn, such as a soft hyphen (U+00AD) or a
  zero-width joiner (U+200D), is hidden as HarfBuzz hides it, whether or not the font has it: it
  shapes to the font's space glyph with an `x_advance` of 0, or, in a font with no space, to no
  glyph at all. Raises `ArgumentError` for text that is not valid UTF-8, and
  `NimbleOptions.ValidationError` for an option not of its form.

  ## Options

  #{NimbleOptions.docs(@shape_options)}

  ## Examples

  Kerning moves "V" closer to "A", so "A" advances less than the font stores:

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> Pica.shape(font, "AV")
      [
        %Pica.Glyph{glyph_id: 3, cluster: 0, x_advance: 1246, nominal_advance: 1354, x_offset: 0, y_offset: 0},
        %Pica.Glyph{glyph_id: 40, cluster: 1, x_advance: 1354, nominal_advance: 1354, x_offset: 0, y_offset: 0}
      ]

  In "office", one glyph draws "ffi", so the next cluster is 4:

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> font |> Pica.shape("office") |> Enum.map(fn glyph -> {glyph.glyph_id, glyph.cluster} end)
      [{111, 0}, {76, 1}, {49, 4}, {59, 5}]

  Lato has no "★", so it is glyph 0, keeping its cluster:

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> font |> Pica.shape("A★V") |> Enum.map(fn glyph -> {glyph.glyph_id, glyph.cluster} end)
      [{3, 0}, {0, 1}, {40, 2}]

  Without kerning, "A" advances as the font stores it:

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> font |> Pica.shape("AV", features: [kern: false]) |> Enum.map(fn glyph -> glyph.x_advance end)
      [1354, 1354]
  """
  @spec shape(Font.t(), String.t(), keyword()) :: [Glyph.t()]
  def shape(font, text, options \\ []) when is_binary(text) do
    check_text!(text)
    options = NimbleOptions.validate!(options, @shape_options)

    font
    |> Font.resource()
    |> Native.shape(
      text,
      options[:features],
      options[:direction],
      options[:script],
      options[:language]
    )
    |> shaped!()
  end

  defp check_text!(text) do
    unless String.valid?(text) do
      raise ArgumentError, "expected text in UTF-8, got: #{inspect(text)}"
    end
  end

  defp check_glyph_ids!(font, glyph_ids) do
    glyph_count = Font.info(font).glyph_count

    case Enum.reject(glyph_ids, fn glyph_id -> is_glyph_id(glyph_id, glyph_count) end) do
      [] ->
        :ok

      [not_a_glyph_id | _rest] ->
        raise ArgumentError,
              "expected glyph ids from 0 to #{glyph_count - 1}, the font's glyph count less " <>
                "one, got: #{inspect(not_a_glyph_id)}"
    end
  end

  defp shaped!({:ok, glyphs}), do: glyphs

  defp shaped!({:error, {reason, detail}}) do
    raise ArgumentError, "cannot shape the text (#{reason}): #{detail}"
  end

  defp measured!({:ok, values}), do: values

  defp measured!({:error, {:malformed_glyph, glyph_id, detail}}) do
    raise ArgumentError, "cannot measure glyph #{glyph_id}: #{detail}"
  end

  defp measured!({:error, {:unreadable_font, detail}}) do
    raise ArgumentError, "cannot measure glyphs, since the font does not read: #{detail}"
  end
end
