defmodule HextankWeb.LobbyLiveTest do
  use HextankWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hextank.Tables

  setup %{conn: conn} do
    {conn, player} = log_in_new_player(conn)
    %{conn: conn, player: player}
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

  test "a bad table name shows an error and creates nothing", %{conn: conn, player: player} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> form("#new-table-form", table: %{name: "x"}) |> render_submit()

    assert has_element?(view, "#flash-error")
    assert Tables.list_for_player(player.id) == []
  end

  test "lists your tables and other people's public tables, not their private ones",
       %{conn: conn, player: player} do
    attrs = %{name: "Someone's table", tick_interval: 86_400}
    {:ok, mine} = Tables.create_table(player.id, "Ana", Map.put(attrs, :visibility, :private))
    {:ok, open} = Tables.create_table("other-player", "Zé", Map.put(attrs, :visibility, :public))

    {:ok, hidden} =
      Tables.create_table("other-player", "Zé", Map.put(attrs, :visibility, :private))

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#my-tables #table-card-#{mine.id}")
    assert has_element?(view, "#open-tables #table-card-#{open.id}")
    refute has_element?(view, "#table-card-#{hidden.id}")
  end
end
