defmodule Hextank.Game do
  @moduledoc """
  The whole state of one table and the rules of Tank Tactics (see README, *Rules*).

  Everything here is pure: functions take a game and return a new one. Functions
  that change the game return `{:ok, game}` or `{:error, reason}`. The current time
  is always passed in as `now` and randomness as a `seed`, so this module never reads
  the clock or calls `:rand` itself.

  A game goes through three statuses: `:lobby` (players join and leave), `:running`
  and `:finished`.
  """

  alias Hextank.{Board, Hex, Random, Settings, Tank}

  @min_players 2
  @max_players 20
  @max_events 50

  @enforce_keys [:id, :name, :visibility, :creator_id, :tick_interval, :created_at]
  defstruct [
    :id,
    :name,
    # :public (listed in the lobby) or :private (joined through its link)
    :visibility,
    :creator_id,
    # Seconds between two ticks.
    :tick_interval,
    :created_at,
    status: :lobby,
    # player_id => %Tank{}
    tanks: %{},
    board: nil,
    started_at: nil,
    # How many ticks have been handed out since the start.
    ticks: 0,
    winner_id: nil,
    finished_at: nil,
    # Newest first, at most @max_events of them.
    events: [],
    # Board size, rocks, starting HP and range (see Hextank.Settings).
    settings: Settings.defaults()
  ]

  @type player_id :: String.t()
  @type status :: :lobby | :running | :finished
  @type action ::
          {:move, Hex.t()}
          | {:shoot, player_id()}
          | :upgrade_range
          | {:give_ap, player_id()}
          | {:vote, player_id()}
  @type event :: %{
          required(:type) => atom(),
          required(:at) => DateTime.t(),
          optional(:actor) => player_id(),
          optional(:target) => player_id()
        }
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          visibility: :public | :private,
          creator_id: player_id() | nil,
          tick_interval: pos_integer(),
          created_at: DateTime.t(),
          status: status(),
          tanks: %{player_id() => Tank.t()},
          board: Board.t() | nil,
          started_at: DateTime.t() | nil,
          ticks: non_neg_integer(),
          winner_id: player_id() | nil,
          finished_at: DateTime.t() | nil,
          events: [event()],
          settings: Settings.t()
        }

  @type result :: {:ok, t()} | {:error, atom()}

  @doc """
  Builds a new game in the `:lobby` status, without players.

  `attrs` must have `:id`, `:name`, `:visibility`, `:creator_id`, `:tick_interval`
  (in seconds) and `:created_at`, and may have `:settings` (already validated with
  `Hextank.Settings.validate/1`).
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs), do: struct!(__MODULE__, attrs)

  ## Lobby

  @doc "Adds a player to a game that hasn't started yet."
  @spec add_player(t(), player_id(), String.t(), DateTime.t()) :: result()
  def add_player(%__MODULE__{status: :lobby} = game, player_id, name, now) do
    cond do
      Map.has_key?(game.tanks, player_id) ->
        {:error, :already_joined}

      map_size(game.tanks) >= @max_players ->
        {:error, :table_full}

      true ->
        tank = %Tank{
          player_id: player_id,
          name: name,
          seat: next_seat(game),
          hp: game.settings.start_hp,
          range: game.settings.start_range
        }

        game =
          game
          |> put_tank(tank)
          |> log(%{type: :joined, actor: player_id}, now)

        {:ok, game}
    end
  end

  def add_player(_game, _player_id, _name, _now), do: {:error, :game_already_started}

  @doc """
  Removes a player from a game that hasn't started yet. If the creator leaves, the
  player who joined first becomes the new creator.
  """
  @spec remove_player(t(), player_id(), DateTime.t()) :: result()
  def remove_player(%__MODULE__{status: :lobby} = game, player_id, now) do
    if Map.has_key?(game.tanks, player_id) do
      game =
        %{game | tanks: Map.delete(game.tanks, player_id)}
        |> pass_on_creator(player_id)
        |> log(%{type: :left, actor: player_id}, now)

      {:ok, game}
    else
      {:error, :not_in_game}
    end
  end

  def remove_player(_game, _player_id, _now), do: {:error, :game_already_started}

  @doc """
  Starts the game: builds the board, places every tank on a random free cell and
  starts counting ticks from `now`. Only the creator can start, with at least
  #{@min_players} players, and the board must have an open cell for everyone.
  """
  @spec start(t(), player_id(), DateTime.t(), integer()) :: result()
  def start(%__MODULE__{status: :lobby} = game, player_id, now, seed) do
    cond do
      player_id != game.creator_id ->
        {:error, :not_creator}

      map_size(game.tanks) < @min_players ->
        {:error, :not_enough_players}

      true ->
        place_tanks(game, now, seed)
    end
  end

  def start(_game, _player_id, _now, _seed), do: {:error, :game_already_started}

  defp place_tanks(game, now, seed) do
    player_count = map_size(game.tanks)

    board =
      Board.generate(player_count, seed,
        radius: game.settings.board_radius,
        obstacle_percent: game.settings.obstacle_percent
      )

    # Nobody starts within reach of another tank.
    spawn_distance = game.settings.start_range + 1

    if length(Board.open_cells(board)) < player_count do
      {:error, :board_too_small}
    else
      positions = spawn_positions(board, player_count, spawn_distance, seed + 1)

      tanks =
        game
        |> tanks_by_seat()
        |> Enum.zip(positions)
        |> Map.new(fn {tank, position} -> {tank.player_id, %{tank | position: position}} end)

      game =
        %{
          game
          | status: :running,
            board: board,
            tanks: tanks,
            started_at: DateTime.truncate(now, :second)
        }
        |> log(%{type: :started}, now)

      {:ok, game}
    end
  end

  ## Ticks

  @doc """
  When the next tick is due, or `nil` if the game isn't running.
  """
  @spec next_tick_at(t()) :: DateTime.t() | nil
  def next_tick_at(%__MODULE__{status: :running} = game) do
    DateTime.add(game.started_at, (game.ticks + 1) * game.tick_interval, :second)
  end

  def next_tick_at(_game), do: nil

  @doc """
  Applies every tick that should have happened by `now` and hasn't yet. Used both by
  the tick timer and when a sleeping table wakes up (see README, *Lazy ticks*).
  """
  @spec catch_up(t(), DateTime.t()) :: t()
  def catch_up(%__MODULE__{status: :running} = game, now) do
    due = div(DateTime.diff(now, game.started_at, :second), game.tick_interval)
    missed = due - game.ticks

    if missed > 0, do: tick(game, missed), else: game
  end

  def catch_up(game, _now), do: game

  @doc """
  Hands out `count` ticks at once: every living tank gets `count` AP, every ghost
  gets its vote back (votes don't pile up: a ghost has at most one).
  """
  @spec tick(t(), pos_integer()) :: t()
  def tick(game, count \\ 1) do
    tanks =
      Map.new(game.tanks, fn {player_id, tank} ->
        tank =
          if Tank.alive?(tank),
            do: %{tank | ap: tank.ap + count},
            else: %{tank | has_vote: true}

        {player_id, tank}
      end)

    %{game | tanks: tanks, ticks: game.ticks + count}
  end

  ## Actions

  @doc """
  A player acts. Every action costs 1 AP, except a ghost's vote.

    * `{:move, hex}` – move to a neighbouring free cell
    * `{:shoot, target_id}` – 1 damage to a tank within range
    * `:upgrade_range` – range + 1
    * `{:give_ap, target_id}` – give 1 AP to a tank within range
    * `{:vote, target_id}` – ghosts only: give 1 AP to any living tank
  """
  @spec act(t(), player_id(), action(), DateTime.t()) :: result()
  def act(%__MODULE__{status: :running} = game, player_id, action, now) do
    with {:ok, tank} <- fetch_player(game, player_id),
         :ok <- check_not_frozen(tank),
         {:ok, game, event} <- perform(game, tank, action) do
      {:ok, game |> log(event, now) |> check_winner(now)}
    end
  end

  def act(_game, _player_id, _action, _now), do: {:error, :game_not_running}

  defp perform(game, tank, {:move, target}) do
    with :ok <- check_alive(tank),
         :ok <- check_ap(tank),
         :ok <- check_adjacent(tank.position, target),
         :ok <- check_open(game, target) do
      game = update_tank(game, tank.player_id, &%{&1 | ap: &1.ap - 1, position: target})
      {:ok, game, %{type: :moved, actor: tank.player_id}}
    end
  end

  defp perform(game, tank, {:shoot, target_id}) do
    with :ok <- check_alive(tank),
         :ok <- check_ap(tank),
         {:ok, target} <- fetch_target(game, tank, target_id),
         :ok <- check_in_range(tank, target) do
      game =
        game
        |> update_tank(tank.player_id, &%{&1 | ap: &1.ap - 1})
        |> update_tank(target.player_id, &damage/1)

      type = if target.hp == 1, do: :destroyed, else: :shot
      {:ok, game, %{type: type, actor: tank.player_id, target: target.player_id}}
    end
  end

  defp perform(game, tank, :upgrade_range) do
    with :ok <- check_alive(tank),
         :ok <- check_ap(tank) do
      game = update_tank(game, tank.player_id, &%{&1 | ap: &1.ap - 1, range: &1.range + 1})
      {:ok, game, %{type: :upgraded, actor: tank.player_id}}
    end
  end

  defp perform(game, tank, {:give_ap, target_id}) do
    with :ok <- check_alive(tank),
         :ok <- check_ap(tank),
         {:ok, target} <- fetch_target(game, tank, target_id),
         :ok <- check_in_range(tank, target) do
      game =
        game
        |> update_tank(tank.player_id, &%{&1 | ap: &1.ap - 1})
        |> update_tank(target.player_id, &%{&1 | ap: &1.ap + 1})

      {:ok, game, %{type: :gave_ap, actor: tank.player_id, target: target.player_id}}
    end
  end

  defp perform(game, tank, {:vote, target_id}) do
    with :ok <- check_ghost(tank),
         :ok <- check_vote(tank),
         {:ok, target} <- fetch_target(game, tank, target_id) do
      game =
        game
        |> update_tank(tank.player_id, &%{&1 | has_vote: false})
        |> update_tank(target.player_id, &%{&1 | ap: &1.ap + 1})

      {:ok, game, %{type: :voted, actor: tank.player_id, target: target.player_id}}
    end
  end

  defp perform(_game, _tank, _action), do: {:error, :unknown_action}

  defp damage(tank) do
    case tank.hp - 1 do
      0 -> %{tank | hp: 0, position: nil}
      hp -> %{tank | hp: hp}
    end
  end

  # The last tank standing wins.
  defp check_winner(game, now) do
    case living_tanks(game) do
      [winner] ->
        %{game | status: :finished, winner_id: winner.player_id, finished_at: now}
        |> log(%{type: :won, actor: winner.player_id}, now)

      _ ->
        game
    end
  end

  ## Checks: each returns :ok or {:error, reason}

  defp fetch_player(game, player_id) do
    case Map.fetch(game.tanks, player_id) do
      {:ok, tank} -> {:ok, tank}
      :error -> {:error, :not_in_game}
    end
  end

  # Targets are always living tanks other than yourself.
  defp fetch_target(_game, %Tank{player_id: player_id}, player_id),
    do: {:error, :cannot_target_self}

  defp fetch_target(game, _tank, target_id) do
    case Map.fetch(game.tanks, target_id) do
      {:ok, target} -> if Tank.alive?(target), do: {:ok, target}, else: {:error, :invalid_target}
      :error -> {:error, :invalid_target}
    end
  end

  defp check_not_frozen(tank), do: if(tank.frozen, do: {:error, :frozen}, else: :ok)
  defp check_alive(tank), do: if(Tank.alive?(tank), do: :ok, else: {:error, :tank_destroyed})
  defp check_ghost(tank), do: if(Tank.ghost?(tank), do: :ok, else: {:error, :not_a_ghost})
  defp check_vote(tank), do: if(tank.has_vote, do: :ok, else: {:error, :no_vote_left})
  defp check_ap(tank), do: if(tank.ap >= 1, do: :ok, else: {:error, :not_enough_ap})

  defp check_adjacent(from, to) do
    if Hex.distance(from, to) == 1, do: :ok, else: {:error, :not_adjacent}
  end

  defp check_in_range(tank, target) do
    if Hex.distance(tank.position, target.position) <= tank.range,
      do: :ok,
      else: {:error, :out_of_range}
  end

  defp check_open(game, hex) do
    cond do
      not Board.on_board?(game.board, hex) -> {:error, :off_board}
      Board.obstacle?(game.board, hex) -> {:error, :obstacle}
      tank_at(game, hex) != nil -> {:error, :cell_occupied}
      true -> :ok
    end
  end

  ## Questions about a game (used by the web layer to show what's possible)

  @doc "The player's tank, or `nil`."
  @spec tank(t(), player_id()) :: Tank.t() | nil
  def tank(game, player_id), do: Map.get(game.tanks, player_id)

  @doc "All tanks, living and ghosts, in join order."
  @spec tanks_by_seat(t()) :: [Tank.t()]
  def tanks_by_seat(game), do: game.tanks |> Map.values() |> Enum.sort_by(& &1.seat)

  @doc "The tanks still on the board, in join order."
  @spec living_tanks(t()) :: [Tank.t()]
  def living_tanks(game), do: game |> tanks_by_seat() |> Enum.filter(&Tank.alive?/1)

  @doc "The tank standing on a hex, or `nil`."
  @spec tank_at(t(), Hex.t()) :: Tank.t() | nil
  def tank_at(game, hex), do: Enum.find(Map.values(game.tanks), &(&1.position == hex))

  @doc "Where the player's tank could move right now (ignoring AP)."
  @spec move_targets(t(), player_id()) :: [Hex.t()]
  def move_targets(game, player_id) do
    case tank(game, player_id) do
      %Tank{position: %Hex{} = position} ->
        position |> Hex.neighbors() |> Enum.filter(&(check_open(game, &1) == :ok))

      _ ->
        []
    end
  end

  @doc "The living tanks the player could shoot or give AP to right now (ignoring AP)."
  @spec tanks_in_range(t(), player_id()) :: [Tank.t()]
  def tanks_in_range(game, player_id) do
    case tank(game, player_id) do
      %Tank{position: %Hex{}} = tank ->
        game
        |> living_tanks()
        |> Enum.filter(&(&1.player_id != player_id and check_in_range(tank, &1) == :ok))

      _ ->
        []
    end
  end

  ## Helpers

  defp put_tank(game, tank), do: %{game | tanks: Map.put(game.tanks, tank.player_id, tank)}

  defp update_tank(game, player_id, fun) do
    %{game | tanks: Map.update!(game.tanks, player_id, fun)}
  end

  defp next_seat(game) do
    game.tanks |> Map.values() |> Enum.map(& &1.seat) |> Enum.max(fn -> 0 end) |> Kernel.+(1)
  end

  defp pass_on_creator(%{creator_id: creator_id} = game, creator_id) do
    case tanks_by_seat(game) do
      [first | _] -> %{game | creator_id: first.player_id}
      [] -> %{game | creator_id: nil}
    end
  end

  defp pass_on_creator(game, _player_id), do: game

  defp log(game, event, now) do
    event = Map.put(event, :at, now)
    %{game | events: Enum.take([event | game.events], @max_events)}
  end

  # Spread tanks out: first pick cells at least `distance` apart from each
  # other; if the board is too crowded for that, fill up with any open cell.
  defp spawn_positions(board, count, distance, seed) do
    cells = board |> Board.open_cells() |> Random.shuffle(seed)

    spread =
      cells
      |> Enum.reduce([], fn hex, chosen ->
        far_enough? = Enum.all?(chosen, &(Hex.distance(&1, hex) >= distance))
        if length(chosen) < count and far_enough?, do: [hex | chosen], else: chosen
      end)
      |> Enum.reverse()

    spread ++ Enum.take(cells -- spread, count - length(spread))
  end
end
