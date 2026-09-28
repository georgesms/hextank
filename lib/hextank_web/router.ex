defmodule HextankWeb.Router do
  use HextankWeb, :router

  import HextankWeb.Plugs.CurrentPlayer, only: [require_player: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HextankWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug HextankWeb.Plugs.Locale
    plug HextankWeb.Plugs.CurrentPlayer
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Pages that work without a player.
  scope "/", HextankWeb do
    pipe_through :browser

    get "/welcome", PlayerController, :new
    post "/players", PlayerController, :create
    get "/rejoin/:token", PlayerController, :rejoin
    get "/banned", PlayerController, :banned
  end

  # Pages that need a player: visitors without one go to /welcome first.
  scope "/", HextankWeb do
    pipe_through [:browser, :require_player]

    live_session :player, on_mount: HextankWeb.PlayerHook do
      live "/", LobbyLive
      live "/tables/:id", TableLive
      live "/account", AccountLive
    end

    # Its own live_session, so moving here from a player page goes through the
    # router again. AdminHook lets only admins in.
    live_session :admin, on_mount: [HextankWeb.PlayerHook, HextankWeb.AdminHook] do
      live "/admin", AdminLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", HextankWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:hextank, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HextankWeb.Telemetry
    end
  end
end
