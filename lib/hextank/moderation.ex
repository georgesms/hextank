defmodule Hextank.Moderation do
  @moduledoc """
  Checks text players write against the prohibited words (see README,
  *Moderation*). Pure: what happens to the player (warnings, ban) is decided by
  `Hextank.Player.add_strike/3` and done by `Hextank.Players.screen/4`.

  The word list is read from `priv/moderation/prohibited_words.txt` **while
  compiling**, normalized once and kept in the module, so checking never touches the
  disk. Changing the list needs a recompile (a deploy in production).
  """

  alias Hextank.Moderation.Text

  @words_file Path.expand("../../priv/moderation/prohibited_words.txt", __DIR__)

  # Recompile this module whenever the file changes.
  @external_resource @words_file

  @words @words_file
         |> File.read!()
         |> String.split("\n")
         |> Enum.map(&String.trim/1)
         |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
         |> Enum.map(&Text.normalize/1)
         |> MapSet.new()

  @doc "The normalized prohibited words from the list file."
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
