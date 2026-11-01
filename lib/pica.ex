defmodule Pica do
  @moduledoc """
  Text shaping and font metrics for Elixir, through HarfBuzz's Rust port.

  Pica measures text from font files. A caller registers loaded fonts under a family name, then
  asks, by family and face, for each string's glyphs: which glyph, which characters it came from,
  how far it advances once kerning, ligatures and contextual forms are applied, and how far it
  would advance unshaped. It also reports font-wide metrics, glyph bounding boxes, and glyph
  outlines as drawing commands. Nothing is rendered.

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

  ## Fonts by name

  A family's faces are its regular (`:plain`), bold, italic and bold italic fonts. `register/2`
  files loaded fonts as a family's faces under a name, and `lookup/3` finds a face by that name
  from anywhere in the application. Registered fonts are kept in `:persistent_term`, so reading
  them costs nothing, but registering a family again, or unregistering one, makes every process
  in the VM garbage collect: register fonts once, when the application starts.

  A face the registered fonts lack is looked for among the machine's installed fonts, unless the
  lookup passes `installed: false`. An installed font is a face of a family when one of its
  family names (the typographic family name, else the family name, in any language the font
  gives) is exactly the name asked for, and the nearest of its kind is chosen: for `:plain`, the
  upright font whose weight is nearest 400 below 600 (semibold); for `:bold`, the upright font
  whose weight is nearest 700 at 600 or above; for `:italic` and `:bold_italic`, the same among
  italic or oblique fonts. A tie goes to the heavier weight, then to the width nearest normal.
  A family with no font of the kind asked for has no such face, so the lookup is `:error`: an
  upright font never stands in for an italic, nor a regular for a bold. A variable font is
  measured at its default instance.

  ## Glyphs

  A font draws text with glyphs: shapes numbered by glyph id, from 0 to one less than the font's
  `glyph_count`. Glyph 0 is `.notdef`, the shape a font draws for a character it lacks. The
  font's character map ties each character to a glyph, which `glyph_ids/2` reads, though shaping
  may then replace glyphs, joining "f" and "i" into one, say.

  `nominal_advances/2` gives how far each glyph moves the pen on, as the font stores it, before
  shaping adjusts it for kerning or context. `glyph_boxes/2` gives the box around each glyph's
  outline, and `glyph_outlines/2` the outline itself, as the commands that draw it. All three
  measure at the font's default location: a variable font, which can vary its weight or width, is
  measured as it is drawn when no variation is chosen.

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
  location, in font units unless a `:scale` is given.

  ## Scale

  Font units depend on no size, but turning them into a size rounds them, and where the rounding
  happens changes the total. With `:scale`, shaping itself positions each glyph at the scale and
  rounds it as HarfBuzz does, so a sum of advances is the one a HarfBuzz-based renderer gets at
  that size. A scale is the em divided into that many units: at 12 points, `scale: 12 * 64` puts
  every length in 1/64 point.

  The rounding is HarfBuzz's own. A renderer whose HarfBuzz takes each glyph's advance from
  FreeType instead rounds by FreeType's arithmetic, so its advances can differ from Pica's by a
  unit on some glyphs; Pica does not imitate it.
  """

  # The root boundary. It lists every outside library a sub-boundary does, since a sub-boundary
  # may list only what its parent lists (`.claude/rules/dependencies.md`); Rustler only when it is
  # loaded, as `Pica.Native` explains.
  use Boundary,
    deps:
      [NimbleOptions, {Mix, :compile}, {RustlerPrecompiled, :compile}] ++
        if(Code.ensure_loaded?(Rustler), do: [{Rustler, :compile}], else: []),
    exports: []

  alias Pica.{Font, Fonts, Glyph, Native}

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

  @typedoc """
  A glyph's outline, in font units: the commands that draw it, in order, measured from the point
  where the glyph is drawn, on the baseline, with y rising upward.

  Each contour, a closed loop of the outline, begins with a `:move` to its start and ends with
  `:close`, which draws the line back to the start; no `:line` to the start comes before it. In
  between, `:line` draws a straight line to its point, `:quad` a quadratic curve steered by one
  control point, and `:cubic` a cubic curve steered by two (see `t:outline_command/0`). A
  TrueType curve that runs through several control points arrives as one `:quad` per control
  point, split at the points on the curve that lie halfway between them.

  A contour whose first point is off the curve starts at its last point, or halfway between its
  last and first when both are off the curve, as FreeType starts it. Coordinates are floats: a
  TrueType glyph's are whole font units, a glyph built from a scaled copy of another having each
  point rounded to the nearest unit, and a CFF glyph's can fall between units.
  """
  @type glyph_outline :: [outline_command()]

  @typedoc """
  One command of a `t:glyph_outline/0`: `{:move, x, y}`, `{:line, x, y}`,
  `{:quad, control_x, control_y, x, y}`,
  `{:cubic, first_control_x, first_control_y, second_control_x, second_control_y, x, y}`, or
  `:close`.
  """
  @type outline_command ::
          {:move, float(), float()}
          | {:line, float(), float()}
          | {:quad, float(), float(), float(), float()}
          | {:cubic, float(), float(), float(), float(), float(), float()}
          | :close

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
                   ],
                   scale: [
                     type: {:in, 1..2_147_483_647},
                     type_doc: "`t:pos_integer/0`",
                     doc: """
                     How many units the em, the font size, is divided into, in place of the
                     font's own units per em: every advance and offset comes back in these units,
                     each glyph's rounded to a whole unit as HarfBuzz rounds it. At 12 points,
                     `scale: 12 * 64` gives 1/64 point. Font units when not given.
                     """
                   ]
                 )

  @long_text_bytes 1000

  @many_glyphs 64

  @face_options NimbleOptions.new!(
                  for face <- [:plain, :bold, :italic, :bold_italic] do
                    {face, [type: {:struct, Font}, doc: "The #{face} face, a loaded font."]}
                  end
                )

  @lookup_options NimbleOptions.new!(
                    installed: [
                      type: :boolean,
                      default: true,
                      doc: """
                      Whether to look among the machine's installed fonts for a face the
                      registered fonts lack.
                      """
                    ]
                  )

  @typedoc "A face of a family: its regular, bold, italic or bold italic font."
  @type face :: :plain | :bold | :italic | :bold_italic

  defguardp is_face(face) when face in [:plain, :bold, :italic, :bold_italic]

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
    Font.load(bytes, options[:index])
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
  Registers loaded fonts as the faces of `family`, so `lookup/3` finds them by name.

  The name is the caller's: it need not be the font's own family name. Registering a family again
  replaces it whole, so a face given before and not now is no longer registered. Fonts are meant
  to be registered once, when the application starts: registering again or unregistering is
  costly for the whole VM (see "Fonts by name" above). Raises `NimbleOptions.ValidationError` for
  a face that is not a loaded font, and `ArgumentError` when no face is given.

  ## Faces

  #{NimbleOptions.docs(@face_options)}

  ## Examples

      iex> {:ok, regular} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> {:ok, bold} = Pica.load(File.read!("test/fonts/Lato-Bold.ttf"))
      iex> Pica.register("Lato for the register example", plain: regular, bold: bold)
      :ok
      iex> Pica.registered?("Lato for the register example")
      true
  """
  @spec register(String.t(), [{face(), Font.t()}]) :: :ok
  def register(family, faces) when is_binary(family) and is_list(faces) do
    faces = NimbleOptions.validate!(faces, @face_options)

    if faces == [] do
      raise ArgumentError, "expected at least one face to register #{inspect(family)} with"
    end

    Fonts.register(family, Map.new(faces))
  end

  @doc """
  Forgets a registered family. Returns `:ok` whether or not it was registered.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(family) when is_binary(family), do: Fonts.unregister(family)

  @doc """
  Whether `family` is registered. Installed fonts are not registered.
  """
  @spec registered?(String.t()) :: boolean()
  def registered?(family) when is_binary(family), do: Fonts.registered?(family)

  @doc """
  The names of the registered families, sorted.
  """
  @spec families() :: [String.t()]
  def families, do: Fonts.families()

  @doc """
  Finds a face of `family` by name: `{:ok, font}`, or `:error` when the face is found nowhere.

  The face, `:plain` unless given, comes from the fonts registered under `family` first. When
  they lack it, the machine's installed fonts are searched, unless `installed: false`: for an
  installed font whose family name is exactly `family`, of the face asked for, as "Fonts by name"
  above describes. A missing face is never answered with another: a registered plain face does
  not stand in for a missing bold. The face may be left out while options are given, as in
  `lookup("Lato", installed: false)`.

  The first search of the installed fonts reads every font file on the machine, which can take a
  second or more; its result is kept for the life of the VM, so fonts installed afterwards are
  not seen.

  ## Options

  #{NimbleOptions.docs(@lookup_options)}

  ## Examples

      iex> {:ok, regular} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> Pica.register("Lato for the lookup example", plain: regular)
      iex> {:ok, font} = Pica.lookup("Lato for the lookup example")
      iex> Pica.info(font).subfamily
      "Regular"
      iex> Pica.lookup("Lato for the lookup example", :bold, installed: false)
      :error
  """
  @spec lookup(String.t(), face() | keyword(), keyword()) :: {:ok, Font.t()} | :error
  def lookup(family, face \\ :plain, options \\ [])

  def lookup(family, options, []) when is_binary(family) and is_list(options) do
    lookup(family, :plain, options)
  end

  def lookup(family, face, options) when is_binary(family) and is_face(face) do
    options = NimbleOptions.validate!(options, @lookup_options)
    Fonts.lookup(family, face, options[:installed])
  end

  def lookup(family, not_a_face, _options) when is_binary(family) do
    raise ArgumentError,
          "expected a face, :plain, :bold, :italic or :bold_italic, got: #{inspect(not_a_face)}"
  end

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
  does not read. More than 64 glyphs are measured on a dirty scheduler, so a whole font's boxes
  never hold up the processes around it.

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
    |> measure_on_scheduler(glyph_ids, &Native.glyph_boxes/2, &Native.glyph_boxes_many_glyphs/2)
    |> measured!()
  end

  @doc """
  Each glyph's outline (see `t:glyph_outline/0`), or `:none` for a glyph that draws nothing,
  such as a space, and for every glyph of a font with no outlines.

  Outlines are drawn at the font's default location, unscaled and unhinted: the font's own
  points, never adjusted to a pixel grid.

  Raises `ArgumentError` for a glyph id the font does not have, or for a glyph whose outline
  does not read. More than 64 glyphs are drawn on a dirty scheduler, so a whole font's outlines
  never hold up the processes around it.

  ## Examples

  Lato draws "I" as one rectangle:

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> Pica.glyph_outlines(font, Pica.glyph_ids(font, "I "))
      [
        [{:move, 377.0, 0.0}, {:line, 183.0, 0.0}, {:line, 183.0, 1433.0}, {:line, 377.0, 1433.0}, :close],
        :none
      ]
  """
  @spec glyph_outlines(Font.t(), [non_neg_integer()]) :: [glyph_outline() | :none]
  def glyph_outlines(font, glyph_ids) when is_list(glyph_ids) do
    check_glyph_ids!(font, glyph_ids)

    font
    |> Font.resource()
    |> measure_on_scheduler(
      glyph_ids,
      &Native.glyph_outlines/2,
      &Native.glyph_outlines_many_glyphs/2
    )
    |> measured!()
  end

  # Boxing and drawing cost up to about 5 and 6 microseconds a glyph, so more than @many_glyphs
  # would hold a normal scheduler for over a quarter of a millisecond; they go to the dirty
  # scheduler's name for the measure, which costs a switch, a few microseconds, that a label's
  # glyphs never pay.
  defp measure_on_scheduler(resource, glyph_ids, normal_measure, _dirty_measure)
       when length(glyph_ids) <= @many_glyphs do
    normal_measure.(resource, glyph_ids)
  end

  defp measure_on_scheduler(resource, glyph_ids, _normal_measure, dirty_measure) do
    dirty_measure.(resource, glyph_ids)
  end

  @doc """
  Shapes `text` into the glyphs `font` draws it with (see `Pica.Glyph`), in the order they are
  drawn, from left to right, with every length in font units, or at the `:scale` given.

  HarfBuzz's default features for the text's script are on, and its direction and script are
  guessed from the text; the options override them. A character the font lacks shapes to glyph
  0, `.notdef`, with its cluster; Pica never draws it from another font. A character Unicode
  marks as default-ignorable, one meant never to be drawn, such as a soft hyphen (U+00AD) or a
  zero-width joiner (U+200D), is hidden as HarfBuzz hides it, whether or not the font has it: it
  shapes to the font's space glyph with an `x_advance` of 0, or, in a font with no space, to no
  glyph at all. Raises `ArgumentError` for text that is not valid UTF-8, and
  `NimbleOptions.ValidationError` for an option not of its form. Text longer than 1,000 bytes is
  shaped on a dirty scheduler, so a long text never holds up the processes around it.

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

  At 12 points in 1/64 point, "AV" is 999/64 point wide, each glyph rounded as HarfBuzz rounds it:

      iex> {:ok, font} = Pica.load(File.read!("test/fonts/Lato-Regular.ttf"))
      iex> font |> Pica.shape("AV", scale: 12 * 64) |> Enum.map(fn glyph -> glyph.x_advance end)
      [479, 520]
  """
  @spec shape(Font.t(), String.t(), keyword()) :: [Glyph.t()]
  def shape(font, text, options \\ []) when is_binary(text) do
    check_text!(text)
    options = NimbleOptions.validate!(options, @shape_options)

    font
    |> Font.resource()
    |> shape_on_scheduler(text, options)
    |> shaped!()
  end

  # Shaping costs about half a microsecond a character, so text past @long_text_bytes would hold
  # a normal scheduler for over half a millisecond; it goes to a dirty one, which costs a switch,
  # a few microseconds, that labels never pay.
  defp shape_on_scheduler(resource, text, options) when byte_size(text) <= @long_text_bytes do
    Native.shape(
      resource,
      text,
      options[:features],
      options[:direction],
      options[:script],
      options[:language],
      options[:scale]
    )
  end

  defp shape_on_scheduler(resource, text, options) do
    Native.shape_long_text(
      resource,
      text,
      options[:features],
      options[:direction],
      options[:script],
      options[:language],
      options[:scale]
    )
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
