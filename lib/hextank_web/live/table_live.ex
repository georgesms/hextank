defmodule HextankWeb.TableLive do
  @moduledoc """
  The table page: the board, your tank and its actions, the players and the event
  log. It watches the table (see `Hextank.Tables.watch/1`), so every change made by
  anyone arrives as `{:game_updated, game}`.

  Acting works in two steps: pick an action (move, shoot, give AP), then click a
  highlighted cell. Clicking your own tank is a shortcut for "move". Escape cancels.
  No rule is checked here: `Hextank.Game` decides, we only show its answer.
  """

  use HextankWeb, :live_view

  alias Hextank.{Board, Game, Hex, Tables, Tank}
  alias HextankWeb.Messages

  import HextankWeb.GameComponents

  # Action modes chosen with a button. A map, so user input never becomes an atom.
  @modes %{"move" => :move, "shoot" => :shoot, "give_ap" => :give_ap}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # The first (static) render only reads the game; the live connection watches it.
    result = if connected?(socket), do: Tables.watch(id), else: Tables.get(id)

    case result do
      {:ok, game} ->
        if connected?(socket), do: schedule_clock(game)

        socket =
          socket
          |> assign(mode: nil, board_layout: nil, now: DateTime.utc_now())
          |> assign_game(game)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok, socket |> put_flash(:error, Messages.error(:not_found)) |> push_navigate(to: ~p"/")}
    end
  end

  ## Assigns

  defp assign_game(socket, game) do
    socket
    |> assign(:game, game)
    |> assign(:me, Game.tank(game, socket.assigns.current_player.id))
    |> assign(:page_title, game.name)
    |> assign_layout(game)
    |> assign_highlights()
  end

  # The board never changes once the game has started, so its layout is computed
  # only once.
  defp assign_layout(%{assigns: %{board_layout: nil}} = socket, %Game{board: %Board{} = board}) do
    assign(socket, :board_layout, board_layout(board))
  end

  defp assign_layout(socket, _game), do: socket

  # Which cells light up for the current mode.
  defp assign_highlights(socket) do
    %{game: game, me: me, mode: mode, current_player: player} = socket.assigns

    targets =
      case mode do
        :move ->
          Game.move_targets(game, player.id)

        mode when mode in [:shoot, :give_ap] ->
          Enum.map(Game.tanks_in_range(game, player.id), & &1.position)

        nil ->
          []
      end

    range_hexes =
      if (mode in [:shoot, :give_ap] and me) && me.position do
        me.position |> Hex.range(me.range) |> Enum.filter(&Board.on_board?(game.board, &1))
      else
        []
      end

    assign(socket, targets: targets, range_hexes: range_hexes)
  end

  ## Events from the page

  @impl true
  def handle_event("join", _params, socket) do
    player = socket.assigns.current_player
    run(socket, fn id -> Tables.join(id, player.id, player.nickname) end)
  end

  def handle_event("leave", _params, socket) do
    run(socket, fn id -> Tables.leave(id, socket.assigns.current_player.id) end)
  end

  def handle_event("start", _params, socket) do
    run(socket, fn id -> Tables.start(id, socket.assigns.current_player.id) end)
  end

  def handle_event("upgrade", _params, socket), do: act(socket, :upgrade_range)

  def handle_event("vote", %{"target" => target_id}, socket), do: act(socket, {:vote, target_id})

  def handle_event("mode", %{"mode" => mode}, socket) do
    mode = Map.get(@modes, mode)
    # Clicking the active mode again turns it off.
    mode = if mode == socket.assigns.mode, do: nil, else: mode
    {:noreply, socket |> assign(:mode, mode) |> assign_highlights()}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> assign(:mode, nil) |> assign_highlights()}
  end

  def handle_event("cell", params, socket) do
    case parse_hex(params) do
      {:ok, hex} -> cell_clicked(socket, socket.assigns.mode, hex)
      :error -> {:noreply, socket}
    end
  end

  defp cell_clicked(socket, :move, hex), do: act(socket, {:move, hex})

  defp cell_clicked(socket, mode, hex) when mode in [:shoot, :give_ap] do
    case Game.tank_at(socket.assigns.game, hex) do
      %Tank{player_id: target_id} -> act(socket, {mode, target_id})
      nil -> {:noreply, socket}
    end
  end

  # No mode yet: clicking your own tank starts moving it.
  defp cell_clicked(socket, nil, hex) do
    case socket.assigns.me do
      %Tank{position: ^hex} -> {:noreply, socket |> assign(:mode, :move) |> assign_highlights()}
      _ -> {:noreply, socket}
    end
  end

  # Cell coordinates come from the browser: parse them, never trust them.
  defp parse_hex(params) do
    with {q, ""} <- Integer.parse(params["q"] || ""),
         {r, ""} <- Integer.parse(params["r"] || ""),
         {s, ""} <- Integer.parse(params["s"] || "") do
      {:ok, Hex.new(q, r, s)}
    else
      _ -> :error
    end
  end

  defp act(socket, action) do
    run(socket, fn id -> Tables.act(id, socket.assigns.current_player.id, action) end)
  end

  # Runs a change on this table and shows the result: the new game, or an error.
  defp run(socket, fun) do
    case fun.(socket.assigns.game.id) do
      {:ok, game} ->
        {:noreply, socket |> clear_flash() |> assign(:mode, nil) |> assign_game(game)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Messages.error(reason))}
    end
  end

  ## Messages from the table and the clock

  @impl true
  def handle_info({:game_updated, game}, socket), do: {:noreply, assign_game(socket, game)}

  def handle_info(:clock, socket) do
    schedule_clock(socket.assigns.game)
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  # The countdown to the next AP: every second in minute games, else every 15 s.
  defp schedule_clock(game) do
    Process.send_after(self(), :clock, if(game.tick_interval <= 60, do: 1_000, else: 15_000))
  end

  defp next_ap_in(game, now) do
    case Game.next_tick_at(game) do
      nil -> nil
      tick_at -> Messages.duration(DateTime.diff(tick_at, now, :second))
    end
  end

  ## Page

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} locale={@locale}>
      <div id="table-page" phx-window-keydown="cancel" phx-key="Escape">
        <div class="mb-6 flex flex-wrap items-center gap-x-3 gap-y-2">
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm -ml-2 gap-1">
            <.icon name="hero-arrow-left-micro" class="size-4" /> {gettext("Lobby")}
          </.link>
          <h1 class="text-2xl font-bold tracking-tight">{@game.name}</h1>
          <.status_badge status={@game.status} />
          <span class="text-sm text-base-content/60">
            {Messages.tick_interval(@game.tick_interval)}
          </span>
        </div>

        <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <section>
            <%= if @board_layout do %>
              <div class="rounded-3xl border border-base-300 bg-base-200/40 p-2 sm:p-4">
                <svg
                  id="board"
                  viewBox={@board_layout.view_box}
                  class="mx-auto max-h-[75vh] w-full select-none"
                >
                  <.board_cells cells={@board_layout.cells} />
                  <.highlights :if={@range_hexes != []} kind={:range} hexes={@range_hexes} />
                  <.highlights :if={@mode} kind={@mode} hexes={@targets} />
                  <.tanks tanks={Game.living_tanks(@game)} me={@current_player.id} />
                </svg>
              </div>
              <p :if={@mode} id="mode-hint" class="mt-3 text-center text-sm text-base-content/70">
                {mode_hint(@mode)}
                <button phx-click="cancel" class="link ml-1">{gettext("Cancel")}</button>
              </p>
            <% else %>
              <.waiting_room game={@game} me={@me} current_player={@current_player} />
            <% end %>
          </section>

          <aside class="space-y-4">
            <.winner_banner :if={@game.status == :finished} game={@game} />
            <.my_panel
              :if={@game.status == :running}
              game={@game}
              me={@me}
              mode={@mode}
              next_ap_in={next_ap_in(@game, @now)}
            />
            <.player_list game={@game} current_player={@current_player} />
            <.event_log game={@game} now={@now} />
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp mode_hint(:move), do: gettext("Click a green cell to move there.")
  defp mode_hint(:shoot), do: gettext("Click a red tank to shoot it.")
  defp mode_hint(:give_ap), do: gettext("Click a blue tank to give it 1 AP.")

  # Before the start: who's in, the link to share, join / leave / start.
  attr :game, Game, required: true
  attr :me, :any, required: true
  attr :current_player, :any, required: true

  defp waiting_room(assigns) do
    ~H"""
    <div class="rounded-3xl border border-base-300 bg-base-200/40 p-6 sm:p-8">
      <h2 class="text-lg font-bold">{gettext("Waiting for players")}</h2>
      <p class="mt-1 text-base-content/70">
        {gettext("%{count} of 20 players. The game needs at least 2.",
          count: map_size(@game.tanks)
        )}
      </p>

      <dl id="table-settings" class="mt-5 grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
        <div
          :for={{label, value} <- Messages.settings_summary(@game.settings)}
          class="rounded-xl bg-base-100 p-3"
        >
          <dt class="text-xs text-base-content/60">{label}</dt>
          <dd class="mt-0.5 font-semibold">{value}</dd>
        </div>
      </dl>

      <label for="share-link" class="mt-6 block text-sm font-semibold">
        {gettext("Invite friends with this link")}
      </label>
      <div class="mt-2 flex gap-2">
        <input
          id="share-link"
          readonly
          value={url(~p"/tables/#{@game.id}")}
          class="input input-bordered w-full font-mono text-sm"
        />
        <button
          id="copy-share-link"
          class="btn"
          phx-click={JS.dispatch("phx:copy", to: "#share-link")}
        >
          <.icon name="hero-clipboard-document" class="size-5" />
        </button>
      </div>

      <div class="mt-6 flex flex-wrap gap-3">
        <button :if={is_nil(@me)} id="join-table" phx-click="join" class="btn btn-primary">
          {gettext("Join this table")}
        </button>
        <button
          :if={@me && @game.creator_id == @current_player.id}
          id="start-game"
          phx-click="start"
          disabled={map_size(@game.tanks) < 2}
          class="btn btn-primary"
        >
          {gettext("Start the game")}
        </button>
        <button :if={@me} id="leave-table" phx-click="leave" class="btn btn-ghost">
          {gettext("Leave")}
        </button>
      </div>
      <p
        :if={@me && @game.creator_id != @current_player.id}
        class="mt-4 text-sm text-base-content/60"
      >
        {gettext("You're in! The table's creator will start the game.")}
      </p>
    </div>
    """
  end

  # Your tank and what you can do with it, or your vote as a ghost.
  attr :game, Game, required: true
  attr :me, :any, required: true
  attr :mode, :atom, required: true
  attr :next_ap_in, :string, required: true

  defp my_panel(%{me: nil} = assigns) do
    ~H"""
    <div class="rounded-2xl border border-base-300 p-4 text-sm text-base-content/70">
      {gettext("You're watching this game.")}
    </div>
    """
  end

  defp my_panel(%{me: %Tank{hp: 0}} = assigns) do
    ~H"""
    <div id="ghost-panel" class="rounded-2xl border border-base-300 bg-base-200/60 p-4">
      <h2 class="flex items-center gap-2 font-bold">
        <.icon name="hero-sparkles" class="size-5" /> {gettext("You're a ghost")}
      </h2>
      <%= if @me.has_vote do %>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Give 1 AP to a living tank. Nobody will know it was you.")}
        </p>
        <div class="mt-3 flex flex-wrap gap-2">
          <button
            :for={tank <- Game.living_tanks(@game)}
            id={"vote-#{tank.player_id}"}
            phx-click="vote"
            phx-value-target={tank.player_id}
            class="btn btn-sm gap-1.5"
          >
            <.seat_dot seat={tank.seat} /> {tank.name}
          </button>
        </div>
      <% else %>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Your next vote arrives in %{time}.", time: @next_ap_in)}
        </p>
      <% end %>
    </div>
    """
  end

  defp my_panel(assigns) do
    ~H"""
    <div id="tank-panel" class="rounded-2xl border border-base-300 bg-base-200/60 p-4">
      <div class="flex items-center gap-2">
        <.seat_dot seat={@me.seat} class="size-4" />
        <h2 class="font-bold">{gettext("Your tank")}</h2>
        <span class="ml-auto"><.hearts hp={@me.hp} max={@game.settings.start_hp} /></span>
      </div>

      <dl class="mt-4 grid grid-cols-3 gap-2 text-center">
        <div class="rounded-xl bg-base-100 p-2">
          <dt class="text-xs text-base-content/60">{gettext("Action points")}</dt>
          <dd id="my-ap" class="text-2xl font-bold">{@me.ap}</dd>
        </div>
        <div class="rounded-xl bg-base-100 p-2">
          <dt class="text-xs text-base-content/60">{gettext("Range")}</dt>
          <dd id="my-range" class="text-2xl font-bold">{@me.range}</dd>
        </div>
        <div class="rounded-xl bg-base-100 p-2">
          <dt class="text-xs text-base-content/60">{gettext("Next AP")}</dt>
          <dd id="next-ap" class="pt-1.5 text-sm font-semibold">{@next_ap_in}</dd>
        </div>
      </dl>

      <div class="mt-4 grid grid-cols-2 gap-2">
        <.action_button
          id="action-move"
          mode="move"
          active={@mode == :move}
          disabled={@me.ap < 1}
          icon="hero-arrows-pointing-out"
        >
          {gettext("Move")}
        </.action_button>
        <.action_button
          id="action-shoot"
          mode="shoot"
          active={@mode == :shoot}
          disabled={@me.ap < 1}
          icon="hero-fire"
        >
          {gettext("Shoot")}
        </.action_button>
        <.action_button
          id="action-give"
          mode="give_ap"
          active={@mode == :give_ap}
          disabled={@me.ap < 1}
          icon="hero-gift"
        >
          {gettext("Give AP")}
        </.action_button>
        <button id="action-upgrade" phx-click="upgrade" disabled={@me.ap < 1} class="btn gap-1.5">
          <.icon name="hero-arrow-trending-up" class="size-4" /> {gettext("Range +1")}
        </button>
      </div>
      <p class="mt-3 text-xs text-base-content/60">{gettext("Every action costs 1 AP.")}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :mode, :string, required: true
  attr :active, :boolean, required: true
  attr :disabled, :boolean, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp action_button(assigns) do
    ~H"""
    <button
      id={@id}
      phx-click="mode"
      phx-value-mode={@mode}
      disabled={@disabled}
      class={["btn gap-1.5", @active && "btn-primary"]}
    >
      <.icon name={@icon} class="size-4" /> {render_slot(@inner_block)}
    </button>
    """
  end

  attr :game, Game, required: true

  defp winner_banner(assigns) do
    ~H"""
    <div id="winner-banner" class="rounded-2xl border border-success/40 bg-success/10 p-4 text-center">
      <.icon name="hero-trophy" class="size-8 text-success" />
      <p class="mt-1 text-lg font-bold">
        {gettext("%{name} won!", name: Game.tank(@game, @game.winner_id).name)}
      </p>
    </div>
    """
  end

  attr :game, Game, required: true
  attr :current_player, :any, required: true

  defp player_list(assigns) do
    ~H"""
    <div class="rounded-2xl border border-base-300 p-4">
      <h2 class="mb-3 font-bold">{gettext("Players")}</h2>
      <ul id="players" class="space-y-2">
        <li
          :for={tank <- Game.tanks_by_seat(@game)}
          id={"player-#{tank.player_id}"}
          class={["flex items-center gap-2 text-sm", Tank.ghost?(tank) && "opacity-50"]}
        >
          <.seat_dot seat={tank.seat} />
          <span class="truncate font-medium">{tank.name}</span>
          <span :if={tank.player_id == @current_player.id} class="text-xs text-base-content/50">
            {gettext("(you)")}
          </span>
          <%= cond do %>
            <% @game.status == :lobby -> %>
            <% Tank.ghost?(tank) -> %>
              <span class="ml-auto text-xs">{gettext("ghost")}</span>
            <% true -> %>
              <span class="ml-auto flex items-center gap-3 text-xs text-base-content/70">
                <span title={gettext("Action points")}>{gettext("%{ap} AP", ap: tank.ap)}</span>
                <span title={gettext("Range")}>
                  <.icon name="hero-viewfinder-circle-micro" class="size-3.5" />{tank.range}
                </span>
                <.hearts hp={tank.hp} max={@game.settings.start_hp} />
              </span>
          <% end %>
        </li>
      </ul>
    </div>
    """
  end

  attr :game, Game, required: true
  attr :now, DateTime, required: true

  defp event_log(assigns) do
    ~H"""
    <div class="rounded-2xl border border-base-300 p-4">
      <h2 class="mb-3 font-bold">{gettext("What happened")}</h2>
      <ol id="events" class="max-h-72 space-y-1.5 overflow-y-auto text-sm">
        <li :for={event <- @game.events} class="flex gap-2">
          <span class="shrink-0 text-base-content/40 tabular-nums">
            {Messages.ago(DateTime.diff(@now, event.at, :second))}
          </span>
          <span>{Messages.event(event, @game)}</span>
        </li>
      </ol>
    </div>
    """
  end
end
