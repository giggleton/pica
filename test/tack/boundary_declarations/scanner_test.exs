defmodule Tack.BoundaryDeclarations.ScannerTest do
  # Proves the scanner reads declarations the way a reviewer would: whole, however `mix format`
  # wrapped them, and never prose that quotes one. The generated per-project test points it at a
  # real tree.
  use ExUnit.Case, async: true

  alias Tack.BoundaryDeclarations

  describe "declarations/1" do
    test "reads a single-line declaration" do
      source = "defmodule Example do\n  use Boundary, deps: [Other], exports: [Thing]\nend\n"

      assert BoundaryDeclarations.declarations(source) == [
               "use Boundary, deps: [Other], exports: [Thing]"
             ]
    end

    test "reads a multi-line declaration whole" do
      source = """
      defmodule Example do
        use Boundary,
          deps: [Other],
          exports: [Thing]
      end
      """

      assert BoundaryDeclarations.declarations(source) == [
               "use Boundary, deps: [Other], exports: [Thing]"
             ]
    end

    # The umbrella's shape once its `except:` list outgrows the line: `mix format` leaves
    # `exports:` alone on a line with the value below. That line's brackets balance and it ends in
    # no comma, so a comma-only rule closes the declaration there and reads "use Boundary,
    # exports:" — and an escape hatch written after the value goes unseen.
    test "reads a key alone on its line, the value below, and the options after it" do
      source = """
      defmodule Example do
        use Boundary,
          exports:
            {:all,
             except: [
               Repo,
               Internal
             ]},
          dirty_xrefs: [Something]
      end
      """

      assert BoundaryDeclarations.declarations(source) == [
               "use Boundary, exports: {:all, except: [ Repo, Internal ]}, dirty_xrefs: [Something]"
             ]

      assert [{"dirty_xrefs:", _effect}] = BoundaryDeclarations.disabled_checks(source)
    end

    # The mutant this kills: a moduledoc explaining why a module may never say `exports: :all`,
    # and a test module quoting every option it forbids. A scanner matching anywhere in the file
    # scores both as maximal grants.
    test "ignores prose and comments that quote a declaration" do
      source = ~S'''
      defmodule Example do
        @moduledoc """
        Never write `use Boundary, exports: :all` here, and never `check: [in: false]`.
        """

        # use Boundary, dirty_xrefs: [Something]
        use Boundary, deps: [Other]
      end
      '''

      assert BoundaryDeclarations.declarations(source) == ["use Boundary, deps: [Other]"]
      assert BoundaryDeclarations.disabled_checks(source) == []
      refute BoundaryDeclarations.exports_all?(source)
    end

    # The installer's own file: whole declarations sit inside template heredocs, on lines that start
    # with `use Boundary`. The scanner must not read a quoted declaration as a live one.
    test "a declaration quoted inside a heredoc is not read as one" do
      source = ~S'''
      defmodule Example do
        use Boundary, deps: [Other]

        def template do
          """
          use Boundary, top_level?: true, deps: [App]
          use Boundary, exports: :all
          """
        end
      end
      '''

      assert BoundaryDeclarations.declarations(source) == ["use Boundary, deps: [Other]"]
      assert BoundaryDeclarations.disabled_checks(source) == []
      refute BoundaryDeclarations.exports_all?(source)
    end

    test "a module with no declaration yields none" do
      assert BoundaryDeclarations.declarations("defmodule Plain do\nend\n") == []
    end
  end

  describe "disabled_checks/1" do
    test "names each option that switches a check off" do
      source = "defmodule Example do\n  use Boundary, check: [in: false], top_level?: true\nend\n"

      tokens =
        source
        |> BoundaryDeclarations.disabled_checks()
        |> Enum.map(fn {token, _effect} -> token end)

      assert "check: [in: false]" in tokens
      assert "top_level?:" in tokens
    end

    test "an ordinary declaration disables nothing" do
      source = "defmodule Example do\n  use Boundary, deps: [Other], exports: [Thing]\nend\n"
      assert BoundaryDeclarations.disabled_checks(source) == []
    end
  end

  describe "strict?/1" do
    test "the type is read from the declaration, not from prose about it" do
      declared = "defmodule Example do\n  use Boundary, type: :strict, deps: []\nend\n"

      described = ~S'''
      defmodule Example do
        @moduledoc """
        This boundary is deliberately not `type: :strict`.
        """
        use Boundary, deps: []
      end
      '''

      assert BoundaryDeclarations.strict?(declared)
      refute BoundaryDeclarations.strict?(described)
    end
  end

  describe "exports_all?/1" do
    test "a bare :all counts, and an excepting form does not" do
      bare = "defmodule Example do\n  use Boundary, exports: :all\nend\n"
      excepting = "defmodule Example do\n  use Boundary, exports: {:all, except: [Repo]}\nend\n"

      assert BoundaryDeclarations.exports_all?(bare)
      refute BoundaryDeclarations.exports_all?(excepting)
    end
  end

  describe "compiler_configured?/1" do
    test "a real setting counts" do
      assert BoundaryDeclarations.compiler_configured?("      compilers: [:boundary] ++ x,\n")
    end

    # The mutant this kills: a mix.exs that describes `compilers: [:boundary]` in the comment
    # above the dependency, so a bare substring check passes on the prose after the setting is
    # deleted.
    test "a comment describing the setting does not" do
      refute BoundaryDeclarations.compiler_configured?(
               "  # `compilers: [:boundary]` enforces it\n"
             )
    end
  end
end
