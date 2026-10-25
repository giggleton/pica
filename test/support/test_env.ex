defmodule PicaTest.TestEnv do
  @moduledoc """
  Overriding `:pica` application config for the rest of one test, and putting it back.

  Application env is one table for the whole VM, outside any database sandbox, so a test that
  changes it owes the suite two things. It must put the old value back, and that is easy to get
  subtly wrong: a key that was **unset** has no old value, and restoring the `nil` that
  `Application.get_env/2` handed back leaves the key *present* with a `nil` in it — which a boolean
  accessor reads as `false` by luck and a `Keyword.get/2` on a module-keyed entry reads as a crash.
  Each function here records the entry with `Application.fetch_env/2`, so "was unset" is remembered
  as such, and its `on_exit/1` either restores the old value or deletes the key.

  And it must run in a **sync** file. ExUnit runs every `async: true` module first and the sync ones
  after, one at a time, and the suite leans on that: an async test may read config because only sync
  files change it. These helpers do nothing to make a change safe under async — nothing could, since
  the table is global — and `Tack.Credo.Check.AsyncEnvMutation` fails the gate on a call to
  any of them, or to `Application.put_env/3` itself, in an `async: true` file.

  Plain functions over `ExUnit.Callbacks.on_exit/1`, so they work from any case template, in a `test`
  body or a `setup` block:

      alias PicaTest.TestEnv

      setup do
        TestEnv.put_app_env(:feature_enabled, true)
        TestEnv.merge_app_env(Pica.SomeClient, base_url: "http://localhost:4040")
        :ok
      end

  Several overrides of one key in one test unwind correctly: `on_exit/1` callbacks run last-first,
  so each restores the value the one before it recorded, and the last to run puts back the original.
  """

  # Test support, compiled only in the test environment: its own top-level boundary, named outside
  # `Pica` so that nothing in the library gains ExUnit.
  use Boundary, deps: [ExUnit]

  import ExUnit.Callbacks, only: [on_exit: 1]

  @app :pica

  @doc """
  Sets `key` to `value` for the rest of the test, restoring the previous value — or deleting the key,
  if it was unset — when the test exits.
  """
  @spec put_app_env(atom(), term()) :: :ok
  def put_app_env(key, value) when is_atom(key) do
    restore_on_exit(key)
    Application.put_env(@app, key, value)
  end

  @doc """
  Merges `overrides` into the keyword list at `key` for the rest of the test, restoring the whole
  entry when the test exits.

  For a module-keyed entry (`config :pica, Pica.SomeClient, …`) where a test changes
  one option — a client's `base_url` — and the rest must survive. An unset entry merges into `[]`.
  """
  @spec merge_app_env(atom(), keyword()) :: :ok
  def merge_app_env(key, overrides) when is_atom(key) and is_list(overrides) do
    restore_on_exit(key)
    Application.put_env(@app, key, Keyword.merge(Application.get_env(@app, key, []), overrides))
  end

  @doc """
  Unsets `key` for the rest of the test, restoring the previous value when the test exits.
  """
  @spec delete_app_env(atom()) :: :ok
  def delete_app_env(key) when is_atom(key) do
    restore_on_exit(key)
    Application.delete_env(@app, key)
  end

  defp restore_on_exit(key) do
    previous = Application.fetch_env(@app, key)
    on_exit(fn -> restore(key, previous) end)
  end

  defp restore(key, {:ok, value}), do: Application.put_env(@app, key, value)
  defp restore(key, :error), do: Application.delete_env(@app, key)
end
