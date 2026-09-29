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

  defp cell_id(hex), do: "cell_#{hex.q}_#{hex.r}_#{hex.s}"

  # An open cell whose shortest path from the player's tank is `length` cells long.
  defp cell_at_path_length(game, player_id, length) do
    game.board
    |> Hextank.Board.open_cells()
    |> Enum.find(fn hex ->
      match?({:ok, path} when length(path) == length, Game.path(game, player_id, hex))
    end)
  end

  # Puts the two tanks on neighbouring open cells.
  defp side_by_side(game, first_id, second_id) do
    open = Hextank.Board.open_cells(game.board)

    {a, b} =
      Enum.find_value(open, fn hex ->
        neighbor = Enum.find(Hextank.Hex.neighbors(hex), &(&1 in open))
        neighbor && {hex, neighbor}
      end)

    tanks =
      game.tanks
      |> Map.update!(first_id, &%{&1 | position: a})
      |> Map.update!(second_id, &%{&1 | position: b})

    %{game | tanks: tanks}
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

  test "a deleted table sends its pages back to the lobby", ctx do
    game = running_game(ctx.ana, ctx.bruno, 1)
    {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

    :ok = Tables.delete(game.id)

    assert_redirect(view, "/")
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

      assert has_element?(view, "#my-ap[aria-label='2 AP']", "⚡⚡")

      view |> element("#action-upgrade") |> render_click()

      assert has_element?(view, "#my-ap[aria-label='1 AP']", "⚡")
      assert has_element?(view, "#my-range[aria-label='range 3']", "🎯🎯🎯")
    end

    test "a click shows the path and its cost, a second click drives there", ctx do
      game = running_game(ctx.ana, ctx.bruno, 3)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      target = cell_at_path_length(game, ctx.ana.id, 2)

      view |> element("##{cell_id(target)}") |> render_click()
      assert has_element?(view, "#selection-info", "2 cells")
      assert has_element?(view, "#highlight-path-#{cell_id(target)}")

      view |> element("##{cell_id(target)}") |> render_click()

      {:ok, game} = Tables.get(game.id)
      assert %{position: ^target, ap: 1} = Game.tank(game, ctx.ana.id)
      refute has_element?(view, "#highlights-path")
    end

    test "a path longer than your AP is shown but not driven", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      target = cell_at_path_length(game, ctx.ana.id, 2)

      view |> element("##{cell_id(target)}") |> render_click()
      assert has_element?(view, "#selection-info", "you need 2 AP and have 1")
      assert has_element?(view, "#highlights-path_too_far")

      view |> element("##{cell_id(target)}") |> render_click()
      assert has_element?(view, "#flash-error")
      {:ok, game} = Tables.get(game.id)
      refute Game.tank(game, ctx.ana.id).position == target
    end

    test "a click on an enemy says it's out of range", ctx do
      # Tanks start at least 3 cells apart, and the range is 2.
      game = running_game(ctx.ana, ctx.bruno, 1)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      view |> element("#tank-#{ctx.bruno.id}") |> render_click()

      assert has_element?(view, "#selection-info", "out of your range")
      assert has_element?(view, "#highlights-target_out_of_range")
      assert has_element?(view, "#action-shoot[disabled]")
    end

    test "an enemy within range: a click says so, a double-click shoots", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1, &side_by_side(&1, ctx.ana.id, ctx.bruno.id))
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      view |> element("#tank-#{ctx.bruno.id}") |> render_click()
      assert has_element?(view, "#selection-info", "within your range")

      render_hook(view, "tank_double", %{"player" => ctx.bruno.id})

      {:ok, game} = Tables.get(game.id)
      assert Game.tank(game, ctx.bruno.id).hp == 2
    end

    test "a shot is animated on every open board, but not what happened before", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1, &side_by_side(&1, ctx.ana.id, ctx.bruno.id))
      {:ok, ana_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      {:ok, bruno_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")
      refute has_element?(ana_view, "#effects [data-effect]")

      render_hook(ana_view, "tank_double", %{"player" => ctx.bruno.id})

      assert has_element?(ana_view, "#effects [data-effect=shot]")
      assert has_element?(bruno_view, "#effects [data-effect=shot]")

      # Opening the board afterwards shows the result, not the animation.
      {:ok, late_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")
      refute has_element?(late_view, "#effects [data-effect]")
    end

    test "the last shot shows the winner above the board, with a crown", ctx do
      game =
        running_game(ctx.ana, ctx.bruno, 1, fn game ->
          game = side_by_side(game, ctx.ana.id, ctx.bruno.id)
          %{game | tanks: Map.update!(game.tanks, ctx.bruno.id, &%{&1 | hp: 1})}
        end)

      {:ok, ana_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      {:ok, bruno_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")
      refute has_element?(ana_view, "#winner-banner")

      render_hook(ana_view, "tank_double", %{"player" => ctx.bruno.id})

      assert has_element?(ana_view, "#winner-banner", "You won!")
      assert has_element?(ana_view, "#winner-banner", "Deleted in 7 days")
      assert has_element?(bruno_view, "#winner-banner", "Ana won!")
      assert has_element?(bruno_view, "#tank-#{ctx.ana.id} .fx-crown")
      assert has_element?(bruno_view, "#effects [data-effect=destroyed]")
    end

    test "the panel can make a double-click on an enemy give AP instead", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1, &side_by_side(&1, ctx.ana.id, ctx.bruno.id))
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      assert has_element?(view, "#double-click-shoot[aria-pressed=true]")

      view |> element("#double-click-give_ap") |> render_click()
      assert has_element?(view, "#double-click-give_ap[aria-pressed=true]")

      view |> element("#tank-#{ctx.bruno.id}") |> render_click()
      assert has_element?(view, "#selection-info", "Double-click to give 1 AP")

      render_hook(view, "tank_double", %{"player" => ctx.bruno.id})

      {:ok, game} = Tables.get(game.id)
      assert %{ap: 2, hp: 3} = Game.tank(game, ctx.bruno.id)
    end

    test "the panel always shows every action, enabled when it fits the selection", ctx do
      game = running_game(ctx.ana, ctx.bruno, 2, &side_by_side(&1, ctx.ana.id, ctx.bruno.id))
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      for id <- ~w(action-move action-shoot action-give) do
        assert has_element?(view, "##{id}[disabled]")
      end

      refute has_element?(view, "#action-upgrade[disabled]")

      # Bruno is right next to Ana: both tank actions fit, moving doesn't.
      view |> element("#tank-#{ctx.bruno.id}") |> render_click()
      refute has_element?(view, "#action-shoot[disabled]")
      assert has_element?(view, "#action-move[disabled]")

      view |> element("#action-give") |> render_click()

      {:ok, game} = Tables.get(game.id)
      assert %{ap: 3, hp: 3} = Game.tank(game, ctx.bruno.id)
    end

    test "the Move here button drives to the selected cell", ctx do
      game = running_game(ctx.ana, ctx.bruno, 2)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      target = cell_at_path_length(game, ctx.ana.id, 2)

      view |> element("##{cell_id(target)}") |> render_click()
      view |> element("#action-move") |> render_click()

      {:ok, game} = Tables.get(game.id)
      assert %{position: ^target, ap: 0} = Game.tank(game, ctx.ana.id)
    end

    test "your own tank: a click shows your range, a double-click adds 1", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      view |> element("#tank-#{ctx.ana.id}") |> render_click()
      assert has_element?(view, "#highlights-range")

      render_hook(view, "tank_double", %{"player" => ctx.ana.id})
      assert has_element?(view, "#my-range[aria-label='range 3']")
    end

    test "every tank carries its stats for the hover tooltip", ctx do
      game = running_game(ctx.ana, ctx.bruno, 2)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      assert view |> element("#tank-#{ctx.bruno.id}") |> render() =~ "❤️❤️❤️ · ⚡⚡ · 🎯🎯"
    end

    test "without AP, acting fails with a message", ctx do
      game = running_game(ctx.ana, ctx.bruno, 0)
      {:ok, view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")

      assert has_element?(view, "#action-upgrade[disabled]")
      render_hook(view, "tank_double", %{"player" => ctx.ana.id})
      assert has_element?(view, "#flash-error")
    end

    test "other players see changes as they happen", ctx do
      game = running_game(ctx.ana, ctx.bruno, 1)
      {:ok, ana_view, _html} = live(ctx.ana_conn, ~p"/tables/#{game.id}")
      {:ok, bruno_view, _html} = live(ctx.bruno_conn, ~p"/tables/#{game.id}")

      assert has_element?(bruno_view, "#player-#{ctx.ana.id} [aria-label='1 AP']")
      ana_view |> element("#action-upgrade") |> render_click()
      assert has_element?(bruno_view, "#player-#{ctx.ana.id} [aria-label='0 AP']", "0 × ⚡")
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
