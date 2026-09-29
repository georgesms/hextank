defmodule Hextank.Tables.Lobby do
  @moduledoc """
  Keeps a small summary of every table in memory, so the lobby page never has to
  load 1000 games or wake up sleeping tables (see README, *Frugality*).

  The summaries are built from disk once at boot, then kept up to date by the table
  processes after every save. Once a day (and at boot) expired tables are deleted:
  finished ones 7 days after the end, never-started ones 7 days after creation, and
  abandoned running ones, where every living tank has more than 200 AP.
  """

  use GenServer

  alias Hextank.{Game, Storage}

  @day 86_400
  @keep_finished_days 7
  @keep_unstarted_days 7
  # Nobody spends AP any more at a table where every living tank has this many.
  @abandoned_ap 200

  @type summary :: %{
          id: String.t(),
          name: String.t(),
          visibility: :public | :private,
          status: Game.status(),
          creator_id: String.t() | nil,
          player_ids: [String.t()],
          alive_count: non_neg_integer(),
          winner_name: String.t() | nil,
          tick_interval: pos_integer(),
          created_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          ticks: non_neg_integer(),
          lowest_ap: non_neg_integer() | nil,
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

  @doc "The summary of one table, or `nil` if there's no such table."
  @spec get(String.t()) :: summary() | nil
  def get(id), do: GenServer.call(__MODULE__, {:get, id})

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
      # For the lobby's cards: "3 alive, 2 destroyed", "Ana won".
      alive_count: length(Game.living_tanks(game)),
      winner_name: winner_name(game),
      tick_interval: game.tick_interval,
      created_at: game.created_at,
      # Enough to work out the AP of a sleeping table without loading it.
      started_at: game.started_at,
      ticks: game.ticks,
      lowest_ap: Game.lowest_ap(game),
      finished_at: game.finished_at,
      action_counts: game.action_counts
    }
  end

  defp winner_name(%Game{winner_id: nil}), do: nil
  defp winner_name(game), do: Game.tank(game, game.winner_id).name

  @doc """
  When a finished or never-started table will be deleted:
  #{@keep_finished_days} days after the end, or #{@keep_unstarted_days} days after
  creation. `nil` for a running table, which is deleted only once it's abandoned (see
  `expired?/2`). Takes a summary or a `%Game{}`.
  """
  @spec expires_at(map()) :: DateTime.t() | nil
  def expires_at(%{status: :finished, finished_at: finished_at}) do
    DateTime.add(finished_at, @keep_finished_days * @day, :second)
  end

  def expires_at(%{status: :lobby, created_at: created_at}) do
    DateTime.add(created_at, @keep_unstarted_days * @day, :second)
  end

  def expires_at(_summary), do: nil

  @doc """
  Whether a table should be deleted: finished or never started and past
  `expires_at/1`, or running with every living tank above #{@abandoned_ap} AP. A
  sleeping table's AP is worked out from the clock: the lowest AP at the last save,
  plus the ticks missed since.
  """
  @spec expired?(summary(), DateTime.t()) :: boolean()
  def expired?(%{status: :running, lowest_ap: lowest_ap} = summary, now)
      when is_integer(lowest_ap) do
    missed = max(Game.ticks_due(summary, now) - summary.ticks, 0)
    lowest_ap + missed > @abandoned_ap
  end

  def expired?(summary, now) do
    case expires_at(summary) do
      nil -> false
      expires_at -> DateTime.after?(now, expires_at)
    end
  end

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
  def handle_call({:get, id}, _from, summaries), do: {:reply, Map.get(summaries, id), summaries}

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
