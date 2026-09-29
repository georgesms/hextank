defmodule Hextank.Moderation.Text do
  @moduledoc """
  Turns text into the plain words that moderation compares (see README,
  *Moderation*). The same steps run on the word list and on what players write, so
  both sides always look alike.

  It also works out the Portuguese forms of a listed word (`word_forms/1`). It's a
  separate module so that `Hextank.Moderation` can use it while compiling, to prepare
  the word list once.
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

  @doc """
  The words of a word list file's contents, normalized: one word per line, empty
  lines and lines starting with `#` skipped.

      iex> Text.list_words("# a comment\\n\\nBadWord\\n")
      ["badword"]
  """
  @spec list_words(String.t()) :: [String.t()]
  def list_words(contents) do
    contents
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.map(&normalize/1)
  end

  # Portuguese gender and size endings. A word ending in the first one also gets its
  # stem with each of the others. The first match wins, so "ona" comes before "a".
  @endings [
    {"ao", ["ona"]},
    {"ona", ["ao"]},
    {"o", ["a", "inho", "inha", "ao", "ona"]},
    {"a", ["o", "inha", "inho", "ao", "ona"]}
  ]

  @doc """
  A normalized word and the forms it takes in Portuguese: the other gender (-o/-a),
  smaller (-inho/-inha), bigger (-ão/-ona), and each of those in the plural (-s,
  -es, -ões, -ães). Stems shorter than 3 letters keep only their plurals. English
  words mostly get just a plural, which is what they need.

      iex> Text.word_forms("gato")
      ["gato", "gatos", "gata", "gatas", "gatinho", "gatinhos", "gatinha", "gatinhas",
       "gatao", "gatoes", "gataes", "gataos", "gatona", "gatonas"]

      iex> Text.word_forms("leitao")
      ["leitao", "leitoes", "leitaes", "leitaos", "leitona", "leitonas"]

      iex> Text.word_forms("flor")
      ["flor", "flors", "flores"]
  """
  @spec word_forms(String.t()) :: [String.t()]
  def word_forms(word) do
    word
    |> gender_and_size_forms()
    |> Enum.flat_map(&[&1 | plurals(&1)])
    |> Enum.map(&normalize/1)
    |> Enum.uniq()
  end

  defp gender_and_size_forms(word) do
    case Enum.find(@endings, fn {ending, _others} -> String.ends_with?(word, ending) end) do
      {ending, others} when byte_size(word) - byte_size(ending) >= 3 ->
        stem = binary_part(word, 0, byte_size(word) - byte_size(ending))
        [word | Enum.map(others, &(stem <> &1))]

      _no_rule_or_short_stem ->
        [word]
    end
  end

  defp plurals(word) do
    cond do
      String.ends_with?(word, "ao") ->
        stem = binary_part(word, 0, byte_size(word) - 2)
        [stem <> "oes", stem <> "aes", word <> "s"]

      String.ends_with?(word, ["r", "z"]) ->
        [word <> "s", word <> "es"]

      true ->
        [word <> "s"]
    end
  end

  # "ã" is "a" plus a combining tilde once decomposed (NFD); drop the combining marks.
  defp remove_accents(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
