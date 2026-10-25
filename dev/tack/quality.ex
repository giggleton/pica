defmodule Tack.Quality do
  @moduledoc """
  The decisions behind `mix tack.quality`, the runner the project's `mix quality` alias
  points at: which steps run, in what mode, and whether the toolchain can be trusted to run them.

  The steps themselves live in the project's `mix.exs`, under the `quality_steps` project key —
  one list, the single source of truth for both the local gate and CI. Each step is
  `{label, command}` or `{label, command, options}`; the one option is `skip_on_check: true`,
  which marks a step `--check` drops. Locally, formatting the tree *first* is the point: an
  unformatted file is fixed up front instead of failing at the end. In CI that same write would
  make the trailing `--check-formatted` step decorative — it would be checking work the first step
  had just done — so CI runs `mix quality --check`, the same list minus the write.

  Pure: this module reads no config and runs no command. `Mix.Tasks.Tack.Quality` owns the
  IO.
  """

  @typedoc "A step as `mix.exs` declares it."
  @type configured_step :: {String.t(), String.t()} | {String.t(), String.t(), keyword()}

  @typedoc "A step as the runner executes it."
  @type step :: {label :: String.t(), command :: String.t()}

  # `mix hex.audit` reports security advisories only from Hex 2.5 on; earlier Hex runs the task
  # happily, checks *retirements* alone, and exits 0. A gate step that can quietly stop checking is
  # worse than no step, so the runner refuses to run rather than under-report.
  @minimum_hex_version "2.5.0"

  @doc "The oldest Hex whose `mix hex.audit` reports security advisories."
  @spec minimum_hex_version() :: String.t()
  def minimum_hex_version, do: @minimum_hex_version

  @doc """
  The steps to run, in order, from the project's `quality_steps` configuration.

  With `check?` the steps marked `skip_on_check: true` are dropped. Returns an error naming the
  fix when the key is missing or a step is malformed, so a typo in `mix.exs` fails the gate loudly
  instead of silently running fewer steps.
  """
  @spec steps(term(), boolean()) :: {:ok, [step()]} | {:error, String.t()}
  def steps(nil, _check?) do
    {:error,
     "mix.exs declares no `quality_steps` project key. Add one — a list of " <>
       "{label, command} tuples, run in order — or re-run `mix tack.install`."}
  end

  def steps(configured, check?) when is_list(configured) do
    configured
    |> Enum.reduce_while({:ok, []}, fn step, {:ok, acc} ->
      case normalize(step) do
        {:ok, {label, command, options}} ->
          {:cont, {:ok, keep(acc, {label, command}, skip?(options, check?))}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
    |> in_order()
  end

  def steps(other, _check?) do
    {:error, "mix.exs's `quality_steps` must be a list; got #{inspect(other)}."}
  end

  @doc """
  Whether `installed` (a Hex version string, or `:none` when Hex is not on the code path) can run
  the `hex.audit` step. Returns the message to raise with when it cannot.
  """
  @spec hex_version_check(String.t() | :none) :: :ok | {:error, String.t()}
  def hex_version_check(:none) do
    {:error, "mix quality: Hex is not available. Run `mix local.hex --force`."}
  end

  def hex_version_check(installed) when is_binary(installed) do
    if Version.match?(installed, ">= #{@minimum_hex_version}") do
      :ok
    else
      {:error,
       "mix quality: Hex #{installed} is too old for the `hex.audit` step, which needs " <>
         "#{@minimum_hex_version} or newer to report security advisories (older Hex checks " <>
         "retirements only and exits 0, reporting nothing). Run `mix local.hex --force`."}
    end
  end

  defp skip?(options, check?), do: check? and Keyword.get(options, :skip_on_check, false)

  defp keep(acc, _step, true), do: acc
  defp keep(acc, step, false), do: [step | acc]

  defp in_order({:ok, reversed}), do: {:ok, Enum.reverse(reversed)}
  defp in_order(error), do: error

  defp normalize({label, command}) when is_binary(label) and is_binary(command),
    do: {:ok, {label, command, []}}

  defp normalize({label, command, options})
       when is_binary(label) and is_binary(command) and is_list(options),
       do: {:ok, {label, command, options}}

  defp normalize(other) do
    {:error,
     "mix.exs's `quality_steps` has a malformed entry: #{inspect(other)}. Each step is " <>
       "{label, command} or {label, command, skip_on_check: true}."}
  end
end
