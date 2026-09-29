defmodule Hextank.Moderation do
  @moduledoc """
  Checks text players write against the prohibited words (see README,
  *Moderation*). Pure: what happens to the player (warnings, ban) is decided by
  `Hextank.Player.add_strike/3` and done by `Hextank.Players.screen/4`.

  The word list is read from `priv/moderation/prohibited_words.txt` **while
  compiling**: each word is normalized and joined by its Portuguese forms (gender,
  size and plural, see `Hextank.Moderation.Text.word_forms/1`), minus the innocent
  words in `priv/moderation/allowed_words.txt`. The result is kept in the module, so
  checking never touches the disk. Changing either file needs a recompile (a deploy
  in production).
  """

  alias Hextank.Moderation.Text

  @words_file Path.expand("../../priv/moderation/prohibited_words.txt", __DIR__)
  @allowed_file Path.expand("../../priv/moderation/allowed_words.txt", __DIR__)

  # Recompile this module whenever one of the files changes.
  @external_resource @words_file
  @external_resource @allowed_file

  # Ordinary words that a form would block by accident ("bruxo" from "bruxa").
  # They win over the list.
  @allowed @allowed_file |> File.read!() |> Text.list_words() |> MapSet.new()

  @words @words_file
         |> File.read!()
         |> Text.list_words()
         |> Enum.flat_map(&Text.word_forms/1)
         |> MapSet.new()
         |> MapSet.difference(@allowed)

  @doc "The normalized prohibited words: the listed ones and their forms."
  @spec words() :: MapSet.t(String.t())
  def words, do: @words

  @doc """
  Checks a text. Returns `{:error, {:prohibited, word}}` with the first prohibited
  word found (normalized), or `:ok`. Tests pass their own harmless list as `words`.

      iex> Moderation.check("what a b4dw0rd move", MapSet.new(["badword"]))
      {:error, {:prohibited, "badword"}}

      iex> Moderation.check("nice move", MapSet.new(["badword"]))
      :ok
  """
  @spec check(String.t(), MapSet.t(String.t())) :: :ok | {:error, {:prohibited, String.t()}}
  def check(text, words \\ @words) do
    case Enum.find(Text.words(text), &MapSet.member?(words, &1)) do
      nil -> :ok
      word -> {:error, {:prohibited, word}}
    end
  end
end
