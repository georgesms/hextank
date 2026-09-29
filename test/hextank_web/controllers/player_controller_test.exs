defmodule HextankWeb.PlayerControllerTest do
  use HextankWeb.ConnCase, async: true

  alias Hextank.Players
  alias HextankWeb.RejoinLink

  describe "visitors without a player" do
    test "are sent to the welcome page, remembering where they wanted to go", %{conn: conn} do
      conn = get(conn, ~p"/tables/abcdefgh1234")
      assert redirected_to(conn) == ~p"/welcome?#{[return_to: "/tables/abcdefgh1234"]}"
    end

    test "see the nickname form", %{conn: conn} do
      conn = get(conn, ~p"/welcome")
      assert html_response(conn, 200) =~ ~s(id="welcome-form")
    end
  end

  describe "POST /players" do
    test "creates a player, logs them in and goes back where they wanted", %{conn: conn} do
      conn =
        post(conn, ~p"/players", %{
          "player" => %{"nickname" => "Bruno"},
          "return_to" => "/tables/abcdefgh1234"
        })

      assert redirected_to(conn) == "/tables/abcdefgh1234"
      assert {:ok, player} = Players.get(get_session(conn, "player_id"))
      assert player.nickname == "Bruno"
    end

    test "never redirects to another site", %{conn: conn} do
      for return_to <- ["//evil.example", "https://evil.example", "/\\evil.example"] do
        conn =
          post(conn, ~p"/players", %{
            "player" => %{"nickname" => "Bruno"},
            "return_to" => return_to
          })

        assert redirected_to(conn) == "/"
      end
    end

    test "shows the form again for a bad nickname", %{conn: conn} do
      conn = post(conn, ~p"/players", %{"player" => %{"nickname" => "<x>"}})

      assert html_response(conn, 200) =~ ~s(id="welcome-form")
      assert get_session(conn, "player_id") == nil
    end
  end

  describe "the session cookie" do
    test "lasts a year from the last page load, not from the login", %{conn: conn} do
      year = 365 * 24 * 60 * 60

      conn = post(conn, ~p"/players", %{"player" => %{"nickname" => "Bruno"}})
      assert conn.resp_cookies["_hextank_key"].max_age == year

      # Every later page sends the cookie again, so the year starts over.
      conn = get(recycle(conn), ~p"/")
      assert conn.resp_cookies["_hextank_key"].max_age == year
      assert get_session(conn, "player_id")
    end
  end

  describe "rejoin links" do
    test "log you in as the link's player", %{conn: conn} do
      {:ok, player} = Players.create("Carla")

      conn = get(conn, ~p"/rejoin/#{RejoinLink.token(player)}")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, "player_id") == player.id
    end

    test "stop working once the link is reset", %{conn: conn} do
      {:ok, player} = Players.create("Carla")
      old_token = RejoinLink.token(player)
      {:ok, _player} = Players.reset_rejoin_link(player)

      conn = get(conn, ~p"/rejoin/#{old_token}")

      assert redirected_to(conn) == ~p"/welcome"
      assert get_session(conn, "player_id") == nil
    end

    test "reject made-up tokens", %{conn: conn} do
      conn = get(conn, ~p"/rejoin/not-a-real-token")
      assert redirected_to(conn) == ~p"/welcome"
    end
  end

  describe "language" do
    test "follows the browser, and the switch overrides it", %{conn: conn} do
      conn = conn |> put_req_header("accept-language", "pt-BR,pt;q=0.9") |> get(~p"/welcome")
      assert html_response(conn, 200) =~ ~s(lang="pt-BR")

      conn = get(recycle(conn), ~p"/welcome?locale=en")
      assert html_response(conn, 200) =~ ~s(lang="en")
    end
  end
end
