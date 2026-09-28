defmodule Hextank.Tables.Table do
  @moduledoc """
  A GenServer holding one table's `%Game{}` while the table is in use.

  It only ever does process work: load, call `Hextank.Game`, save, broadcast, run the
  tick timer, and stop itself when nobody has used the table for a while (see README,
  *Lazy ticks*). All the rules live in `Hextank.Game`.

  Use it through `Hextank.Tables`, never directly.
  """

  use GenServer, restart: :transient

  alias Hextank.{Game, Storage}
  alias Hextank.Tables.Lobby

  require Logger

  @doc false
  def start_link(id), do: GenServer.start_link(__MODULE__, id, name: via(id))

  @doc "The name a table registers under, so it can be found by id."
  def via(id), do: {:via, Registry, {Hextank.Tables.Registry, id}}

  ## Starting

  @impl true
  def init(id) do
    case Storage.load_game(id) do
      {:ok, game} ->
        state = %{
          game: game,
          # Monitor ref => pid of each page watching this table.
          watchers: %{},
          tick_timer: nil,
          idle_ref: nil
        }

        # Apply the ticks missed while the table was asleep.
        state = state |> update_game(Game.catch_up(game, now())) |> schedule_tick()
        {:ok, reset_idle_timer(state)}

      {:error, :not_found} ->
        # Returning :ignore makes DynamicSupervisor.start_child/2 return :ignore.
        :ignore
    end
  end

  ## Requests (all count as activity, so they push back the idle stop)

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, {:ok, state.game}, reset_idle_timer(state)}
  end

  def handle_call(:watch, {pid, _tag}, state) do
    ref = Process.monitor(pid)
    state = %{state | watchers: Map.put(state.watchers, ref, pid)}
    {:reply, {:ok, state.game}, reset_idle_timer(state)}
  end

  def handle_call({:join, player_id, name}, _from, state) do
    change(state, &Game.add_player(&1, player_id, name, now()))
  end

  def handle_call({:leave, player_id}, _from, state) do
    change(state, &Game.remove_player(&1, player_id, now()))
  end

  def handle_call({:start, player_id}, _from, state) do
    seed = :rand.uniform(1_000_000_000)
    change(state, &Game.start(&1, player_id, now(), seed))
  end

  def handle_call({:freeze, player_id}, _from, state) do
    change(state, &Game.freeze(&1, player_id, now()))
  end

  def handle_call({:act, player_id, action}, _from, state) do
    change(state, &Game.act(&1, player_id, action, now()))
  end

  # Brings the game up to date, then applies one change from `Hextank.Game`.
  defp change(state, fun) do
    game = Game.catch_up(state.game, now())

    case fun.(game) do
      {:ok, game} ->
        state = state |> update_game(game) |> schedule_tick() |> reset_idle_timer()
        {:reply, {:ok, game}, state}

      {:error, reason} ->
        # The catch-up alone may have changed the game.
        state = state |> update_game(game) |> reset_idle_timer()
        {:reply, {:error, reason}, state}
    end
  end

  ## Timers and monitors

  @impl true
  def handle_info(:tick, state) do
    # Not activity: a ticking table with nobody watching still goes to sleep.
    state = state |> update_game(Game.catch_up(state.game, now())) |> schedule_tick()
    {:noreply, state}
  end

  def handle_info({:idle, ref}, %{idle_ref: ref} = state) do
    Logger.debug("table #{state.game.id} is idle, stopping")
    {:stop, :normal, state}
  end

  # An idle timer that was replaced by a newer one: ignore it.
  def handle_info({:idle, _old_ref}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    state = %{state | watchers: Map.delete(state.watchers, ref)}
    {:noreply, reset_idle_timer(state)}
  end

  ## Helpers

  # Saves, updates the lobby and tells every watcher, but only if something changed.
  defp update_game(%{game: game} = state, game), do: state

  defp update_game(state, game) do
    Storage.save_game(game)
    Lobby.put(game)
    Phoenix.PubSub.broadcast(Hextank.PubSub, "table:#{game.id}", {:game_updated, game})
    %{state | game: game}
  end

  defp schedule_tick(state) do
    if state.tick_timer, do: Process.cancel_timer(state.tick_timer)

    case Game.next_tick_at(state.game) do
      nil ->
        %{state | tick_timer: nil}

      tick_at ->
        delay = max(DateTime.diff(tick_at, now(), :millisecond), 0)
        %{state | tick_timer: Process.send_after(self(), :tick, delay)}
    end
  end

  # Starts (or restarts) the countdown to stopping, unless someone is watching. Each
  # countdown gets a fresh ref, so a message from an older one is ignored.
  defp reset_idle_timer(state) do
    if map_size(state.watchers) == 0 do
      ref = make_ref()
      Process.send_after(self(), {:idle, ref}, idle_timeout())
      %{state | idle_ref: ref}
    else
      %{state | idle_ref: nil}
    end
  end

  defp idle_timeout, do: Application.fetch_env!(:hextank, :table_idle_timeout)

  defp now, do: DateTime.utc_now()
end
