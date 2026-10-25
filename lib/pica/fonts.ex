defmodule Pica.Fonts do
  @moduledoc false

  # The fonts Pica finds by name: the families an app registers, and the machine's installed fonts
  # behind them. Every table lives in `:persistent_term`, so a lookup from any process reads it
  # without copying, and this is the one module excluded from `CorePurity` for it (`.credo.exs`).
  #
  # A registered family is one key, `{Pica.Fonts, :family, family}`, holding a map of its faces,
  # so registering it again replaces it whole. Writing a key that exists, or erasing one, runs a
  # global garbage collection, which is why fonts are registered at startup and not per request.
  #
  # The installed fonts are scanned at the first lookup a registered family cannot answer, and
  # the list of their faces is kept under `{Pica.Fonts, :installed_faces}` for the life of the VM.
  # Each installed face is loaded the first time it is chosen and kept under
  # `{Pica.Fonts, :installed_font, path, index}`: a new key, which runs no collection. Two lookups
  # racing to the same first scan or load both do it and the later write wins, so the cost is
  # done twice, never a wrong answer.

  alias Pica.{Font, Native, NearestFace}

  @doc false
  # Files `faces`, a map of face to `%Pica.Font{}`, under `family`, replacing any family of that
  # name.
  @spec register(String.t(), %{optional(Pica.face()) => Font.t()}) :: :ok
  def register(family, faces) when is_binary(family) and is_map(faces) do
    family
    |> family_key()
    |> :persistent_term.put(faces)
  end

  @doc false
  # Forgets the registered family; `:ok` whether or not it was registered.
  @spec unregister(String.t()) :: :ok
  def unregister(family) when is_binary(family) do
    family
    |> family_key()
    |> :persistent_term.erase()

    :ok
  end

  @doc false
  @spec registered?(String.t()) :: boolean()
  def registered?(family) when is_binary(family) do
    family
    |> family_key()
    |> :persistent_term.get(:none)
    |> Kernel.!=(:none)
  end

  @doc false
  # The registered families' names, sorted.
  @spec families() :: [String.t()]
  def families do
    for({{__MODULE__, :family, family}, _faces} <- :persistent_term.get(), do: family)
    |> Enum.sort()
  end

  @doc false
  # The face of the family: the registered face where the family is registered with it, else,
  # when `installed?`, the nearest installed face (`Pica.NearestFace`), else `:error`. An installed
  # face whose file no longer reads or loads is `:error`.
  @spec lookup(String.t(), Pica.face(), boolean()) :: {:ok, Font.t()} | :error
  def lookup(family, face, installed?) when is_binary(family) and is_boolean(installed?) do
    family
    |> family_key()
    |> :persistent_term.get(%{})
    |> Map.fetch(face)
    |> registered_or_installed(family, face, installed?)
  end

  defp registered_or_installed({:ok, font}, _family, _face, _installed?), do: {:ok, font}
  defp registered_or_installed(:error, _family, _face, false), do: :error

  defp registered_or_installed(:error, family, face, true) do
    case NearestFace.choose(installed_faces(), family, face) do
      {:ok, installed_face} -> installed_font(installed_face)
      :error -> :error
    end
  end

  defp installed_faces do
    case :persistent_term.get({__MODULE__, :installed_faces}, :none) do
      :none ->
        installed_faces = Native.installed_faces(nil)
        :persistent_term.put({__MODULE__, :installed_faces}, installed_faces)
        installed_faces

      installed_faces ->
        installed_faces
    end
  end

  defp installed_font(%{path: path, index: index}) do
    key = {__MODULE__, :installed_font, path, index}

    case :persistent_term.get(key, :none) do
      :none -> load_installed(key, path, index)
      font -> {:ok, font}
    end
  end

  defp load_installed(key, path, index) do
    with {:ok, bytes} <- File.read(path),
         {:ok, font} <- Font.load(bytes, index) do
      :persistent_term.put(key, font)
      {:ok, font}
    else
      {:error, _reason} -> :error
    end
  end

  defp family_key(family), do: {__MODULE__, :family, family}
end
