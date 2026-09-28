defmodule Hextank.Admin do
  @moduledoc """
  What the admin page needs: who is an admin, statistics, and deleting tables in
  bulk.

  Admins are the players whose ids are in the `:admin_player_ids` config, set from
  the `ADMIN_PLAYER_IDS` environment variable (comma-separated). Players see their
  id on their account page.

  Statistics are worked out only when the admin page asks, from what the app keeps
  anyway: the lobby summaries (in memory), the size of each chat file (a quick
  `stat`: the files are never read) and a few numbers from the BEAM. Nothing else
  is stored for them, apart from the action counts in each `%Game{}`. So they cover
  the tables that exist now: an expired or deleted table no longer counts.
  """

  alias Hextank.{Player, Storage, Tables}
  alias Hextank.Players.Bans
  alias Hextank.Tables.Lobby

  @day 86_400
  @chart_days 14

  @doc "Whether the player may open the admin page."
  @spec admin?(Player.t() | nil) :: boolean()
  def admin?(%Player{id: id}), do: id in Application.get_env(:hextank, :admin_player_ids, [])
  def admin?(_player), do: false

  @doc "Every table's lobby summary, newest first, with its chat size in bytes."
  @spec tables() :: [map()]
  def tables do
    for summary <- Lobby.list_all() do
      Map.put(summary, :chat_bytes, Storage.chat_size(summary.id))
    end
  end

  @doc """
  Statistics about the tables from `tables/0`, as of `now`: how many there are, of
  which kind, how many were created lately (and per day for the last #{@chart_days}
  days), the actions used and the chat volume.
  """
  @spec table_stats([map()], DateTime.t()) :: map()
  def table_stats(tables, now) do
    %{
      total: length(tables),
      by_status:
        Map.merge(%{lobby: 0, running: 0, finished: 0}, Enum.frequencies_by(tables, & &1.status)),
      public: Enum.count(tables, &(&1.visibility == :public)),
      created_last_day: Enum.count(tables, &created_within?(&1, now, 1)),
      created_last_week: Enum.count(tables, &created_within?(&1, now, 7)),
      created_last_month: Enum.count(tables, &created_within?(&1, now, 30)),
      created_per_day: created_per_day(tables, now),
      seated_players: tables |> Enum.flat_map(& &1.player_ids) |> Enum.uniq() |> length(),
      actions: sum_actions(tables),
      chat_bytes: tables |> Enum.map(& &1.chat_bytes) |> Enum.sum(),
      tables_with_chat: Enum.count(tables, &(&1.chat_bytes > 0))
    }
  end

  defp created_within?(table, now, days) do
    DateTime.diff(now, table.created_at, :second) <= days * @day
  end

  # [{date, count}] for the last days, oldest first, today included.
  defp created_per_day(tables, now) do
    counts = Enum.frequencies_by(tables, &DateTime.to_date(&1.created_at))
    today = DateTime.to_date(now)

    for days_ago <- (@chart_days - 1)..0//-1 do
      date = Date.add(today, -days_ago)
      {date, Map.get(counts, date, 0)}
    end
  end

  defp sum_actions(tables) do
    Enum.reduce(tables, %{}, fn table, sums ->
      Map.merge(sums, table.action_counts, fn _kind, sum, count -> sum + count end)
    end)
  end

  @doc """
  Numbers about players and the server right now: registered and banned players,
  table processes awake, and the memory the BEAM uses.
  """
  @spec server_stats() :: map()
  def server_stats do
    %{
      players: length(Storage.list_player_ids()),
      banned: Bans.count(),
      awake_tables: DynamicSupervisor.count_children(Hextank.Tables.Supervisor).active,
      memory_bytes: :erlang.memory(:total)
    }
  end

  @doc "Deletes the tables with these ids. Returns how many were deleted."
  @spec delete_tables([String.t()]) :: non_neg_integer()
  def delete_tables(ids), do: Enum.count(ids, &(Tables.delete(&1) == :ok))
end
