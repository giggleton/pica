defmodule Pica.BoundaryDeclarationsTest do
  # Pins the architecture's weakening surface.
  #
  # Boundary declarations fail in one direction only. Too narrow fails loudly; too wide compiles in
  # silence. Every way to make the compiler enforce less is either absent from the tree or named in
  # `@sanctioned` with its reason, so widening costs an edit here, in the same diff — a visible act
  # rather than a quiet one. `Tack.BoundaryDeclarations` is the scanner; the harness tests
  # it against fabricated declarations, so this file reads only the real tree.
  use ExUnit.Case, async: true

  alias Tack.BoundaryDeclarations

  # The accepted exceptions, each with the reason it was accepted. A new entry is the decision;
  # this test failing is the prompt to make it deliberately.
  @sanctioned %{}

  @umbrella "lib/pica.ex"

  # The compiled source a declaration can sit in: the library, and the gate's tooling copied from
  # Tack, which is compiled too and could weaken the compiler as quietly. Test support is read by
  # the test that needs it.
  @declared_roots ["lib", "dev"]

  test "no declaration disables a check except where sanctioned, with a stated reason" do
    unsanctioned =
      for root <- @declared_roots,
          path <- BoundaryDeclarations.source_files(root),
          {token, effect} <- BoundaryDeclarations.disabled_checks_in(path),
          not Map.has_key?(@sanctioned, {path, token}),
          do: "  #{path}: #{token} — #{effect}"

    assert unsanctioned == [],
           """
           A boundary declaration disables a compiler check without being sanctioned.

           #{Enum.join(unsanctioned, "\n")}

           This is the one kind of change nothing else will catch: it compiles clean and
           enforces less. If the exemption is right, add it to @sanctioned in this file with
           the reason — that edit is the decision, and it belongs in the same diff.
           """
  end

  test "every sanctioned exemption still exists, so the list cannot rot" do
    stale =
      for {{path, token}, _reason} <- @sanctioned,
          not sanctioned_exemption_present?(path, token),
          do: {path, token}

    assert stale == [],
           "@sanctioned names exemptions no longer in the tree: #{inspect(stale)}. Remove " <>
             "them — a standing exemption for code that no longer exists is permission " <>
             "waiting to be reused without a decision."
  end

  test "only the umbrella uses exports: :all" do
    offenders =
      for root <- @declared_roots,
          path <- BoundaryDeclarations.source_files(root),
          path != @umbrella,
          BoundaryDeclarations.exports_all_in?(path),
          do: path

    assert offenders == [],
           "exports: :all outside the umbrella: #{inspect(offenders)}. On a sub-boundary the " <>
             "export list is an approval gate: an explicit list fails safe (a new module is " <>
             "private until a person admits it) while :all makes it public the moment it " <>
             "compiles. List the exported modules instead (.claude/rules/dependencies.md)."
  end

  test "every boundary stays strict by default" do
    # The loaded config, which is what boundary reads: a pattern over mix.exs's text would still
    # match the line commented out.
    assert get_in(Mix.Project.config(), [:boundary, :default, :type]) == :strict,
           "mix.exs no longer makes every boundary strict. Without that default a boundary's " <>
             "`deps:` stops being the whole of what it may call: it inherits its parent's " <>
             "list and may call any outside library it does not name, and nothing reports it."
  end

  test "no declaration relaxes the strict default" do
    relaxed =
      for root <- ["test/support" | @declared_roots],
          path <- BoundaryDeclarations.source_files(root),
          declaration <- BoundaryDeclarations.declarations_in(path),
          declaration =~ ~r/type:\s*:relaxed/,
          do: path

    assert relaxed == [],
           "A boundary declaration sets `type: :relaxed`, opting out of the strict default: " <>
             "#{inspect(relaxed)}. Its `deps:` no longer bounds what it may call. If that is " <>
             "the intent, it is a decision for the user, made in this file."
  end

  test "every implementation of Pica's own protocols is classified into its protocol's boundary" do
    # Boundary checks nothing a protocol implementation calls until the implementation is
    # classified, so an unclassified `defimpl` compiles clean with every call it makes unchecked.
    # An implementation of a protocol from outside Pica has no protocol boundary to be classified
    # into, and is left out.
    {:ok, modules} = :application.get_key(:pica, :modules)

    implementations =
      Enum.filter(modules, fn module ->
        Code.ensure_loaded?(module) and function_exported?(module, :__impl__, 1) and
          module.__impl__(:protocol) in modules
      end)

    # Pica defines no protocol yet, so the list is empty. When the first one lands, assert that
    # it is not, so that a broken search cannot pass as every implementation classified.

    unclassified =
      for module <- implementations,
          protocol = module.__impl__(:protocol),
          classified_to(module) != protocol,
          do:
            "  #{inspect(module)}: classify it with `use Boundary, classify_to: #{inspect(protocol)}`"

    assert unclassified == [],
           """
           A protocol implementation is not classified into its protocol's boundary, so boundary
           checks none of the calls it makes.

           #{Enum.join(unclassified, "\n")}

           Make that declaration the first line of the `defimpl`.
           """
  end

  test "the boundary compiler is wired into the project" do
    assert BoundaryDeclarations.compiler_configured_in?("mix.exs"),
           "mix.exs no longer runs the boundary compiler, so every declaration in lib/ is " <>
             "inert and the architecture is unenforced. This is the single largest bypass " <>
             "and the cheapest to make by accident."
  end

  # The boundary a module's `use Boundary, classify_to: …` puts it in, which boundary keeps in the
  # module's attributes; `nil` for a module with no such declaration.
  defp classified_to(module) do
    attributes = module.__info__(:attributes)

    case Keyword.get(attributes, Boundary) do
      [%{opts: options}] -> Keyword.get(options, :classify_to)
      nil -> nil
    end
  end

  defp sanctioned_exemption_present?(path, token) do
    File.exists?(path) and
      path
      |> BoundaryDeclarations.disabled_checks_in()
      |> Enum.any?(fn {found, _effect} -> found == token end)
  end
end
