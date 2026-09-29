defmodule HextankWeb.TableLive do
  @moduledoc """
  The table page: the board, your tank and its actions, the players and the event
  log. It watches the table (see `Hextank.Tables.watch/1`), so every change made by
  anyone arrives as `{:game_updated, game}`.

  Playing happens on the board:

    * click a cell: shows the shortest path there and its cost; click it again (or
      double-click) to drive there, 1 AP per cell;
    * click a tank: shows whether it's within your range; double-click to shoot it,
      or to give it 1 AP (the player picks which in the panel);
    * click your own tank: shows your range; double-click to add 1 to it;
    * hover a tank: its stats (HP, AP, range).

  The bar above the board explains the current selection. The "Your tank" panel
  always shows every action as a button, enabled when it fits the selection (handy
  on touch screens). Escape cancels. No rule is checked here: `Hextank.Game`
  decides, we only show its answer.

  The chat panel shows the table chat and your private messages (see
  `Hextank.Chat`). Messages are a LiveView stream: once sent to the browser, the
  server forgets them.
  """

  use HextankWeb, :live_view

  alias Hextank.{Board, Chat, Game, Hex, Tables, Tank}
  alias HextankWeb.Messages

  import HextankWeb.GameComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # The first (static) render only reads the game; the live connection watches it.
    result = if connected?(socket), do: Tables.watch(id), else: Tables.get(id)

    case result do
      {:ok, game} ->
        player = socket.assigns.current_player

        if connected?(socket) do
          schedule_clock(game)
          Chat.subscribe_private(id, player.id)
          mark_read(game, player)
        end

        socket =
          socket
          |> assign(selection: nil, board_layout: nil, now: DateTime.utc_now())
          # Effects are only for what happens while the page is open.
          |> assign(effects: [], shown_until: newest_event_at(game))
          # What a double-click on another tank does: :shoot or :give_ap.
          |> assign(:double_click, :shoot)
          |> assign(chat_form: chat_form(), sent_at: [], sent_count: 0)
          |> assign_game(game)
          # Newest first: the chat box shows them bottom-up (flex-col-reverse), so it
          # stays scrolled to the latest message without any JavaScript.
          |> stream(:messages, Enum.reverse(Chat.history(id, player.id)))

        {:ok, socket}

      {:error, :not_found} ->
        {:ok, socket |> put_flash(:error, Messages.error(:not_found)) |> push_navigate(to: ~p"/")}
    end
  end

  ## Assigns

  defp assign_game(socket, game) do
    socket
    |> assign_effects(game)
    |> assign(:game, game)
    |> assign(:me, Game.tank(game, socket.assigns.current_player.id))
    |> assign(:page_title, game.name)
    |> assign_layout(game)
    |> assign_selection_details()
  end

  # Board effects for the events we haven't animated yet (see
  # GameComponents.effects_for/3), read before the new game replaces the old one.
  # `shown_until` is the time of the newest event animated so far, so an update
  # that arrives late, carrying an older game, never plays an effect twice. The last
  # few effects stay in the list: already played, they are left alone on the page.
  # New ones go at the end: moving an element in the page would restart its
  # animation.
  defp assign_effects(socket, game) do
    %{shown_until: shown_until, effects: effects} = socket.assigns

    case Enum.take_while(game.events, &DateTime.after?(&1.at, shown_until)) do
      [] ->
        socket

      [newest | _] = events ->
        new_effects = effects_for(events, socket.assigns.game, game)

        assign(socket,
          shown_until: newest.at,
          effects: Enum.take(effects ++ new_effects, -8)
        )
    end
  end

  defp newest_event_at(%Game{events: [newest | _]}), do: newest.at
  defp newest_event_at(_game), do: DateTime.from_unix!(0)

  # The board never changes once the game has started, so its layout is computed
  # only once.
  defp assign_layout(%{assigns: %{board_layout: nil}} = socket, %Game{board: %Board{} = board}) do
    assign(socket, :board_layout, board_layout(board))
  end

  defp assign_layout(socket, _game), do: socket

  ## Selection: what the player clicked on the board

  # The selection is nil, {:cell, hex} (planning a move) or {:tank, player_id}.
  # From it come the details shown under the board and the highlighted cells. They
  # are worked out again after every game update, so they never go stale.
  defp assign_selection(socket, selection) do
    socket |> assign(:selection, selection) |> assign_selection_details()
  end

  defp assign_selection_details(socket) do
    %{game: game, me: me, selection: selection} = socket.assigns
    details = selection_details(game, me, selection)
    assign(socket, details: details, highlights: highlights(game, me, details))
  end

  defp selection_details(game, %Tank{position: %Hex{}} = me, {:cell, hex}) do
    case Game.path(game, me.player_id, hex) do
      {:ok, path} ->
        %{
          kind: :path,
          target: hex,
          path: path,
          cost: length(path),
          affordable?: length(path) <= me.ap
        }

      {:error, reason} ->
        %{kind: :no_path, reason: reason}
    end
  end

  defp selection_details(_game, %Tank{player_id: id, position: %Hex{}}, {:tank, id}) do
    %{kind: :self}
  end

  defp selection_details(game, %Tank{position: %Hex{}} = me, {:tank, target_id}) do
    case Game.tank(game, target_id) do
      %Tank{position: %Hex{} = position} = target ->
        %{
          kind: :enemy,
          target: target,
          distance: Hex.distance(me.position, position),
          in_range?: Game.check_target(game, me.player_id, target_id) == :ok
        }

      # Destroyed in the meantime, or not a real player.
      _ ->
        nil
    end
  end

  defp selection_details(_game, _me, _selection), do: nil

  # A list of {kind, hexes}, drawn by GameComponents.highlights/1.
  defp highlights(_game, _me, nil), do: []
  defp highlights(_game, _me, %{kind: :no_path}), do: []

  defp highlights(_game, _me, %{kind: :path} = details) do
    [{if(details.affordable?, do: :path, else: :path_too_far), details.path}]
  end

  defp highlights(game, me, %{kind: :self}), do: [{:range, range_cells(game, me)}]

  defp highlights(game, me, %{kind: :enemy} = details) do
    target_kind = if details.in_range?, do: :target_in_range, else: :target_out_of_range
    [{:range, range_cells(game, me)}, {target_kind, [details.target.position]}]
  end

  defp range_cells(game, me) do
    me.position |> Hex.range(me.range) |> Enum.filter(&Board.on_board?(game.board, &1))
  end

  # Only a living tank that isn't frozen, in a running game, can select and act.
  defp can_select?(%{game: %Game{status: :running}, me: me}) do
    match?(%Tank{position: %Hex{}, frozen: false}, me)
  end

  defp can_select?(_assigns), do: false

  # The panel's buttons that fit the selection right now. Only a hint for the
  # player: `Game` checks every action again anyway.
  defp enabled_actions(%{game: game, me: me, details: details} = assigns) do
    cond do
      not can_select?(assigns) or me.ap < 1 -> []
      Game.max_range_reached?(game, me) -> selection_actions(details)
      true -> [:upgrade | selection_actions(details)]
    end
  end

  defp selection_actions(%{kind: :path, affordable?: true}), do: [:move]
  defp selection_actions(%{kind: :enemy, in_range?: true}), do: [:shoot, :give_ap]
  defp selection_actions(_details), do: []

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

  def handle_event("cancel", _params, socket), do: {:noreply, assign_selection(socket, nil)}

  # A click on a cell plans a move there; a second click on the same cell drives.
  def handle_event("cell", params, socket) do
    with true <- can_select?(socket.assigns),
         {:ok, hex} <- parse_hex(params) do
      case socket.assigns.selection do
        {:cell, ^hex} -> act(socket, {:move, hex})
        _ -> {:noreply, assign_selection(socket, {:cell, hex})}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  # A click on a tank selects it (your own: shows your range).
  def handle_event("tank", %{"player" => player_id}, socket) do
    if can_select?(socket.assigns),
      do: {:noreply, assign_selection(socket, {:tank, player_id})},
      else: {:noreply, socket}
  end

  # Sent by the .Board hook, since LiveView has no double-click binding of its own.
  # It only comes for the tank that was under the pointer when the double-click
  # started, so double-clicking a cell never also upgrades the tank that drives there.
  def handle_event("tank_double", %{"player" => player_id}, socket) do
    cond do
      not can_select?(socket.assigns) -> {:noreply, socket}
      player_id == socket.assigns.current_player.id -> act(socket, :upgrade_range)
      true -> act(socket, {socket.assigns.double_click, player_id})
    end
  end

  def handle_event("double_click", %{"action" => "shoot"}, socket),
    do: {:noreply, assign(socket, :double_click, :shoot)}

  def handle_event("double_click", %{"action" => "give_ap"}, socket),
    do: {:noreply, assign(socket, :double_click, :give_ap)}

  # The panel's buttons do the same for the current selection.
  def handle_event("move_here", _params, socket) do
    case socket.assigns.selection do
      {:cell, hex} -> act(socket, {:move, hex})
      _ -> {:noreply, socket}
    end
  end

  def handle_event(action, _params, socket) when action in ["shoot", "give_ap"] do
    case socket.assigns.selection do
      {:tank, target_id} -> act(socket, {String.to_existing_atom(action), target_id})
      _ -> {:noreply, socket}
    end
  end

  def handle_event("send_message", %{"chat" => %{"text" => text} = params}, socket) do
    %{game: game, current_player: player, sent_at: sent_at} = socket.assigns
    now = DateTime.utc_now()
    to = if params["to"] in [nil, ""], do: nil, else: params["to"]

    result =
      if Chat.too_fast?(sent_at, now),
        do: {:error, :too_fast},
        else: Chat.send_message(game, player, text, to, now)

    case result do
      # The message comes back through PubSub, like everyone else's.
      {:ok, _message} ->
        {:noreply,
         socket
         |> clear_flash()
         |> assign(
           chat_form: chat_form(params["to"] || ""),
           sent_at: Enum.take([now | sent_at], 5),
           # A new id for the text box: the browser swaps in a fresh, empty one.
           sent_count: socket.assigns.sent_count + 1
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Messages.error(reason))}
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
        {:noreply, socket |> clear_flash() |> assign(:selection, nil) |> assign_game(game)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Messages.error(reason))}
    end
  end

  ## Chat

  defp chat_form(to \\ ""), do: to_form(%{"text" => "", "to" => to}, as: :chat)

  # Players only: someone watching has nothing to mark as read.
  defp mark_read(game, player) do
    if Game.tank(game, player.id), do: Chat.mark_read(game.id, player.id)
  end

  ## Messages from the table and the clock

  @impl true
  def handle_info({:game_updated, game}, socket), do: {:noreply, assign_game(socket, game)}

  def handle_info(:table_deleted, socket) do
    {:noreply,
     socket |> put_flash(:error, Messages.error(:table_deleted)) |> push_navigate(to: ~p"/")}
  end

  def handle_info({:chat_message, message}, socket) do
    mark_read(socket.assigns.game, socket.assigns.current_player)
    {:noreply, stream_insert(socket, :messages, message, at: 0)}
  end

  def handle_info(:clock, socket) do
    schedule_clock(socket.assigns.game)
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  # The countdown to the next AP: every second in fast games, else every 15 s.
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
              <div
                id="board-area"
                phx-hook=".Board"
                class="rounded-3xl border border-base-300 bg-base-200/40 p-2 sm:p-4"
              >
                <%!-- A fixed wrapper: when the banner replaces the bar, the board next
                     to it stays put. Moving it would restart every animation in it. --%>
                <div id="board-top">
                  <%= if @game.status == :finished do %>
                    <.result_banner game={@game} current_player={@current_player} now={@now} />
                  <% else %>
                    <.selection_bar
                      details={@details}
                      me={@me}
                      can_select={can_select?(assigns)}
                      double_click={@double_click}
                    />
                  <% end %>
                </div>
                <svg
                  id="board"
                  viewBox={@board_layout.view_box}
                  class="board-screen mx-auto max-h-[75vh] w-full touch-manipulation select-none"
                >
                  <.board_defs />
                  <.board_cells cells={@board_layout.cells} />
                  <%!-- Always there, even with nothing highlighted: the layers after it
                       (tracks, tanks, effects) then never move, and moving them would
                       restart their animations. --%>
                  <g id="highlights">
                    <.highlights :for={{kind, hexes} <- @highlights} kind={kind} hexes={hexes} />
                  </g>
                  <.tracks effects={@effects} />
                  <.tanks
                    tanks={Game.living_tanks(@game)}
                    me={@current_player.id}
                    winner_id={@game.winner_id}
                    effects={@effects}
                  />
                  <.effects effects={@effects} />
                </svg>
                <div
                  id="tank-tooltip"
                  phx-update="ignore"
                  hidden
                  class="pointer-events-none fixed z-50 whitespace-pre-line rounded-lg bg-base-content px-2.5 py-1.5 text-xs font-medium leading-snug text-base-100 shadow-lg"
                />
              </div>
              <script :type={Phoenix.LiveView.ColocatedHook} name=".Board">
                // Two things the server can't see: double-clicks and hovering.
                export default {
                  mounted() {
                    const tooltip = this.el.querySelector("#tank-tooltip")

                    // Only a double-click that started on a tank counts.
                    this.el.addEventListener("dblclick", (event) => {
                      const tank = event.target.closest("[data-player]")
                      if (tank) this.pushEvent("tank_double", {player: tank.dataset.player})
                    })

                    // Hovering a tank shows its stats next to the pointer.
                    this.el.addEventListener("mousemove", (event) => {
                      const tank = event.target.closest("[data-tip]")
                      tooltip.hidden = !tank
                      if (!tank) return
                      tooltip.textContent = tank.dataset.tip
                      tooltip.style.left = `${event.clientX + 14}px`
                      tooltip.style.top = `${event.clientY + 14}px`
                    })
                    this.el.addEventListener("mouseleave", () => (tooltip.hidden = true))
                  },
                }
              </script>
            <% else %>
              <.waiting_room game={@game} me={@me} current_player={@current_player} />
            <% end %>
          </section>

          <aside class="space-y-4">
            <.my_panel
              :if={@game.status == :running}
              game={@game}
              me={@me}
              next_ap_in={next_ap_in(@game, @now)}
              enabled={enabled_actions(assigns)}
              double_click={@double_click}
            />
            <.player_list game={@game} current_player={@current_player} />
            <.chat_panel
              streams={@streams}
              form={@chat_form}
              sent_count={@sent_count}
              game={@game}
              me={@me}
              current_player={@current_player}
            />
            <.event_log game={@game} now={@now} />
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Above the board: what the selection means. The buttons are in the panel.
  attr :details, :map, default: nil
  attr :me, :any, required: true
  attr :can_select, :boolean, required: true
  attr :double_click, :atom, required: true

  defp selection_bar(assigns) do
    ~H"""
    <div
      id="selection-info"
      class="mb-2 flex min-h-10 flex-wrap items-center justify-center gap-x-3 gap-y-2 px-2 text-center text-sm"
    >
      <%= case @details do %>
        <% nil -> %>
          <span :if={@can_select} class="text-base-content/60">
            {gettext(
              "Click a cell to plan a move, or a tank to check your range. Double-click to act. Hover a tank for its stats."
            )}
          </span>
        <% %{kind: :path, affordable?: true} = details -> %>
          <span>
            {ngettext(
              "1 cell away, 1 AP. Click it again to drive there.",
              "%{count} cells along the path, %{count} AP. Click again to drive there.",
              details.cost
            )}
          </span>
        <% %{kind: :path} = details -> %>
          <span class="text-warning">
            {ngettext(
              "1 cell away: you need 1 AP and have %{ap}.",
              "%{count} cells along the path: you need %{count} AP and have %{ap}.",
              details.cost,
              ap: @me.ap
            )}
          </span>
        <% %{kind: :no_path, reason: reason} -> %>
          <span class="text-base-content/70">{Messages.error(reason)}</span>
        <% %{kind: :self} -> %>
          <span>
            {gettext(
              "Your range is %{range} (highlighted). Double-click your tank to add 1 for 1 AP.",
              range: @me.range
            )}
          </span>
        <% %{kind: :enemy, in_range?: true} = details -> %>
          <span>
            {ngettext(
              "%{name} is 1 cell away, within your range of %{range}.",
              "%{name} is %{count} cells away, within your range of %{range}.",
              details.distance,
              name: details.target.name,
              range: @me.range
            )}
            <%= if @double_click == :shoot do %>
              {gettext("Double-click to shoot for 1 AP.")}
            <% else %>
              {gettext("Double-click to give 1 AP.")}
            <% end %>
          </span>
        <% %{kind: :enemy} = details -> %>
          <span class="text-base-content/70">
            {ngettext(
              "%{name} is 1 cell away, out of your range of %{range}.",
              "%{name} is %{count} cells away, out of your range of %{range}.",
              details.distance,
              name: details.target.name,
              range: @me.range
            )}
          </span>
      <% end %>
      <button :if={@details} id="selection-cancel" phx-click="cancel" class="btn btn-ghost btn-sm">
        {gettext("Cancel")}
      </button>
    </div>
    """
  end

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
  attr :next_ap_in, :string, required: true
  attr :enabled, :list, default: [], doc: "the actions that fit the selection"
  attr :double_click, :atom, default: :shoot

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
        <.stat id="my-hp" kind={:hp} value={@me.hp} class="ml-auto" />
      </div>

      <dl class="mt-4 grid grid-cols-3 gap-2 text-center">
        <div class="rounded-xl bg-base-100 p-2">
          <dt class="text-xs text-base-content/60">{gettext("Action points")}</dt>
          <dd class="pt-1 text-lg"><.stat id="my-ap" kind={:ap} value={@me.ap} /></dd>
        </div>
        <div class="rounded-xl bg-base-100 p-2">
          <dt class="text-xs text-base-content/60">{gettext("Range")}</dt>
          <dd class="pt-1 text-lg"><.stat id="my-range" kind={:range} value={@me.range} /></dd>
        </div>
        <div class="rounded-xl bg-base-100 p-2">
          <dt class="text-xs text-base-content/60">{gettext("Next AP")}</dt>
          <dd id="next-ap" class="pt-1.5 text-sm font-semibold">{@next_ap_in}</dd>
        </div>
      </dl>

      <div id="actions" class="mt-4 grid grid-cols-2 gap-2">
        <button
          id="action-move"
          phx-click="move_here"
          disabled={:move not in @enabled}
          class="btn btn-success gap-1.5"
        >
          <.icon name="hero-arrow-right-circle" class="size-4" /> {gettext("Move here")}
        </button>
        <button
          id="action-shoot"
          phx-click="shoot"
          disabled={:shoot not in @enabled}
          class="btn btn-error gap-1.5"
        >
          <.icon name="hero-fire" class="size-4" /> {gettext("Shoot")}
        </button>
        <button
          id="action-give"
          phx-click="give_ap"
          disabled={:give_ap not in @enabled}
          class="btn btn-info gap-1.5"
        >
          <.icon name="hero-gift" class="size-4" /> {gettext("Give 1 AP")}
        </button>
        <button
          id="action-upgrade"
          phx-click="upgrade"
          disabled={:upgrade not in @enabled}
          class="btn gap-1.5"
        >
          <.icon name="hero-arrow-trending-up" class="size-4" /> {gettext("Range +1")}
        </button>
      </div>
      <div class="mt-4">
        <p class="text-xs text-base-content/60">
          {gettext("A double-click on another tank:")}
        </p>
        <div id="double-click-choice" class="join mt-1 w-full">
          <button
            :for={{action, label} <- [shoot: gettext("Shoots it"), give_ap: gettext("Gives it 1 AP")]}
            id={"double-click-#{action}"}
            phx-click="double_click"
            phx-value-action={action}
            aria-pressed={to_string(@double_click == action)}
            class={["btn btn-sm join-item flex-1", @double_click == action && "btn-neutral"]}
          >
            {label}
          </button>
        </div>
      </div>
      <p class="mt-3 text-xs text-base-content/60">
        {gettext(
          "Pick a cell or a tank on the board first. Every action costs 1 AP; driving costs 1 AP per cell."
        )}
      </p>
    </div>
    """
  end

  # Above the board once the game is over, instead of the selection bar: who won,
  # with a little celebration, and when the table will be deleted.
  attr :game, Game, required: true
  attr :current_player, :any, required: true
  attr :now, DateTime, required: true

  defp result_banner(assigns) do
    assigns = assign(assigns, winner: Game.tank(assigns.game, assigns.game.winner_id))

    ~H"""
    <div
      id="winner-banner"
      class="fx-pop relative mb-2 rounded-2xl border border-warning/40 bg-warning/10 px-4 py-3 text-center"
    >
      <span :for={style <- confetti()} class="fx-confetti" style={style} />
      <.icon name="hero-trophy" class="fx-bounce inline-block size-8 text-warning" />
      <p class="text-lg font-bold">
        <%= if @winner.player_id == @current_player.id do %>
          {gettext("You won!")}
        <% else %>
          {gettext("%{name} won!", name: @winner.name)}
        <% end %>
      </p>
      <p class="text-xs text-base-content/60">
        {Messages.deleted_in(DateTime.diff(Tables.expires_at(@game), @now, :second))}
      </p>
    </div>
    """
  end

  # Eight dots flying out of the trophy, one every 45 degrees, further sideways than
  # up and down since the banner is wide. Their animation is in app.css.
  defp confetti do
    for index <- 0..7 do
      angle = index * :math.pi() / 4
      dx = round(56 * :math.cos(angle))
      dy = round(28 * :math.sin(angle))
      "--fx-dx: #{dx}px; --fx-dy: #{dy}px; background: #{seat_color(index + 1)}"
    end
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
                <.stat kind={:ap} value={tank.ap} />
                <.stat kind={:range} value={tank.range} />
                <.stat kind={:hp} value={tank.hp} />
              </span>
          <% end %>
        </li>
      </ul>
    </div>
    """
  end

  attr :streams, :map, required: true
  attr :form, :map, required: true
  attr :sent_count, :integer, required: true
  attr :game, Game, required: true
  attr :me, :any, required: true
  attr :current_player, :any, required: true

  defp chat_panel(assigns) do
    ~H"""
    <div id="chat" class="rounded-2xl border border-base-300 p-4">
      <h2 class="mb-3 font-bold">{gettext("Chat")}</h2>
      <ol
        id="messages"
        phx-update="stream"
        class="flex max-h-80 flex-col-reverse gap-2 overflow-y-auto text-sm"
      >
        <li id="messages-empty" class="hidden text-base-content/50 only:block">
          {gettext("No messages yet. Diplomacy starts here.")}
        </li>
        <li :for={{dom_id, message} <- @streams.messages} id={dom_id}>
          <.chat_message message={message} game={@game} current_player={@current_player} />
        </li>
      </ol>

      <.form
        :if={@me}
        for={@form}
        id="chat-form"
        phx-submit="send_message"
        class="mt-3 space-y-2"
      >
        <select
          id="chat-to"
          name={@form[:to].name}
          class="select select-bordered select-sm w-full"
        >
          <option value="">{gettext("Everyone at the table")}</option>
          <option
            :for={tank <- Game.tanks_by_seat(@game)}
            :if={tank.player_id != @current_player.id}
            value={tank.player_id}
            selected={@form[:to].value == tank.player_id}
          >
            {gettext("Privately to %{name}", name: tank.name)}
          </option>
        </select>
        <div class="flex gap-2">
          <input
            id={"chat-text-#{@sent_count}"}
            phx-mounted={@sent_count > 0 && JS.focus()}
            name={@form[:text].name}
            value={@form[:text].value}
            maxlength="500"
            autocomplete="off"
            placeholder={gettext("Write a message")}
            class="input input-bordered input-sm w-full"
          />
          <button id="chat-send" class="btn btn-primary btn-sm">
            <.icon name="hero-paper-airplane-micro" class="size-4" />
          </button>
        </div>
      </.form>
    </div>
    """
  end

  attr :message, :map, required: true
  attr :game, Game, required: true
  attr :current_player, :any, required: true

  defp chat_message(assigns) do
    ~H"""
    <div class={[@message.to && "rounded-lg bg-info/10 px-2 py-1"]}>
      <span class="font-semibold">{@message.name}</span>
      <span :if={@message.to} class="text-xs text-info">
        <.icon name="hero-lock-closed-micro" class="size-3" />
        <%= if @message.from == @current_player.id do %>
          {gettext("to %{name}", name: recipient_name(@game, @message.to))}
        <% else %>
          {gettext("privately")}
        <% end %>
      </span>
      <p class="break-words">{@message.text}</p>
    </div>
    """
  end

  defp recipient_name(game, player_id) do
    case Game.tank(game, player_id) do
      nil -> gettext("someone")
      tank -> tank.name
    end
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
