defmodule Pica.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/giggleton/pica"
  @crate_manifest "native/pica/Cargo.toml"

  def project do
    [
      app: :pica,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:boundary] ++ Mix.compilers(),
      # Every boundary is strict: a boundary's `deps:` list is the whole of what it may call,
      # outside libraries included, and a boundary inherits nothing from its parent.
      boundary: [default: [type: :strict]],
      quality_steps: [
        {"format (write)", "mix format", skip_on_check: true},
        {"cargo fmt (write)", "cargo fmt --manifest-path #{@crate_manifest}",
         skip_on_check: true},
        {"hex.audit", "mix hex.audit"},
        {"deps (unused)", "mix deps.unlock --check-unused"},
        {"compile (:dev)", "mix compile --warnings-as-errors"},
        {"compile (:test)", "MIX_ENV=test mix compile --warnings-as-errors"},
        {"cargo clippy",
         "cargo clippy --manifest-path #{@crate_manifest} --all-targets -- -D warnings"},
        {"cargo test", "cargo test --manifest-path #{@crate_manifest}"},
        {"test", "mix test --warnings-as-errors"},
        {"format", "mix format --check-formatted"},
        {"cargo fmt", "cargo fmt --manifest-path #{@crate_manifest} --check"},
        {"credo", "mix credo --strict"},
        {"rules", "mix tack.rules_check"}
      ],
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      # Expected values the tests read, written as Elixir terms; not test files.
      test_ignore_filters: [~r"^test/fixtures/"],
      description: "Text shaping and font metrics for Elixir, through HarfBuzz's Rust port.",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:rustler_precompiled, "~> 0.10.1"},
      {:rustler, "~> 0.38.0", optional: true},
      {:nimble_options, "~> 1.1"},
      {:boundary, "~> 0.11", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.6", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev], runtime: false},
      {:benchee, "~> 1.5", only: [:dev], runtime: false}
    ]
  end

  defp aliases() do
    [quality: ["tack.quality"]]
  end

  # `dev/` holds the gate's tooling, copied from Tack (`dev/tack.ex`): compiled for the dev and
  # test environments, never for a user's build, and left out of the package.
  defp elixirc_paths(:test) do
    ["lib", "dev", "test/support"]
  end

  defp elixirc_paths(:dev) do
    ["lib", "dev"]
  end

  defp elixirc_paths(_environment) do
    ["lib"]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: [
        "lib",
        "native/pica/src",
        "native/pica/Cargo.toml",
        "native/pica/Cargo.lock",
        "native/pica/.cargo",
        "checksum-Elixir.Pica.Native.exs",
        "mix.exs",
        "README.md",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md"
      ]
    ]
  end

  defp docs do
    [
      main: "Pica",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/registering-fonts.md",
        "guides/units.md",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md"
      ],
      groups_for_extras: [Guides: ~r"guides/"]
    ]
  end
end
