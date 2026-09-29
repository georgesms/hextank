defmodule HextankWeb.DormantControllerTest do
  # Not async: tables share the registry and the lobby.
  use HextankWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hextank.Tables

  setup %{conn: conn} do
    {conn, player} = log_in_new_player(conn)
    %{conn: conn, player: player}
  end

  test "a table's dormant page shows the table without starting it", %{conn: conn, player: player} do
    {:ok, game} =
      Tables.create_table(player, %{name: "Sleepy", visibility: :public, tick_interval: 60})

    html = conn |> get(~p"/tables/#{game.id}/dormant") |> html_response(200)

    assert html =~ "Sleepy"
    assert html =~ ~s(href="/tables/#{game.id}")
    # No app.js: no LiveView, no websocket keeping the machine awake.
    refute html =~ "app.js"
    # Only the lobby's summary was read: the table's process never started.
    assert Registry.lookup(Hextank.Tables.Registry, game.id) == []
  end

  test "an unknown table's dormant page leads back to the lobby", %{conn: conn} do
    html = conn |> get(~p"/tables/#{Hextank.Storage.new_id()}/dormant") |> html_response(200)

    assert html =~ ~s(id="dormant-back")
    assert html =~ ~s(href="/")
  end

  test "the lobby's dormant page leads back to the lobby, without app.js", %{conn: conn} do
    html = conn |> get(~p"/dormant") |> html_response(200)

    assert html =~ ~s(href="/")
    refute html =~ "app.js"
  end

  test "every LiveView page says where to go when left alone", %{conn: conn, player: player} do
    {:ok, game} =
      Tables.create_table(player, %{name: "Busy", visibility: :public, tick_interval: 60})

    {:ok, lobby, _html} = live(conn, ~p"/")
    assert has_element?(lobby, "main[data-dormant-url='/dormant']")

    {:ok, account, _html} = live(conn, ~p"/account")
    assert has_element?(account, "main[data-dormant-url='/dormant']")

    {:ok, table, _html} = live(conn, ~p"/tables/#{game.id}")
    assert has_element?(table, "main[data-dormant-url='/tables/#{game.id}/dormant']")
  end
end
