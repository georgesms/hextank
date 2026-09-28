defmodule HextankWeb.GameComponents do
  @moduledoc """
  Pieces for drawing a game: the SVG board, tanks, badges and colours.

  The board is drawn in three layers:

    1. `board_cells/1`: every cell, drawn once. Its assigns never change after the
       game starts, so LiveView sends it to the browser only once.
    2. highlights: the cells you can act on right now.
    3. tanks: one `<g>` per tank, keyed by player, so an action only sends the tanks
       that changed. Moves slide thanks to a CSS transition.

  Every cell (and highlight) sends `phx-click="cell"` with its `q`, `r` and `s`;
  every tank sends `phx-click="tank"` with its player id. Tanks also carry
  `data-player` (for double-clicks) and `data-tip` (their stats, shown on hover),
  both read by the table page's `.Board` hook.
  """

  use HextankWeb, :html

  alias Hextank.{Board, Game, Hex}
  alias HextankWeb.Messages

  # Size of a hex in SVG units: the distance from its centre to a corner.
  @size 10

  ## Board geometry (computed once per game)

  @doc """
  Everything the board layer needs: a map per cell with its DOM id, hex, SVG points
  and whether it's an obstacle, plus the SVG `viewBox`.
  """
  def board_layout(%Board{} = board) do
    cells =
      for hex <- Board.cells(board) do
        %{id: cell_id(hex), hex: hex, points: points(hex), obstacle?: Board.obstacle?(board, hex)}
      end

    # A pointy-top hexagonal board is sqrt(3) * size * (2r + 1) wide and
    # size * (3r + 2) tall (redblobgames: "Size and Spacing").
    half_width = :math.sqrt(3) * @size * (board.radius + 0.5) + 2
    half_height = @size * (1.5 * board.radius + 1) + 2

    view_box =
      Enum.map_join([-half_width, -half_height, 2 * half_width, 2 * half_height], " ", &number/1)

    %{cells: cells, view_box: view_box}
  end

  @doc "The DOM id of a cell."
  def cell_id(%Hex{q: q, r: r, s: s}), do: "cell_#{q}_#{r}_#{s}"

  @doc "The SVG points of a hex, a little smaller than the cell, so cells have gaps."
  def points(hex) do
    {center_x, center_y} = Hex.to_pixel(hex, @size)

    Hex.new(0, 0, 0)
    |> Hex.corners(@size * 0.92)
    |> Enum.map_join(" ", fn {x, y} -> number(center_x + x) <> "," <> number(center_y + y) end)
  end

  defp number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)

  ## Board layers

  @doc "The cells of the board. Rendered once: its assigns never change."
  attr :cells, :list, required: true

  def board_cells(assigns) do
    ~H"""
    <g id="board-cells">
      <polygon
        :for={cell <- @cells}
        id={cell.id}
        points={cell.points}
        phx-click="cell"
        phx-value-q={cell.hex.q}
        phx-value-r={cell.hex.r}
        phx-value-s={cell.hex.s}
        class={[
          "transition-colors",
          if(cell.obstacle?,
            do: "fill-base-content/35",
            else: "cursor-pointer fill-base-300 hover:fill-base-content/20"
          )
        ]}
      />
    </g>
    """
  end

  @doc "Cells highlighted for the current selection: a path, your range, a target."
  attr :hexes, :list, required: true

  attr :kind, :atom,
    required: true,
    doc: ":range, :path (affordable), :path_too_far, :target_in_range or :target_out_of_range"

  def highlights(assigns) do
    ~H"""
    <g id={"highlights-#{@kind}"}>
      <polygon
        :for={hex <- @hexes}
        id={"highlight-#{@kind}-#{cell_id(hex)}"}
        points={points(hex)}
        phx-click="cell"
        phx-value-q={hex.q}
        phx-value-r={hex.r}
        phx-value-s={hex.s}
        class={[
          @kind == :range && "pointer-events-none fill-primary/15",
          @kind == :path && "cursor-pointer fill-success/45 hover:fill-success/70",
          @kind == :path_too_far && "cursor-pointer fill-warning/40",
          @kind == :target_in_range && "pointer-events-none fill-error/50",
          @kind == :target_out_of_range && "pointer-events-none fill-base-content/25"
        ]}
      />
    </g>
    """
  end

  @doc "The living tanks. Keyed by player, so only the tanks that change are sent."
  attr :tanks, :list, required: true
  attr :me, :string, default: nil, doc: "the current player's id"

  def tanks(assigns) do
    ~H"""
    <g id="tanks">
      <g
        :for={tank <- @tanks}
        :key={tank.player_id}
        id={"tank-#{tank.player_id}"}
        style={tank_position(tank)}
        phx-click="tank"
        phx-value-player={tank.player_id}
        data-player={tank.player_id}
        data-tip={Messages.tank_stats(tank)}
        class="cursor-pointer transition-transform duration-500 ease-out"
      >
        <circle
          :if={tank.player_id == @me}
          r="8.2"
          class="fill-none stroke-base-content"
          stroke-width="1.2"
        />
        <circle r="6" fill={seat_color(tank.seat)} />
        <text
          text-anchor="middle"
          dominant-baseline="central"
          font-size="7"
          font-weight="700"
          fill="white"
        >
          {initial(tank.name)}
        </text>
      </g>
    </g>
    """
  end

  defp tank_position(tank) do
    {x, y} = Hex.to_pixel(tank.position, @size)
    "transform: translate(#{number(x)}px, #{number(y)}px)"
  end

  defp initial(name), do: name |> String.first() |> String.upcase()

  ## Small pieces

  @doc "A distinct colour per seat (golden-angle hues)."
  def seat_color(seat), do: "hsl(#{rem(seat * 137, 360)} 65% 45%)"

  @doc "A coloured dot for a tank."
  attr :seat, :integer, required: true
  attr :class, :string, default: "size-3"

  def seat_dot(assigns) do
    ~H"""
    <span
      class={["inline-block shrink-0 rounded-full", @class]}
      style={"background: #{seat_color(@seat)}"}
    />
    """
  end

  @doc "A badge showing a game's status."
  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold",
      @status == :lobby && "bg-warning/15 text-warning",
      @status == :running && "bg-success/15 text-success",
      @status == :finished && "bg-base-content/10 text-base-content/60"
    ]}>
      {Messages.status(@status)}
    </span>
    """
  end

  ## Stats as emojis

  @emoji %{hp: "❤️", ap: "⚡", range: "🎯"}

  @doc """
  A tank stat (`:hp`, `:ap` or `:range`) as emojis: repeated up to 4 times, then
  counted, so a big number stays short.

      iex> GameComponents.stat_text(:hp, 3)
      "❤️❤️❤️"

      iex> GameComponents.stat_text(:ap, 7)
      "7 × ⚡"

      iex> GameComponents.stat_text(:range, 0)
      "0 × 🎯"
  """
  @spec stat_text(:hp | :ap | :range, non_neg_integer()) :: String.t()
  def stat_text(kind, count) when count in 1..4, do: String.duplicate(@emoji[kind], count)
  def stat_text(kind, count), do: "#{count} × #{@emoji[kind]}"

  @doc "A tank stat as emojis, with the number in words for hovering and screen readers."
  attr :kind, :atom, required: true, values: [:hp, :ap, :range]
  attr :value, :integer, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def stat(assigns) do
    assigns = assign(assigns, :label, stat_label(assigns.kind, assigns.value))

    ~H"""
    <span id={@id} role="img" aria-label={@label} title={@label} class={["whitespace-nowrap", @class]}>
      {stat_text(@kind, @value)}
    </span>
    """
  end

  defp stat_label(:hp, count), do: gettext("%{hp} HP", hp: count)
  defp stat_label(:ap, count), do: gettext("%{ap} AP", ap: count)
  defp stat_label(:range, count), do: gettext("range %{range}", range: count)

  @doc "Whether the board should be shown for this game."
  def board?(%Game{board: %Board{}}), do: true
  def board?(_game), do: false
end
