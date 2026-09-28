defmodule HextankWeb.AdminLiveTest do
  # Not async: changes the admin config and uses the table registry.
  use HextankWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hextank.{Storage, Tables}

  @attrs %{name: "Admin table", visibility: :public, tick_interval: 86_400}

  setup %{conn: conn} do
    {conn, admin} = log_in_new_player(conn, "Boss")
    Application.put_env(:hextank, :admin_player_ids, [admin.id])
    on_exit(fn -> Application.put_env(:hextank, :admin_player_ids, []) end)
    %{conn: conn, admin: admin}
  end

  test "players who aren't admins are sent back to the lobby" do
    {conn, _ana} = log_in_new_player(build_conn(), "Ana")

    assert {:error, {:redirect, %{to: "/", flash: %{"error" => "That page is for admins only."}}}} =
             live(conn, ~p"/admin")

    {:ok, _view, html} = live(conn, ~p"/")
    refute html =~ ~s(id="admin-link")
  end

  test "an admin sees the statistics and a link in the header", %{conn: conn, admin: admin} do
    {:ok, game} = Tables.create_table(admin, @attrs)
    :ok = Storage.append_chat(game.id, %{text: "hello"})

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#admin-link")
    assert has_element?(view, "#stats-tables")
    assert has_element?(view, "#day-chart")
    assert has_element?(view, "#table-#{game.id}", "Admin table")
  end

  test "an admin deletes the selected tables at once", %{conn: conn, admin: admin} do
    {:ok, first} = Tables.create_table(admin, @attrs)
    {:ok, second} = Tables.create_table(admin, @attrs)
    {:ok, kept} = Tables.create_table(admin, @attrs)

    {:ok, view, _html} = live(conn, ~p"/admin")
    assert has_element?(view, "#delete-selected[disabled]")

    view |> form("#tables-form", %{"ids" => [first.id, second.id]}) |> render_change()
    assert has_element?(view, "#delete-selected", "Delete 2 tables")

    view |> element("#delete-selected") |> render_click()

    assert has_element?(view, "#flash-info", "Deleted 2 tables.")
    refute has_element?(view, "#table-#{first.id}")
    refute has_element?(view, "#table-#{second.id}")
    assert has_element?(view, "#table-#{kept.id}")
    assert Storage.load_game(first.id) == {:error, :not_found}
  end

  test "the filter shows one status, and select all takes only what's shown", ctx do
    {:ok, waiting} = Tables.create_table(ctx.admin, @attrs)
    {:ok, running} = Tables.create_table(ctx.admin, @attrs)
    {_bruno_conn, bruno} = log_in_new_player(build_conn(), "Bruno")
    {:ok, _} = Tables.join(running.id, bruno.id, "Bruno")
    {:ok, _} = Tables.start(running.id, ctx.admin.id)

    {:ok, view, _html} = live(ctx.conn, ~p"/admin")
    view |> form("#filter-form", %{"status" => "running"}) |> render_change()

    assert has_element?(view, "#table-#{running.id}")
    refute has_element?(view, "#table-#{waiting.id}")

    view |> element("#select-all") |> render_click()
    view |> element("#delete-selected") |> render_click()

    assert Storage.load_game(running.id) == {:error, :not_found}
    assert {:ok, _game} = Storage.load_game(waiting.id)
  end
end
