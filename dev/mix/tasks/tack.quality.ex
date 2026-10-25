defmodule Mix.Tasks.Tack.Quality do
  @shortdoc "Runs the quality gate: every step in mix.exs's quality_steps, stopping at the first failure"

  @moduledoc """
  The pre-commit quality gate, run as one command — the project's `mix quality` alias.

      mix quality            # locally: every step, formatting the tree first
      mix quality --check    # CI: the same steps minus the formatting write

  Each step is its own `mix` subprocess with an explicit `MIX_ENV` where it needs one, so the env
  never flips mid-gate (`mix test` builds in `:test`, the rest in `:dev` — separate `_build` dirs,
  warmed by the compile steps first). It **stops at the first failing step** and exits non-zero,
  so the failing step's output is the last thing printed and a `❌ … FAILED` banner is the final
  line — legible even if the run is (wrongly) piped through `tail`.

  **Run it bare — never pipe it through `tail`, `head` or `grep`.** A pipe hides the failing
  step's output and, worse, makes the shell report the *pipe's* exit status (`0`), masking the
  gate's non-zero failure. To iterate on one check, run that single `mix` task directly.

  The steps come from the `quality_steps` project key in `mix.exs`; see `Tack.Quality` for
  the shape, and the project's `CLAUDE.md` for what each step is for.
  """

  use Mix.Task

  use Boundary, classify_to: Tack
  alias Tack.Quality

  @impl Mix.Task
  def run(args) do
    assert_hex_version!()
    steps = steps!(args)

    outcome =
      Enum.reduce_while(steps, :ok, fn {label, command}, _accumulator ->
        Mix.shell().info("\n==> mix quality: #{label}  (#{command})")

        case Mix.shell().cmd(command) do
          0 -> {:cont, :ok}
          status -> {:halt, {:failed, label, command, status}}
        end
      end)

    case outcome do
      :ok ->
        Mix.shell().info("\n✅ mix quality: all steps passed.")

      {:failed, label, command, status} ->
        Mix.shell().error("\n❌ mix quality FAILED at step: #{label}")
        Mix.shell().error("   command: #{command}  (exit #{status})")

        Mix.shell().error(
          "   Fix the output ABOVE, then re-run `mix quality` bare (do not pipe through tail)."
        )

        Mix.raise("mix quality failed at: #{label}")
    end
  end

  defp steps!(args) do
    case Quality.steps(Mix.Project.config()[:quality_steps], "--check" in args) do
      {:ok, steps} -> steps
      {:error, message} -> Mix.raise(message)
    end
  end

  # Runs before the first step, so a too-old Hex fails the gate immediately instead of after the
  # whole suite. Asked via `Hex.version/0` rather than `Application.spec(:hex, :vsn)`: Hex is an
  # *archive*, so Mix puts it on the code path at boot but never loads it as an application, and
  # the `spec` answer is always `nil` — which would fail the gate on every machine.
  defp assert_hex_version! do
    installed =
      if Code.ensure_loaded?(Hex) and function_exported?(Hex, :version, 0) do
        # why: `Hex` is an archive, not a dependency, so a direct `Hex.version()` is an
        #   undefined-module warning under `--warnings-as-errors`; `apply/3` keeps the call dynamic.
        # instead of: `Application.spec(:hex, :vsn)` — rejected because Mix never loads Hex as an
        #   application, so it answers `nil` on every machine.
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Hex, :version, [])
      else
        :none
      end

    case Quality.hex_version_check(installed) do
      :ok -> :ok
      {:error, message} -> Mix.raise(message)
    end
  end
end
