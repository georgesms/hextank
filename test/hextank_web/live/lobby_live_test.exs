defmodule HextankWeb.LobbyLiveTest do
  use HextankWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hextank.{Game, Storage, Tables}
  alias Hextank.Tables.Lobby

  setup %{conn: conn} do
    {conn, player} = log_in_new_player(conn)
    %{conn: conn, player: player}
  end

  describe "the rejoin link modal" do
    test "opens by itself right after signing up, and closes for good" do
      conn = post(build_conn(), ~p"/players", %{"player" => %{"nickname" => "Bruno"}})
      {:ok, view, _html} = live(recycle(conn), redirected_to(conn))

      assert has_element?(view, "#welcome-rejoin-modal.modal-open")
      assert view |> element("#welcome-rejoin-modal-link") |> render() =~ "/rejoin/"

      view |> element("#welcome-rejoin-modal-done") |> render_click()
      refute has_element?(view, "#welcome-rejoin-modal")
    end

    test "stays closed on later visits, until the lobby's button opens it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#welcome-rejoin-modal")
      refute has_element?(view, "#rejoin-modal.modal-open")
      assert has_element?(view, "#show-rejoin-link")
      assert view |> element("#rejoin-modal-link") |> render() =~ "/rejoin/"
    end
  end

  test "the info button in the header opens the rules", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#rules-button[popovertarget=rules]")
    assert has_element?(view, "#rules[popover]", "How to play")
    assert has_element?(view, "#rules", "The last tank standing wins")
  end

  test "creating a table opens its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, _table_view, html} =
      view
      |> form("#new-table-form", table: %{name: "Friday tanks", visibility: "private"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Friday tanks"
  end

  test "the chosen settings are saved and shown in the waiting room",
       %{conn: conn, player: player} do
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, table_view, _html} =
      view
      |> form("#new-table-form",
        table: %{
          name: "Custom",
          board_radius: "7",
          obstacle_percent: "0",
          start_hp: "5",
          start_ap: "3",
          max_range: "none"
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    [summary] = Tables.list_for_player(player.id)
    {:ok, game} = Tables.get(summary.id)

    assert %{
             board_radius: 7,
             obstacle_percent: 0,
             start_hp: 5,
             start_range: 2,
             start_ap: 3,
             max_range: :none
           } =
             game.settings

    assert has_element?(table_view, "#table-settings")
  end

  test "a bad table name shows an error and creates nothing", %{conn: conn, player: player} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> form("#new-table-form", table: %{name: "x"}) |> render_submit()

    assert has_element?(view, "#flash-error")
    assert Tables.list_for_player(player.id) == []
  end

  test "lists your tables and other people's public tables, not their private ones",
       %{conn: conn, player: player} do
    attrs = %{name: "Someone's table", tick_interval: 86_400}
    {:ok, other} = Hextank.Players.create("Zé")
    {:ok, mine} = Tables.create_table(player, Map.put(attrs, :visibility, :private))
    {:ok, open} = Tables.create_table(other, Map.put(attrs, :visibility, :public))

    {:ok, hidden} =
      Tables.create_table(other, Map.put(attrs, :visibility, :private))

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#my-tables #table-card-#{mine.id}")
    assert has_element?(view, "#open-tables #table-card-#{open.id}")
    refute has_element?(view, "#table-card-#{hidden.id}")
  end

  test "your tables show how many chat messages you haven't read", %{conn: conn, player: player} do
    {:ok, bruno} = Hextank.Players.create("Bruno")

    {:ok, game} =
      Tables.create_table(player, %{name: "Chatty", visibility: :public, tick_interval: 86_400})

    {:ok, game} = Tables.join(game.id, bruno.id, "Bruno")
    {:ok, _} = Hextank.Chat.send_message(game, bruno, "psst")
    {:ok, _} = Hextank.Chat.send_message(game, bruno, "psst again")

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#unread-#{game.id}", "2")
  end

  describe "table cards" do
    # Ana's table with Bruno and Carla, started `days` days ago. `change` adjusts the
    # game before it's saved. No table process runs, so the test saves it directly.
    defp started_table(player, days, change) do
      now = DateTime.utc_now()

      {:ok, game} =
        Tables.create_table(player, %{name: "Cards", visibility: :public, tick_interval: 86_400})

      {:ok, game} = Game.add_player(game, "bruno", "Bruno", now)
      {:ok, game} = Game.add_player(game, "carla", "Carla", now)
      {:ok, game} = Game.start(game, player.id, DateTime.add(now, -days * 86_400, :second), 1)
      game = change.(game)
      :ok = Storage.save_game(game)
      Lobby.put(game)
      game
    end

    defp destroy(game, player_id) do
      tanks = Map.update!(game.tanks, player_id, &%{&1 | hp: 0, position: nil})
      %{game | tanks: tanks}
    end

    test "a table that hasn't started shows how many players joined", %{conn: conn} do
      {:ok, other} = Hextank.Players.create("Zé")

      {:ok, game} =
        Tables.create_table(other, %{name: "Soon", visibility: :public, tick_interval: 60})

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#table-card-#{game.id}", "Not started")
      assert has_element?(view, "#table-status-#{game.id}", "1 of 20 players")
    end

    test "a running table shows who's alive and how long ago it started",
         %{conn: conn, player: player} do
      game = started_table(player, 3, &destroy(&1, "carla"))

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#table-card-#{game.id}", "Running")
      assert has_element?(view, "#table-status-#{game.id}", "2 alive")
      assert has_element?(view, "#table-status-#{game.id}", "1 destroyed")
      assert has_element?(view, "#table-status-#{game.id}", "Started 3 days ago")
    end

    test "a finished table shows the winner and when it will be deleted",
         %{conn: conn, player: player} do
      game =
        started_table(player, 10, fn game ->
          game = game |> destroy("bruno") |> destroy("carla")
          ended_at = DateTime.add(DateTime.utc_now(), -2 * 86_400, :second)
          %{game | status: :finished, winner_id: player.id, finished_at: ended_at}
        end)

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#table-card-#{game.id}", "Finished")
      assert has_element?(view, "#table-status-#{game.id}", "Ana won")
      assert has_element?(view, "#table-status-#{game.id}", "Deleted in 5 days")
    end
  end
end
