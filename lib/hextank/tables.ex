defmodule Hextank.Tables do
  @moduledoc """
  The public API for tables, used by the web layer.

  Each table runs as a `Hextank.Tables.Table` process only while it's in use. The
  functions here find the process, starting it from disk if needed, and talk to it.
  Watchers (the table pages) subscribe to `"table:<id>"` and get
  `{:game_updated, game}` after every change, and `:table_deleted` if the table is
  deleted.
  """

  alias Hextank.{Game, Player, Players, Settings, Storage}
  alias Hextank.Players.Bans
  alias Hextank.Tables.{Lobby, Table}

  @tick_intervals [60, 3_600, 86_400]

  @doc "The tick intervals a new table can choose from, in seconds."
  @spec tick_intervals() :: [pos_integer()]
  def tick_intervals, do: @tick_intervals

  @doc """
  Creates a table, with its creator as the first player. The name goes through
  moderation (`Hextank.Players.screen/3`).

  `attrs` has `:name` (3 to 40 characters), `:visibility` (`:public` or `:private`),
  `:tick_interval` (one of `tick_intervals/0`) and optionally `:settings` (see
  `Hextank.Settings`; missing values get the defaults).
  """
  @spec create_table(Player.t(), map(), DateTime.t()) :: {:ok, Game.t()} | {:error, term()}
  def create_table(%Player{} = creator, attrs, now \\ DateTime.utc_now()) do
    name = attrs |> Map.get(:name, "") |> String.trim()

    with :ok <- check_not_banned(creator.id),
         :ok <- check_name(name),
         :ok <- Players.screen(creator, name),
         :ok <- check_visibility(attrs[:visibility]),
         :ok <- check_tick_interval(attrs[:tick_interval]),
         {:ok, settings} <- Settings.validate(Map.get(attrs, :settings, %{})) do
      game =
        Game.new(
          id: Storage.new_id(),
          name: name,
          visibility: attrs.visibility,
          creator_id: creator.id,
          tick_interval: attrs.tick_interval,
          created_at: now,
          settings: settings
        )

      {:ok, game} = Game.add_player(game, creator.id, creator.nickname, now)
      Storage.save_game(game)
      Lobby.put(game)
      {:ok, game}
    end
  end

  defp check_not_banned(player_id) do
    if Bans.banned?(player_id), do: {:error, :banned}, else: :ok
  end

  defp check_name(name) do
    if String.length(name) in 3..40, do: :ok, else: {:error, :invalid_name}
  end

  defp check_visibility(visibility) do
    if visibility in [:public, :private], do: :ok, else: {:error, :invalid_visibility}
  end

  defp check_tick_interval(interval) do
    if interval in @tick_intervals, do: :ok, else: {:error, :invalid_tick_interval}
  end

  @doc "The current game of a table."
  @spec get(String.t()) :: {:ok, Game.t()} | {:error, :not_found}
  def get(id), do: call(id, :get)

  @doc """
  Subscribes the calling process to the table's updates and keeps the table awake
  for as long as the caller lives. Returns the current game.
  """
  @spec watch(String.t()) :: {:ok, Game.t()} | {:error, :not_found}
  def watch(id) do
    # Subscribe first, so no update can slip through between reading and subscribing.
    if Storage.valid_id?(id), do: Phoenix.PubSub.subscribe(Hextank.PubSub, "table:#{id}")
    call(id, :watch)
  end

  @doc "Joins a table that hasn't started yet. Banned players can't."
  def join(id, player_id, name) do
    with :ok <- check_not_banned(player_id), do: call(id, {:join, player_id, name})
  end

  @doc "Leaves a table that hasn't started yet."
  def leave(id, player_id), do: call(id, {:leave, player_id})

  @doc "Starts the game (creator only)."
  def start(id, player_id), do: call(id, {:start, player_id})

  @doc "A player acts. See `Hextank.Game.act/4` for the actions."
  def act(id, player_id, action), do: call(id, {:act, player_id, action})

  @doc "Freezes a banned player's place at a table (see `Hextank.Game.freeze/3`)."
  def freeze(id, player_id), do: call(id, {:freeze, player_id})

  @doc """
  Deletes a table: its files, its lobby summary and its process. Pages showing it
  get `:table_deleted`. For the admin page; there is no undo.
  """
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(id), do: call(id, :delete)

  @doc "Public tables waiting for players or running, newest first."
  defdelegate list_public(), to: Lobby

  @doc "Every table the player is in, newest first."
  defdelegate list_for_player(player_id), to: Lobby

  ## Finding or starting the table process

  # A table can stop itself (idle) just as a request reaches it. Then the call exits
  # with :noproc or :normal, and we simply try again: the table starts from disk.
  # The pause gives the Registry time to forget the stopped process: it does so a
  # moment after the process exits, not at the same instant.
  defp call(id, message, attempts \\ 5) do
    with {:ok, pid} <- ensure_started(id) do
      try do
        GenServer.call(pid, message)
      catch
        :exit, {reason, {GenServer, :call, _}}
        when reason in [:noproc, :normal] and attempts > 1 ->
          Process.sleep(10)
          call(id, message, attempts - 1)
      end
    end
  end

  defp ensure_started(id) do
    if Storage.valid_id?(id), do: lookup_or_start(id), else: {:error, :not_found}
  end

  defp lookup_or_start(id) do
    case Registry.lookup(Hextank.Tables.Registry, id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(Hextank.Tables.Supervisor, {Table, id}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          :ignore -> {:error, :not_found}
        end
    end
  end
end
