defmodule Hextank.Players.Bans do
  @moduledoc """
  The ids of banned players, kept in memory so checking a ban never reads the disk
  (see CLAUDE.md, *Identity, security and moderation rules*).

  An `Agent` is the simplest process that just holds a value: here a `MapSet` of
  player ids, loaded from the player files at boot.
  """

  use Agent

  alias Hextank.{Player, Storage}

  @doc false
  def start_link(_options), do: Agent.start_link(&load/0, name: __MODULE__)

  defp load do
    for id <- Storage.list_player_ids(),
        {:ok, player} <- [Storage.load_player(id)],
        Player.banned?(player),
        into: MapSet.new(),
        do: id
  end

  @doc "Whether the player is banned."
  @spec banned?(String.t()) :: boolean()
  def banned?(player_id), do: Agent.get(__MODULE__, &MapSet.member?(&1, player_id))

  @doc "How many players are banned."
  @spec count() :: non_neg_integer()
  def count, do: Agent.get(__MODULE__, &MapSet.size/1)

  @doc "Marks a player as banned."
  @spec add(String.t()) :: :ok
  def add(player_id), do: Agent.update(__MODULE__, &MapSet.put(&1, player_id))

  @doc "Lifts a player's ban."
  @spec remove(String.t()) :: :ok
  def remove(player_id), do: Agent.update(__MODULE__, &MapSet.delete(&1, player_id))
end
