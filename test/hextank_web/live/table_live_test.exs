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
    {:ok, game} = Tables.create_table(ana.id, "Ana", @attrs)
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
      {:ok, game} = Tables.create_table(ctx.ana.id, "Ana", @attrs)

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

      {:ok, game} = Tables.create_table(ctx.ana.id, "Ana", @attrs)
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
end
