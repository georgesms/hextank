defmodule Hextank.Players do
  @moduledoc """
  Creating, loading and changing players. Each player is one small file (see
  `Hextank.Storage`); there is no process per player.
  """

  alias Hextank.{Player, Storage}

  @doc "Creates and saves a new player."
  @spec create(String.t(), DateTime.t()) :: {:ok, Player.t()} | {:error, :invalid_nickname}
  def create(nickname, now \\ DateTime.utc_now()) do
    with {:ok, nickname} <- Player.validate_nickname(nickname) do
      player = %Player{id: Storage.new_id(), nickname: nickname, created_at: now}
      :ok = Storage.save_player(player)
      {:ok, player}
    end
  end

  @doc "Loads a player."
  @spec get(String.t()) :: {:ok, Player.t()} | {:error, :not_found}
  defdelegate get(id), to: Storage, as: :load_player

  @doc "Changes a player's nickname. Tanks keep the name they joined with."
  @spec rename(Player.t(), String.t()) :: {:ok, Player.t()} | {:error, :invalid_nickname}
  def rename(player, nickname) do
    with {:ok, nickname} <- Player.validate_nickname(nickname) do
      player = %{player | nickname: nickname}
      :ok = Storage.save_player(player)
      {:ok, player}
    end
  end

  @doc "Makes every rejoin link given out so far stop working."
  @spec reset_rejoin_link(Player.t()) :: {:ok, Player.t()}
  def reset_rejoin_link(player) do
    player = %{player | token_version: player.token_version + 1}
    :ok = Storage.save_player(player)
    {:ok, player}
  end
end
