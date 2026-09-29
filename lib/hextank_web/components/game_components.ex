defmodule HextankWeb.GameComponents do
  @moduledoc """
  Pieces for drawing a game: the SVG board, tanks, badges and colours.

  The board is a dark screen (the `board-` classes in `app.css`), drawn in five
  layers:

    1. `board_cells/1`: every cell, drawn once. Its assigns never change after the
       game starts, so LiveView sends it to the browser only once.
    2. highlights: the cells you can act on right now, inside a `<g>` that is
       always there, so the layers after it never move.
    3. tracks: the tread marks of recent moves.
    4. tanks: one `<g>` per tank, keyed by player, so an action only sends the tanks
       that changed. A move drives along the shortest path, turning at each cell.
    5. effects: a short animation for each action (see `effects_for/3`), played once by
       CSS when LiveView adds it to the page. No JavaScript.

  Every cell (and highlight) sends `phx-click="cell"` with its `q`, `r` and `s`;
  every tank sends `phx-click="tank"` with its player id. Tanks also carry
  `data-player` (for double-clicks) and `data-tip` (their stats, shown on hover),
  both read by the table page's `.Board` hook.
  """

  use HextankWeb, :html

  alias Hextank.{Board, Game, Hex, Tank}
  alias HextankWeb.{Messages, TankMotion}

  # Size of a hex in SVG units: the distance from its centre to a corner.
  @size 10

  ## Board geometry (computed once per game)

  @doc """
  Everything the board layer needs: a map per cell with its DOM id, hex, SVG points
  and whether it's an obstacle, plus the SVG `viewBox`. It stays on the server:
  `board_cells/1` only sends what the player can see.
  """
  def board_layout(%Board{} = board) do
    cells =
      for hex <- Board.cells(board) do
        %{id: cell_id(hex), hex: hex, points: points(hex), obstacle?: Board.obstacle?(board, hex)}
      end

    half_width = half_width(board.radius)
    half_height = half_height(board.radius)

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

  @doc """
  The cells of the board. A cell the player can't see is drawn in the fog: never
  saying whether it's a rock, and not clickable. Keyed by cell, so when the view
  moves only the cells that changed are sent.
  """
  attr :cells, :list, required: true
  attr :visible, :any, required: true, doc: ":all or a MapSet of hexes"

  def board_cells(assigns) do
    ~H"""
    <g id="board-cells">
      <polygon
        :for={cell <- @cells}
        :key={cell.id}
        id={cell.id}
        points={cell.points}
        phx-click="cell"
        phx-value-q={cell.hex.q}
        phx-value-r={cell.hex.r}
        phx-value-s={cell.hex.s}
        class={cell_class(cell, @visible)}
      />
    </g>
    """
  end

  defp cell_class(cell, visible) do
    cond do
      not Game.visible?(visible, cell.hex) -> "board-fog"
      cell.obstacle? -> "board-rock"
      true -> "board-cell"
    end
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
          @kind == :range && "pointer-events-none fill-cyan-300/10",
          @kind == :path && "cursor-pointer fill-emerald-400/35 hover:fill-emerald-400/55",
          @kind == :path_too_far && "cursor-pointer fill-amber-400/35",
          @kind == :target_in_range && "pointer-events-none fill-rose-500/45",
          @kind == :target_out_of_range && "pointer-events-none fill-white/15"
        ]}
      />
    </g>
    """
  end

  @doc """
  The tread marks of recent moves: two lines per leg, drawn while the tank drives
  along it, then fading. Under the tanks, from the same effects as `effects/1`.
  """
  attr :effects, :list, required: true

  def tracks(assigns) do
    ~H"""
    <g id="tracks" class="pointer-events-none">
      <g
        :for={effect <- @effects}
        :if={effect.kind == :moved}
        :key={effect.id}
        id={"tracks-#{effect.id}"}
        style={"color: #{effect.color}"}
      >
        <line
          :for={track <- effect.tracks}
          x1={number(elem(track.from, 0))}
          y1={number(elem(track.from, 1))}
          x2={number(elem(track.to, 0))}
          y2={number(elem(track.to, 1))}
          pathLength="1"
          class="fx-track"
          style={"animation-duration: #{track.duration}ms, 1400ms; animation-delay: #{track.start}ms, #{effect.fade_at}ms"}
        />
      </g>
    </g>
    """
  end

  @doc """
  The living tanks, drawn as the NATO symbol for armour: the hull (a rectangle)
  turns the way the tank drives, the turret (an ellipse with its gun) the way it
  aims. Keyed by player, so only the tanks that change are sent.

  A tank that just moved or shot also gets the CSS animations of that effect (see
  `effects_for/3`); once they are over it rests exactly where its base style puts it.
  """
  attr :tanks, :list, required: true
  attr :me, :string, default: nil, doc: "the current player's id"
  attr :winner_id, :string, default: nil, doc: "once the game is over: gets a crown"
  attr :effects, :list, default: [], doc: "recent effects, for the tanks' animations"

  def tanks(assigns) do
    assigns = assign(assigns, :animations, tank_animations(assigns.effects))

    ~H"""
    <g id="tanks">
      <g
        :for={tank <- @tanks}
        :key={tank.player_id}
        id={"tank-#{tank.player_id}"}
        style={
          part_style(tank_translate(tank), @animations[tank.player_id][:drive]) <>
            "; color: #{seat_color(tank.seat)}"
        }
        phx-click="tank"
        phx-value-player={tank.player_id}
        data-player={tank.player_id}
        data-tip={Messages.tank_stats(tank)}
        class="cursor-pointer"
      >
        <circle
          :if={tank.player_id == @winner_id}
          r="10.5"
          stroke-width="1.5"
          class="fx-halo fill-none stroke-warning"
        />
        <circle
          :if={tank.player_id == @me}
          r="8.8"
          stroke-width="0.6"
          stroke-dasharray="2 1.4"
          class="fill-none stroke-white/70"
        />
        <g filter="url(#tank-glow)">
          <g
            class="tank-part"
            style={
              part_style(
                TankMotion.rotate(TankMotion.hull_angle(tank)),
                @animations[tank.player_id][:hull]
              )
            }
          >
            <rect x="-5.5" y="-3.6" width="11" height="7.2" rx="0.6" class="tank-fill" />
            <line x1="-4.6" y1="-2.4" x2="4.6" y2="-2.4" class="tank-tread" />
            <line x1="-4.6" y1="2.4" x2="4.6" y2="2.4" class="tank-tread" />
          </g>
          <g
            class="tank-part"
            style={
              part_style(
                TankMotion.rotate(TankMotion.turret_angle(tank)),
                @animations[tank.player_id][:turret]
              )
            }
          >
            <rect x="1.8" y="-0.75" width="7.4" height="1.5" rx="0.4" fill="currentColor" />
            <ellipse rx="2.9" ry="2.1" class="tank-fill" />
          </g>
        </g>
        <text y="-9.5" font-size="3.6" text-anchor="middle" class="tank-callsign">
          {callsign(tank.name)}
        </text>
        <text
          :if={tank.player_id == @winner_id}
          y="-16"
          font-size="8"
          text-anchor="middle"
          dominant-baseline="central"
          class="fx-crown"
        >
          👑
        </text>
      </g>
    </g>
    """
  end

  defp tank_translate(tank), do: TankMotion.translate(Hex.to_pixel(tank.position, @size))

  # The base transform of a tank part, plus the animation that brings it there.
  defp part_style(transform, nil), do: "transform: #{transform}"
  defp part_style(transform, animation), do: "transform: #{transform}; animation: #{animation}"

  # The newest animation of each part of each tank, from the recent effects (oldest
  # first, so newer ones win). Only the newest can still be playing.
  defp tank_animations(effects) do
    Enum.reduce(effects, %{}, fn
      %{actor: actor, animations: animations}, acc ->
        Map.update(acc, actor, animations, &Map.merge(&1, animations))

      _effect, acc ->
        acc
    end)
  end

  # A short label above the tank, like a radio call sign.
  defp callsign(name), do: name |> String.slice(0, 8) |> String.upcase()

  @doc """
  Definitions the board uses: the neon glow around tanks and the hatching of rocks.
  Rendered once, before the layers.
  """
  def board_defs(assigns) do
    ~H"""
    <defs>
      <pattern
        id="rock-hatch"
        width="2.6"
        height="2.6"
        patternUnits="userSpaceOnUse"
        patternTransform="rotate(45)"
      >
        <rect width="2.6" height="2.6" fill="#22323f" />
        <line x1="0" y1="0" x2="0" y2="2.6" stroke="#6f8a9c" stroke-width="1" />
      </pattern>
      <filter id="tank-glow" x="-50%" y="-50%" width="200%" height="200%">
        <feGaussianBlur stdDeviation="0.9" result="blur" />
        <feMerge>
          <feMergeNode in="blur" />
          <feMergeNode in="SourceGraphic" />
        </feMerge>
      </filter>
    </defs>
    """
  end

  ## Action effects

  @doc """
  What to draw for `events`, the events that just happened: a drive along the
  shortest path with tread marks for a move, the turret turning and then a tracer
  and a burst for a shot, a bolt flying to the tank that got AP, a ring for a range
  upgrade. Each effect is a map with a unique `:id`, a `:kind` (the event's type),
  the `:cells` it shows (so the fog can hide it, see `visible_effect?/2`) and SVG
  coordinates.

  An effect may also have:

    * `:css`, the keyframes it needs;
    * `:animations`, the CSS animation of each part of the tank that acted
      (`:drive`, `:hull`, `:turret`), which `tanks/1` puts on that tank;
    * `:camera`, how the camera of one player moves (`:follow` for panning, `:zoom`),
      which `camera/1` uses when that player is watching: following their tank as it
      drives, zooming out when their range grows, showing the whole board once they
      are destroyed or have won.

  Positions are read from `before`, the game just before the events, where a
  destroyed tank is still on the board, and from `game`, the game after them.
  Events without an effect (joins, the start) are skipped.
  """
  def effects_for(events, %Game{} = before, %Game{} = game) do
    Enum.flat_map(events, &effect_for(&1, before, game))
  end

  defp effect_for(%{type: :moved, actor: actor}, before, game) do
    with %Tank{position: %Hex{} = from} = tank <- Game.tank(before, actor),
         {:ok, to} <- position(game, actor),
         # The same shortest path the tank just drove, worked out again.
         {:ok, path} <- Game.path(before, actor, to) do
      points = Enum.map([from | path], &Hex.to_pixel(&1, @size))
      follows? = camera(before, actor).zoom > 1
      [drive_effect(tank, points, [from, to], follows?)]
    else
      _ -> []
    end
  end

  defp effect_for(%{type: type, actor: actor, target: target}, before, game)
       when type in [:shot, :destroyed] do
    with {:ok, from} <- position(before, actor),
         {:ok, to} <- position(before, target),
         %Tank{} = shooter <- Game.tank(game, actor) do
      id = new_id()

      aim =
        TankMotion.aim(
          TankMotion.turret_angle(Game.tank(before, actor)),
          TankMotion.turret_angle(shooter)
        )

      effect = %{
        id: id,
        kind: type,
        cells: [from, to],
        from: Hex.to_pixel(from, @size),
        to: Hex.to_pixel(to, @size),
        actor: actor,
        css: TankMotion.keyframes("#{id}-turret", aim.angles, aim.duration, &TankMotion.rotate/1),
        animations: %{turret: "#{id}-turret #{aim.duration}ms ease-out both"}
      }

      # The destroyed tank's player now sees the whole board.
      if type == :destroyed,
        do: [add_camera(effect, whole_board_camera(before, target))],
        else: [effect]
    else
      _ -> []
    end
  end

  defp effect_for(%{type: :gave_ap, actor: actor, target: target}, before, _game) do
    with {:ok, from} <- position(before, actor),
         {:ok, to} <- position(before, target) do
      [
        new_effect(:gave_ap,
          cells: [from, to],
          from: Hex.to_pixel(from, @size),
          to: Hex.to_pixel(to, @size)
        )
      ]
    else
      _ -> []
    end
  end

  # A ghost's vote comes from nowhere: the bolt drops onto the tank.
  defp effect_for(%{type: :voted, target: target}, before, _game) do
    case position(before, target) do
      {:ok, to} -> [new_effect(:voted, cells: [to], to: Hex.to_pixel(to, @size))]
      :error -> []
    end
  end

  # A ring that grows to the new range: range steps of sqrt(3) * size each, the
  # distance between the centres of two neighbouring cells. The player's camera
  # zooms out to the bigger view at the same time.
  defp effect_for(%{type: :upgraded, actor: actor}, before, game) do
    with {:ok, at} <- position(before, actor),
         %Tank{range: range} <- Game.tank(game, actor) do
      radius = range * :math.sqrt(3) * @size

      effect =
        new_effect(:upgraded, cells: [at], at: Hex.to_pixel(at, @size), radius: number(radius))

      [add_camera(effect, camera_change(actor, camera(before, actor), camera(game, actor)))]
    else
      _ -> []
    end
  end

  # The winner's camera shows the whole board. Nothing else to draw.
  defp effect_for(%{type: :won, actor: actor}, before, _game) do
    [add_camera(new_effect(:won, cells: []), whole_board_camera(before, actor))]
  end

  defp effect_for(_event, _before, _game), do: []

  defp position(game, player_id) do
    case Game.tank(game, player_id) do
      %Tank{position: %Hex{} = hex} -> {:ok, hex}
      _ -> :error
    end
  end

  # A drive through `points` (the pixel centres of the cells, start first): the
  # keyframes that move the tank and turn its hull (and its turret too, when it
  # points along the hull), two tread marks per leg and, when the player's camera
  # follows the tank, the camera panning along.
  defp drive_effect(tank, points, cells, follows?) do
    id = new_id()
    plan = TankMotion.drive(points, TankMotion.hull_angle(tank))
    timing = "#{plan.duration}ms linear both"
    follow_frames = Enum.map(plan.positions, fn {ms, point} -> {ms, opposite(point)} end)

    css =
      Enum.join(
        [
          TankMotion.keyframes(
            "#{id}-drive",
            plan.positions,
            plan.duration,
            &TankMotion.translate/1
          ),
          TankMotion.keyframes("#{id}-hull", plan.angles, plan.duration, &TankMotion.rotate/1),
          TankMotion.keyframes(
            "#{id}-follow",
            follow_frames,
            plan.duration,
            &TankMotion.translate/1
          )
        ],
        " "
      )

    animations = %{drive: "#{id}-drive #{timing}", hull: "#{id}-hull #{timing}"}

    %{
      id: id,
      kind: :moved,
      cells: cells,
      actor: tank.player_id,
      color: seat_color(tank.seat),
      tracks: Enum.flat_map(plan.legs, &tread_marks/1),
      # The marks fade together, a moment after the tank arrives.
      fade_at: plan.duration + 600,
      css: css,
      animations:
        if(tank.aim == nil, do: Map.put(animations, :turret, animations.hull), else: animations),
      camera: if(follows?, do: %{player_id: tank.player_id, follow: "#{id}-follow #{timing}"})
    }
  end

  # Two lines along a leg, one under each track: 2.4 units either side of the
  # line between the two cell centres.
  defp tread_marks(%{from: {x1, y1}, to: {x2, y2}} = leg) do
    length = :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
    {side_x, side_y} = {-(y2 - y1) / length * 2.4, (x2 - x1) / length * 2.4}

    for sign <- [1, -1] do
      %{
        from: {x1 + sign * side_x, y1 + sign * side_y},
        to: {x2 + sign * side_x, y2 + sign * side_y},
        start: leg.start,
        duration: leg.duration
      }
    end
  end

  defp new_effect(kind, fields), do: Map.new([id: new_id(), kind: kind] ++ fields)

  # A fresh id each time: the browser sees a new element and plays its animation.
  # It also names the effect's keyframes, so it must be a valid CSS name.
  defp new_id, do: "effect-#{System.unique_integer([:positive])}"

  @doc """
  Whether the player can see an effect: every cell it shows is visible to them (see
  `Hextank.Game.visible_cells/2`). A tank driving out of the fog just appears.
  """
  def visible_effect?(effect, visible), do: Enum.all?(effect.cells, &Game.visible?(visible, &1))

  ## Camera

  @camera_ms 600

  @doc """
  What a player's board shows: a `:zoom` factor and the `:center` point.

  A living tank's player sees the hexagon they can see (twice their range around
  their tank), zoomed in to fill the board. Everyone else, and a player whose view
  already covers the whole board, sees the whole board.
  """
  def camera(%Game{status: :running, board: %Board{} = board} = game, player_id) do
    case Game.tank(game, player_id) do
      %Tank{position: %Hex{} = position} = tank ->
        case zoom(board.radius, Game.view_radius(tank)) do
          zoom when zoom > 1 -> %{zoom: zoom, center: Hex.to_pixel(position, @size)}
          _covers_the_board -> whole_board()
        end

      _ ->
        whole_board()
    end
  end

  def camera(_game, _player_id), do: whole_board()

  defp whole_board, do: %{zoom: 1.0, center: {0.0, 0.0}}

  @doc """
  How much to zoom in so that a view of `view_radius` fills a board of
  `board_radius`: the ratio of their widths (or heights, whichever is smaller),
  never below 1.

      iex> GameComponents.zoom(10, 10)
      1.0

      iex> GameComponents.zoom(4, 8)
      1.0
  """
  def zoom(board_radius, view_radius) do
    width_ratio = half_width(board_radius) / half_width(view_radius)
    height_ratio = half_height(board_radius) / half_height(view_radius)
    width_ratio |> min(height_ratio) |> max(1.0) |> Float.round(3)
  end

  # A pointy-top hexagon of radius r is sqrt(3) * size * (2r + 1) wide and
  # size * (3r + 2) tall (redblobgames: "Size and Spacing"), plus a small margin.
  defp half_width(radius), do: :math.sqrt(3) * @size * (radius + 0.5) + 2
  defp half_height(radius), do: @size * (1.5 * radius + 1) + 2

  # From the player's camera in `before` to the whole board.
  defp whole_board_camera(before, player_id) do
    camera_change(player_id, camera(before, player_id), whole_board())
  end

  # The keyframes taking a player's camera from one view to another. nil when it
  # doesn't change.
  defp camera_change(_player_id, same, same), do: nil

  defp camera_change(player_id, from, to) do
    %{
      player_id: player_id,
      frames: %{
        zoom: [{0, from.zoom}, {@camera_ms, to.zoom}],
        follow: [{0, opposite(from.center)}, {@camera_ms, opposite(to.center)}]
      }
    }
  end

  # Adds a camera change's keyframes to an effect, named after it.
  defp add_camera(effect, nil), do: effect

  defp add_camera(effect, %{player_id: player_id, frames: frames}) do
    css =
      TankMotion.keyframes("#{effect.id}-zoom", frames.zoom, @camera_ms, &scale/1) <>
        " " <>
        TankMotion.keyframes(
          "#{effect.id}-follow",
          frames.follow,
          @camera_ms,
          &TankMotion.translate/1
        )

    timing = "#{@camera_ms}ms ease-in-out both"

    effect
    |> Map.update(:css, css, &(&1 <> " " <> css))
    |> Map.put(:camera, %{
      player_id: player_id,
      zoom: "#{effect.id}-zoom #{timing}",
      follow: "#{effect.id}-follow #{timing}"
    })
  end

  defp opposite({x, y}), do: {-x, -y}
  defp scale(zoom), do: "scale(#{zoom})"

  @doc """
  The camera around the board layers: an outer group zooms (`scale`), an inner one
  pans (`translate`), so a point `p` ends up at `zoom * (p - center)`. Each gets the
  newest camera animation of the recent effects meant for this player.
  """
  attr :camera, :map, required: true
  attr :effects, :list, required: true
  attr :me, :string, default: nil
  slot :inner_block, required: true

  def camera_view(assigns) do
    animations =
      Enum.reduce(assigns.effects, %{}, fn
        %{camera: %{player_id: player_id} = camera}, acc when player_id == assigns.me ->
          Map.merge(acc, Map.take(camera, [:zoom, :follow]))

        _effect, acc ->
          acc
      end)

    assigns = assign(assigns, :animations, animations)

    ~H"""
    <g id="camera" class="board-camera" style={part_style(scale(@camera.zoom), @animations[:zoom])}>
      <g
        id="camera-follow"
        class="board-camera"
        style={part_style(TankMotion.translate(opposite(@camera.center)), @animations[:follow])}
      >
        {render_slot(@inner_block)}
      </g>
    </g>
    """
  end

  @doc """
  The effects layer. Keyed by id: an effect already on the page is left alone, so
  it never plays twice. The animations are CSS: the `fx-` classes in `app.css`, and
  for moves and shots the keyframes of the effect itself, in a `<style>`.
  """
  attr :effects, :list, required: true

  def effects(assigns) do
    ~H"""
    <g id="effects" class="pointer-events-none">
      <g :for={effect <- @effects} :key={effect.id} id={effect.id} data-effect={effect.kind}>
        <style :if={effect[:css]}>
          <%= effect.css %>
        </style>
        <.effect effect={effect} />
      </g>
    </g>
    """
  end

  attr :effect, :map, required: true

  # The tank itself moves (see tanks/1) and leaves marks (see tracks/1); a win only
  # moves the winner's camera (see camera_view/1).
  defp effect(%{effect: %{kind: kind}} = assigns) when kind in [:moved, :won], do: ~H""

  defp effect(%{effect: %{kind: kind}} = assigns) when kind in [:shot, :destroyed] do
    ~H"""
    <line
      x1={number(elem(@effect.from, 0))}
      y1={number(elem(@effect.from, 1))}
      x2={number(elem(@effect.to, 0))}
      y2={number(elem(@effect.to, 1))}
      pathLength="1"
      stroke-width="1.2"
      stroke-linecap="round"
      class="fx-tracer stroke-error"
    />
    <circle
      cx={number(elem(@effect.to, 0))}
      cy={number(elem(@effect.to, 1))}
      r={if @effect.kind == :destroyed, do: "12", else: "7"}
      class={[
        "fx-burst",
        if(@effect.kind == :destroyed, do: "fill-warning/70", else: "fill-error/60")
      ]}
    />
    """
  end

  defp effect(%{effect: %{kind: :gave_ap}} = assigns) do
    {from_x, from_y} = assigns.effect.from
    {to_x, to_y} = assigns.effect.to
    assigns = assign(assigns, dx: number(to_x - from_x), dy: number(to_y - from_y))

    ~H"""
    <g transform={translate(@effect.from)}>
      <text
        class="fx-travel"
        style={"--fx-dx: #{@dx}px; --fx-dy: #{@dy}px"}
        font-size="7"
        text-anchor="middle"
        dominant-baseline="central"
      >
        ⚡
      </text>
    </g>
    """
  end

  defp effect(%{effect: %{kind: :voted}} = assigns) do
    ~H"""
    <g transform={translate(@effect.to)}>
      <text class="fx-drop" font-size="7" text-anchor="middle" dominant-baseline="central">
        ⚡
      </text>
    </g>
    """
  end

  defp effect(%{effect: %{kind: :upgraded}} = assigns) do
    ~H"""
    <g transform={translate(@effect.at)}>
      <circle r={@effect.radius} stroke-width="1" class="fx-ring fill-none stroke-primary" />
      <text
        y="-10"
        font-size="5"
        text-anchor="middle"
        dominant-baseline="central"
        class="fx-float fill-white"
      >
        +1 🎯
      </text>
    </g>
    """
  end

  defp translate({x, y}), do: "translate(#{number(x)} #{number(y)})"

  ## Small pieces

  @doc "A distinct neon colour per seat (golden-angle hues), bright on the dark board."
  def seat_color(seat), do: "hsl(#{rem(seat * 137, 360)} 100% 62%)"

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
      "shrink-0 rounded px-2 py-0.5 font-mono text-xs uppercase tracking-wider",
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
