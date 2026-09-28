defmodule HextankWeb.TableLiveTest do
  # Not async: tables share the registry, the lobby and the idle timeout.
  use HextankWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hextank.{Game, Storage, Tables}

  @attrs %{name: "Live table", visibility: :public, tick_interval: 86_400}

  setup %{conn: conn} do
    {ana_conn, ana} = log_in_new_player(conn, "Ana")
    {bruno_conn, bruno} = log_in_new_player(build_conn(), "Bruno")
    %{ana_conn: ana_conn, ana: ana, bruno_conn: bruno_conn, bruno: bruno}
  end

  # A running game between Ana and Bruno that started `days` days ago, so every tank
  # has `days` AP. `change` can adjust the game before it's saved.
  defp running_game(ana, bruno, days, change \\ & &1) do
    {:ok, game} = Tables.create_table(ana, @attrs)
    {:ok, _} = Tables.join(game.id, bruno.id, "Bruno")
    {:ok, game} = Tables.start(game.id, ana.id)
    wait_until_asleep(game.id)

    game = %{game | started_at: DateTime.add(game.started_at, -days * 86_400, :second)}
    :ok = Storage.save_game(change.(game))
    game
  end

  defp wait_until_asleep(id) do
    case Registry.lookup(Hextank.Tables.Registry, id) do
      [{pid, _}] ->
        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000

      [] ->
        :ok
    end
  end

  test "an unknown table sends you back to the lobby", %{ana_conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/tables/#{Storage.new_id()}")
  end

  describe "before the start" do
    test "players join, and the creator starts the game", ctx do
      {:ok, game} = Tables.create_table(ctx.ana, @attrs)

      {:ok, bruno_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")
      bruno_view |> element("#join-table") |> render_click()
      assert has_element?(bruno_view, "#player-#{ctx.bruno.id}")
      refute has_element?(bruno_view, "#start-game")

      {:ok, ana_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      ana_view |> element("#start-game") |> render_click()
      assert has_element?(ana_view, "#board")

      # Bruno's page updates by itself.
      assert has_element?(bruno_view, "#board")
      assert has_element?(bruno_view, "#tank-panel")
    end
  end

  describe "during the game" do
    test "upgrading the range spends 1 AP", ctx do
      game = running_game(ctx.ana, ctx.bruno, 2)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      assert view |> element("#my-ap") |> render() =~ "2"

      view |> element("#action-upgrade") |> render_click()

      assert view |> element("#my-ap") |> render() =~ "1"
      assert view |> element("#my-range") |> render() =~ "3"
    end

    test "moving: pick the action, then a highlighted cell", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      view |> element("#action-move") |> render_click()
      [target | _] = Game.move_targets(game, ctx.ana.id)

      view
      |> element("#highlight-move-cell_#{target.q}_#{target.r}_#{target.s}")
      |> render_click()

      {:ok, game} = Tables.get(game.id)
      assert Game.tank(game, ctx.ana.id).position == target
      refute has_element?(view, "#mode-hint")
    end

    test "without AP, the actions are disabled", ctx do
      game = running_game(ctx.ana, ctx.bruno, 0)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      assert has_element?(view, "#action-upgrade[disabled]")
      assert has_element?(view, "#action-move[disabled]")
    end

    test "other players see changes as they happen", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1)
      {:ok, ana_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      {:ok, bruno_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")

      assert has_element?(bruno_view, "#player-#{ctx.ana.id}", "1 AP")
      ana_view |> element("#action-upgrade") |> render_click()
      assert has_element?(bruno_view, "#player-#{ctx.ana.id}", "0 AP")
    end

    test "a ghost votes to give a living tank 1 AP", ctx do
      {carla_conn, carla} = log_in_new_player(build_conn(), "Carla")

      {:ok, game} = Tables.create_table(ctx.ana, @attrs)
      {:ok, _} = Tables.join(game.id, ctx.bruno.id, "Bruno")
      {:ok, _} = Tables.join(game.id, carla.id, "Carla")
      {:ok, game} = Tables.start(game.id, ctx.ana.id)
      wait_until_asleep(game.id)

      # Carla was destroyed and has her vote.
      carla_tank = %{Game.tank(game, carla.id) | hp: 0, position: nil, has_vote: true}
      :ok = Storage.save_game(%{game | tanks: Map.put(game.tanks, carla.id, carla_tank)})

      {:ok, view, _html} = live(carla_conn, ~p"/tables/#{game.id}")
      assert has_element?(view, "#ghost-panel")

      view |> element("#vote-#{ctx.bruno.id}") |> render_click()

      {:ok, game} = Tables.get(game.id)
      assert Game.tank(game, ctx.bruno.id).ap == 1
      refute has_element?(view, "#vote-#{ctx.bruno.id}")
    end
  end

  describe "chat" do
    # Ana and Bruno at a table that hasn't started: chat works before the game too.
    defp chat_table(ctx) do
      {:ok, game} = Tables.create_table(ctx.ana, @attrs)
      {:ok, _} = Tables.join(game.id, ctx.bruno.id, "Bruno")
      game
    end

    defp send_chat(view, text, to \\ "") do
      view |> form("#chat-form", chat: %{text: text, to: to}) |> render_submit()
    end

    test "a message reaches everyone at the table", ctx do
      game = chat_table(ctx)
      {:ok, ana_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      {:ok, bruno_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")

      send_chat(ana_view, "Truce until Friday?")

      assert has_element?(bruno_view, "#messages", "Truce until Friday?")
      assert has_element?(ana_view, "#messages", "Truce until Friday?")
    end

    test "a private message never reaches a third player", ctx do
      {carla_conn, carla} = log_in_new_player(build_conn(), "Carla")
      game = chat_table(ctx)
      {:ok, _} = Tables.join(game.id, carla.id, "Carla")

      {:ok, ana_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      {:ok, bruno_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")
      {:ok, carla_view, _html} = live(carla_conn, ~p"/tables/#{game.id}")

      send_chat(ana_view, "Let's betray Carla", ctx.bruno.id)

      assert has_element?(bruno_view, "#messages", "Let's betray Carla")
      refute has_element?(carla_view, "#messages", "Let's betray Carla")

      # Not after a reload either.
      {:ok, carla_view, _html} = live(carla_conn, ~p"/tables/#{game.id}")
      refute has_element?(carla_view, "#messages", "Let's betray Carla")
    end

    test "a prohibited word blocks the message and warns", ctx do
      game = chat_table(ctx)
      {:ok, ana_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      {:ok, bruno_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")

      send_chat(ana_view, "you badword")

      assert has_element?(ana_view, "#flash-error", "Warning 1 of 2")
      refute has_element?(bruno_view, "#messages", "badword")
    end

    test "at most 5 messages in 10 seconds", ctx do
      game = chat_table(ctx)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      for n <- 1..5, do: send_chat(view, "message #{n}")
      send_chat(view, "one too many")

      assert has_element?(view, "#flash-error")
      refute has_element?(view, "#messages", "one too many")
    end
  end

  describe "bans" do
    test "a ban closes every open page of the player at once", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1)
      {:ok, table_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      {:ok, lobby_view, _html} = live(ctx.ana_conn, ~p"/")

      :ok = Hextank.Players.ban(ctx.ana)

      assert_redirect(table_view, "/banned")
      assert_redirect(lobby_view, "/banned")
    end

    test "a banned player can't open any page but /banned", ctx do
      :ok = Hextank.Players.ban(ctx.ana)

      assert redirected_to(get(ctx.ana_conn, ~p"/")) == "/banned"
      assert html_response(get(ctx.ana_conn, ~p"/banned"), 200) =~ ~s(id="banned")
    end
  end
end
