defmodule Pica.Native do
  @moduledoc false

  # The NIF stubs for the Rust crate in `native/pica`. `RustlerPrecompiled` downloads a prebuilt
  # binary for the platform from the GitHub release named by the version and checks it against
  # `checksum-Elixir.Pica.Native.exs`; it builds from source instead when the version is a `-dev`
  # pre-release or `PICA_BUILD` is `1` or `true`, which needs Rust and the optional `rustler`
  # dependency. Each stub raises until the library is loaded, which replaces it with the NIF.
  #
  # A source build compiles the crate in release mode and copies the library to `priv/native/`,
  # which git ignores. The crate is standalone, with no Cargo workspace, so its `Cargo.lock` sits
  # beside its `Cargo.toml`, where `rustler-precompiled-action` and a source build from Hex expect
  # it.

  # `use RustlerPrecompiled` runs at compile time only: it reads the project's version, picks a
  # binary or builds one with Rustler, and leaves an `@on_load` hook that loads it.
  use Boundary,
    deps: [{Mix, :compile}, {Rustler, :compile}, {RustlerPrecompiled, :compile}],
    exports: []

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :pica,
    crate: "pica",
    base_url: "https://github.com/giggleton/pica/releases/download/v#{version}",
    force_build: System.get_env("PICA_BUILD") in ["1", "true"],
    version: version,
    nif_versions: ["2.15"]

  @doc false
  # The Rust crate's version, so a test can show that the NIF loaded.
  @spec crate_version() :: String.t()
  def crate_version, do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  # Loads the font at `index` from a font file's bytes: `{:ok, {resource, info}}`, with `info` as
  # `Pica.info/1` describes it but for absent values, which arrive as `nil`; or
  # `{:error, reason}`, as `Pica.load_error/0` describes. Runs on a dirty scheduler.
  @spec load(binary(), non_neg_integer()) :: {:ok, {reference(), map()}} | {:error, term()}
  def load(_bytes, _index), do: :erlang.nif_error(:nif_not_loaded)

  # The glyph measurements below answer `{:ok, list}`, or `{:error, reason}`, the reason being
  # `{:malformed_glyph, glyph_id, detail}` for a glyph whose data does not read, or
  # `{:unreadable_font, detail}`, which load's checks leave unexpected. They take glyph ids the
  # caller has checked against the font's glyph count.

  @doc false
  # The glyph each character of `text`, valid UTF-8, maps to through the font's character map, 0
  # for a character the font lacks.
  @spec glyph_ids(reference(), String.t()) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def glyph_ids(_resource, _text), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  # Each glyph's advance width as the font's `hmtx` table gives it.
  @spec nominal_advances(reference(), [non_neg_integer()]) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  def nominal_advances(_resource, _glyph_ids), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  # Each glyph's control box as `{x_min, y_min, x_max, y_max}`, or `:none` for a glyph with no
  # outline.
  @spec glyph_boxes(reference(), [non_neg_integer()]) ::
          {:ok, [{integer(), integer(), integer(), integer()} | :none]} | {:error, term()}
  def glyph_boxes(_resource, _glyph_ids), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  # Shapes `text`, valid UTF-8, into `%Pica.Glyph{}` structs, applying `features` (`{tag, value}`,
  # the tag four bytes) to the whole text, with the direction, script and language given, or
  # guessed (direction, script) or left unset (language) where `nil`. Answers `{:ok, glyphs}`, or
  # `{:error, reason}` for what the caller's checks and harfrust's leave unexpected:
  # `{:invalid_setting, detail}` or `{:shaping_failed, detail}`.
  @spec shape(
          reference(),
          String.t(),
          [{String.t(), non_neg_integer()}],
          :left_to_right | :right_to_left | nil,
          String.t() | nil,
          String.t() | nil
        ) :: {:ok, [Pica.Glyph.t()]} | {:error, term()}
  def shape(_resource, _text, _features, _direction, _script, _language),
    do: :erlang.nif_error(:nif_not_loaded)
end
