defmodule Hextank.Players do
  @moduledoc """
  Creating, loading and changing players. Each player is one small file (see
  `Hextank.Storage`); there is no process per player.
  """

  alias Hextank.{Moderation, Player, Storage, Tables}
  alias Hextank.Players.Bans

  @doc """
  Creates and saves a new player. A nickname with a prohibited word is refused (no
  strike: there's no player yet to give it to).
  """
  @spec create(String.t(), DateTime.t()) :: {:ok, Player.t()} | {:error, atom()}
  def create(nickname, now \\ DateTime.utc_now()) do
    with {:ok, nickname} <- Player.validate_nickname(nickname),
         :ok <- check_words(nickname) do
      player = %Player{id: Storage.new_id(), nickname: nickname, created_at: now}
      :ok = Storage.save_player(player)
      {:ok, player}
    end
  end

  @doc "Loads a player."
  @spec get(String.t()) :: {:ok, Player.t()} | {:error, :not_found}
  defdelegate get(id), to: Storage, as: :load_player

  @doc """
  Changes a player's nickname (screened like any text). Tanks keep the name they
  joined with.
  """
  @spec rename(Player.t(), String.t()) :: {:ok, Player.t()} | {:error, term()}
  def rename(player, nickname) do
    with {:ok, nickname} <- Player.validate_nickname(nickname),
         :ok <- screen(player, nickname) do
      player = %{player | nickname: nickname}
      :ok = Storage.save_player(player)
      {:ok, player}
    end
  end

  ## Moderation (see README, *Moderation*)

  @doc """
  Screens a text a player wrote. With a prohibited word, the player gets a strike
  and the text must not be sent or saved: the result says what the strike led to.
  The third strike bans the player (see `ban/1`).
  """
  @spec screen(Player.t(), String.t(), String.t() | nil) ::
          :ok | {:error, {:prohibited, :warning | :final_warning | :banned}}
  def screen(player, text, table_id \\ nil) do
    case Moderation.check(text, prohibited_words()) do
      :ok ->
        :ok

      {:error, {:prohibited, word}} ->
        # Reload first: the player in the caller's hands may be out of date.
        {:ok, player} = get(player.id)
        {player, outcome} = Player.add_strike(player, %{table_id: table_id, word: word}, now())
        :ok = Storage.save_player(player)
        if outcome == :banned, do: ban(player)
        {:error, {:prohibited, outcome}}
    end
  end

  # Nicknames of new players: no strike, just a refusal.
  defp check_words(text) do
    case Moderation.check(text, prohibited_words()) do
      :ok -> :ok
      {:error, {:prohibited, _word}} -> {:error, :inappropriate}
    end
  end

  # The compiled list, plus words from the :extra_prohibited_words config (only set in
  # tests, so they can use harmless words).
  defp prohibited_words do
    extra = Application.get_env(:hextank, :extra_prohibited_words, [])
    MapSet.union(Moderation.words(), MapSet.new(extra))
  end

  @doc """
  Bans a player: remembered in `Bans`, every open page of theirs is told
  (`:banned` on `"player:<id>"`), and their place at every unfinished table is
  frozen.
  """
  @spec ban(Player.t()) :: :ok
  def ban(player) do
    :ok = Bans.add(player.id)
    Phoenix.PubSub.broadcast(Hextank.PubSub, "player:#{player.id}", :banned)

    for summary <- Tables.list_for_player(player.id), summary.status != :finished do
      Tables.freeze(summary.id, player.id)
    end

    :ok
  end

  @doc """
  Lifts a ban and clears the strikes. Only when the human asks (see CLAUDE.md).
  Frozen tanks stay frozen.
  """
  @spec unban(String.t()) :: {:ok, Player.t()} | {:error, :not_found}
  def unban(player_id) do
    with {:ok, player} <- get(player_id) do
      player = Player.unban(player)
      :ok = Storage.save_player(player)
      :ok = Bans.remove(player.id)
      {:ok, player}
    end
  end

  defp now, do: DateTime.utc_now()

  @doc "Makes every rejoin link given out so far stop working."
  @spec reset_rejoin_link(Player.t()) :: {:ok, Player.t()}
  def reset_rejoin_link(player) do
    player = %{player | token_version: player.token_version + 1}
    :ok = Storage.save_player(player)
    {:ok, player}
  end
end
