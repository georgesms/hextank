defmodule Hextank.Tables.Lobby do
  @moduledoc """
  Keeps a small summary of every table in memory, so the lobby page never has to
  load 1000 games or wake up sleeping tables (see README, *Frugality*).

  The summaries are built from disk once at boot, then kept up to date by the table
  processes after every save. Once a day (and at boot) expired tables are deleted:
  finished ones 30 days after the end, never-started ones 7 days after creation.
  """

  use GenServer

  alias Hextank.{Game, Storage}

  @day 86_400
  @keep_finished_days 30
  @keep_unstarted_days 7

  @type summary :: %{
          id: String.t(),
          name: String.t(),
          visibility: :public | :private,
          status: Game.status(),
          creator_id: String.t() | nil,
          player_ids: [String.t()],
          tick_interval: pos_integer(),
          created_at: DateTime.t(),
          finished_at: DateTime.t() | nil,
          action_counts: %{optional(atom()) => non_neg_integer()}
        }

  @doc false
  def start_link(_options), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  ## API

  @doc "Adds or updates the summary of a game. Doesn't wait for an answer."
  @spec put(Game.t()) :: :ok
  def put(game), do: GenServer.cast(__MODULE__, {:put, summary(game)})

  @doc "Forgets a deleted table. Doesn't wait for an answer."
  @spec delete(String.t()) :: :ok
  def delete(id), do: GenServer.cast(__MODULE__, {:delete, id})

  @doc "Every table, newest first. For the admin page."
  @spec list_all() :: [summary()]
  def list_all, do: GenServer.call(__MODULE__, {:list, fn _summary -> true end})

  @doc "The public tables that are waiting for players or running, newest first."
  @spec list_public() :: [summary()]
  def list_public do
    GenServer.call(__MODULE__, {:list, &(&1.visibility == :public and &1.status != :finished)})
  end

  @doc "Every table the player is in, newest first."
  @spec list_for_player(String.t()) :: [summary()]
  def list_for_player(player_id) do
    GenServer.call(__MODULE__, {:list, &(player_id in &1.player_ids)})
  end

  @doc "Builds the summary of a game."
  @spec summary(Game.t()) :: summary()
  def summary(game) do
    %{
      id: game.id,
      name: game.name,
      visibility: game.visibility,
      status: game.status,
      creator_id: game.creator_id,
      player_ids: Map.keys(game.tanks),
      tick_interval: game.tick_interval,
      created_at: game.created_at,
      finished_at: game.finished_at,
      action_counts: game.action_counts
    }
  end

  @doc """
  Whether a table should be deleted: finished more than #{@keep_finished_days} days
  ago, or created more than #{@keep_unstarted_days} days ago and never started.
  """
  @spec expired?(summary(), DateTime.t()) :: boolean()
  def expired?(%{status: :finished, finished_at: finished_at}, now) do
    DateTime.diff(now, finished_at, :second) > @keep_finished_days * @day
  end

  def expired?(%{status: :lobby, created_at: created_at}, now) do
    DateTime.diff(now, created_at, :second) > @keep_unstarted_days * @day
  end

  def expired?(_summary, _now), do: false

  ## Server

  @impl true
  def init(nil) do
    # Load from disk after init/1 returns, so the rest of the app can start.
    {:ok, %{}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, _summaries) do
    summaries =
      for id <- Storage.list_table_ids(),
          {:ok, game} <- [Storage.load_game(id)],
          into: %{},
          do: {id, summary(game)}

    schedule_cleanup()
    {:noreply, delete_expired(summaries)}
  end

  @impl true
  def handle_cast({:put, summary}, summaries) do
    {:noreply, Map.put(summaries, summary.id, summary)}
  end

  def handle_cast({:delete, id}, summaries), do: {:noreply, Map.delete(summaries, id)}

  @impl true
  def handle_call({:list, keep?}, _from, summaries) do
    list =
      summaries
      |> Map.values()
      |> Enum.filter(keep?)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})

    {:reply, list, summaries}
  end

  @impl true
  def handle_info(:cleanup, summaries) do
    schedule_cleanup()
    {:noreply, delete_expired(summaries)}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @day * 1000)

  defp delete_expired(summaries) do
    now = DateTime.utc_now()

    expired_ids =
      for {id, summary} <- summaries,
          expired?(summary, now),
          # A table someone is using right now is left alone until the next cleanup.
          Registry.lookup(Hextank.Tables.Registry, id) == [],
          do: id

    Enum.each(expired_ids, &Storage.delete_table/1)
    Map.drop(summaries, expired_ids)
  end
end
