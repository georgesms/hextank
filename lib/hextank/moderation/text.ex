defmodule Hextank.Moderation.Text do
  @moduledoc """
  Turns text into the plain words that moderation compares (see README,
  *Moderation*). The same steps run on the word list and on what players write, so
  both sides always look alike.

  It's a separate module so that `Hextank.Moderation` can use it while compiling, to
  prepare the word list once.
  """

  # Letters people swap in to get around word lists.
  @swaps %{"4" => "a", "3" => "e", "0" => "o", "1" => "i", "@" => "a", "$" => "s"}

  @doc """
  Lowercase, no accents, letter swaps undone, repeated letters shortened.

      iex> Text.normalize("CÃÃÃO")
      "cao"

      iex> Text.normalize("h3ll0")
      "helo"
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(text) do
    text
    |> String.downcase()
    |> remove_accents()
    |> String.replace(Map.keys(@swaps), &Map.fetch!(@swaps, &1))
    |> String.replace(~r/(.)\1+/u, "\\1")
  end

  @doc """
  The normalized words of a text: anything that isn't a letter separates words.

      iex> Text.words("Olá, s3u   tanque!")
      ["ola", "seu", "tanque"]
  """
  @spec words(String.t()) :: [String.t()]
  def words(text) do
    text
    |> normalize()
    |> String.split(~r/[^\p{L}]+/u, trim: true)
  end

  # "ã" is "a" plus a combining tilde once decomposed (NFD); drop the combining marks.
  defp remove_accents(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
