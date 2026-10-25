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
end
