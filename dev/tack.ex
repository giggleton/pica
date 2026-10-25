defmodule Tack do
  @moduledoc false

  # Development tooling copied from Tack (github.com/srowley/tack, commit 9ae74d8, MIT), the
  # harness Pica's gate is built on, so that the gate needs no access to Tack's private
  # repository. The modules keep Tack's names and code, so a later fix in Tack can be compared and
  # copied across by hand:
  #
  #   * `Tack.Credo.Check.*` — the credo checks `.credo.exs` enables, each a convention from
  #     `CLAUDE.md` made into a gate failure.
  #   * `Tack.RulesCheck` and `mix tack.rules_check` — the ratchets that keep `CLAUDE.md` from
  #     regrowing and the area rules' path globs from rotting.
  #   * `Tack.Quality` and `mix tack.quality` — the quality gate runner behind `mix quality`.
  #   * `Tack.BoundaryDeclarations` — the scanner behind the boundary declarations test.
  #
  # `dev/` is compiled in the dev and test environments only (`elixirc_paths` in `mix.exs`) and
  # is not in the Hex package, so none of this reaches a user of Pica.

  # Its own top-level boundary, outside `Pica`: it may call Credo and Mix, and exports nothing,
  # so no module of the library can call into it. The mix tasks are classified into it.
  use Boundary, deps: [Credo, Mix], exports: []
end
