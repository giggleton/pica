defmodule Pica.NearestFace do
  @moduledoc false

  # Chooses, among installed faces, the one `Pica.lookup/3` returns for a family and a face: the
  # nearest within the face asked for, never a different kind of face. The family must be one of
  # the face's family names exactly. Plain and bold are upright, italic and bold_italic italic or
  # oblique, the upright never standing in. Plain is the weight nearest 400 below 600, bold the
  # weight nearest 700 at 600 and above, a tie going to the heavier, as CSS breaks the common ones
  # (500 over 300, 800 over 600). Among those, the width nearest normal is chosen, a tie going to
  # the narrower, as CSS does for a normal width; and then the first by path and index, so the
  # choice never depends on the order the machine listed its fonts in. No face of the right kind
  # is `:error`.

  @bold_from 600

  @type installed_face :: %{
          path: String.t(),
          index: non_neg_integer(),
          families: [String.t()],
          weight: non_neg_integer(),
          italic: boolean(),
          width: 1..9
        }

  @doc false
  # The installed face nearest `face` of `family`, or `:error` for none of the right kind.
  @spec choose([installed_face()], String.t(), Pica.face()) :: {:ok, installed_face()} | :error
  def choose(installed_faces, family, face) when is_list(installed_faces) and is_binary(family) do
    installed_faces
    |> Enum.filter(fn installed_face -> right_kind?(installed_face, family, face) end)
    |> Enum.min_by(fn installed_face -> preference(installed_face, face) end, fn -> :none end)
    |> chosen()
  end

  defp right_kind?(installed_face, family, face) do
    family in installed_face.families and installed_face.italic == italic?(face) and
      bold_weight?(installed_face.weight) == bold?(face)
  end

  # Smaller is preferred: the weight's distance from the face's, the heavier on a tie; the width's
  # distance from normal, the narrower on a tie; then path and index.
  defp preference(installed_face, face) do
    {abs(installed_face.weight - target_weight(face)), -installed_face.weight,
     abs(installed_face.width - 5), installed_face.width, installed_face.path,
     installed_face.index}
  end

  defp chosen(:none), do: :error
  defp chosen(installed_face), do: {:ok, installed_face}

  defp bold_weight?(weight), do: weight >= @bold_from

  defp target_weight(face), do: if(bold?(face), do: 700, else: 400)

  defp bold?(face), do: face in [:bold, :bold_italic]
  defp italic?(face), do: face in [:italic, :bold_italic]
end
