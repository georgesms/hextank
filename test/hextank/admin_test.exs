defmodule Hextank.AdminTest do
  # Not async: changes the admin config and uses the table registry.
  use ExUnit.Case, async: false

  alias Hextank.{Admin, Player, Storage, Tables}

  @now ~U[2026-09-28 12:00:00Z]

  defp summary(fields) do
    Map.merge(
      %{
        id: Storage.new_id(),
        name: "A table",
        visibility: :public,
        status: :running,
        player_ids: ["ana", "bruno"],
        created_at: @now,
        action_counts: %{},
        chat_bytes: 0
      },
      Map.new(fields)
    )
  end

  describe "admin?/1" do
    setup do
      on_exit(fn -> Application.put_env(:hextank, :admin_player_ids, []) end)
    end

    test "only players listed in the config" do
      Application.put_env(:hextank, :admin_player_ids, ["boss-id-1"])

      assert Admin.admin?(%Player{id: "boss-id-1", nickname: "Boss", created_at: @now})
      refute Admin.admin?(%Player{id: "ana-id-12", nickname: "Ana", created_at: @now})
      refute Admin.admin?(nil)
    end
  end

  describe "table_stats/2" do
    test "counts tables, players, actions and chat" do
      tables = [
        summary(status: :lobby, player_ids: ["ana"], chat_bytes: 120),
        summary(
          visibility: :private,
          created_at: DateTime.add(@now, -3 * 86_400),
          action_counts: %{move: 4, shoot: 1}
        ),
        summary(
          status: :finished,
          created_at: DateTime.add(@now, -40 * 86_400),
          player_ids: ["carla", "ana"],
          action_counts: %{move: 2, vote: 3},
          chat_bytes: 80
        )
      ]

      stats = Admin.table_stats(tables, @now)

      assert stats.total == 3
      assert stats.by_status == %{lobby: 1, running: 1, finished: 1}
      assert stats.public == 2

      assert {stats.created_last_day, stats.created_last_week, stats.created_last_month} ==
               {1, 2, 2}

      assert stats.seated_players == 3
      assert stats.actions == %{move: 6, shoot: 1, vote: 3}
      assert {stats.chat_bytes, stats.tables_with_chat} == {200, 2}
    end

    test "counts the tables created per day, for the last 14 days" do
      tables = [summary([]), summary([]), summary(created_at: DateTime.add(@now, -86_400))]

      per_day = Admin.table_stats(tables, @now).created_per_day

      assert length(per_day) == 14
      assert List.last(per_day) == {~D[2026-09-28], 2}
      assert Enum.at(per_day, -2) == {~D[2026-09-27], 1}
      assert hd(per_day) == {~D[2026-09-15], 0}
    end

    test "works without any table" do
      assert %{total: 0, actions: %{}, chat_bytes: 0} = Admin.table_stats([], @now)
    end
  end

  describe "tables/0 and delete_tables/1" do
    test "lists tables with their chat size, and deletes several at once" do
      ana = %Player{id: Storage.new_id(), nickname: "Ana", created_at: @now}
      attrs = %{name: "Admin test", visibility: :public, tick_interval: 86_400}
      {:ok, first} = Tables.create_table(ana, attrs)
      {:ok, second} = Tables.create_table(ana, attrs)
      :ok = Storage.append_chat(first.id, %{text: "hello"})

      listed = Map.new(Admin.tables(), &{&1.id, &1})
      assert listed[first.id].chat_bytes > 0
      assert listed[second.id].chat_bytes == 0

      assert Admin.delete_tables([first.id, second.id, Storage.new_id()]) == 2
      refute Enum.any?(Admin.tables(), &(&1.id in [first.id, second.id]))
    end
  end

  test "server_stats/0 reports players, bans, awake tables and memory" do
    assert %{players: players, banned: banned, awake_tables: awake, memory_bytes: memory} =
             Admin.server_stats()

    assert Enum.all?([players, banned, awake], &is_integer/1)
    assert memory > 0
  end
end
