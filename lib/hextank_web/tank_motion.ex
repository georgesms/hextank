defmodule HextankWeb.TankMotion do
  @moduledoc """
  How a tank moves on the board: the angles of its hull and turret, and the
  timeline of a drive along the shortest path, one cell at a time, turning the hull
  before each leg. The timelines become CSS keyframes, so the browser plays them
  without any JavaScript (see `HextankWeb.GameComponents.effects_for/3`).

  Everything here is pure: pixel positions and angles in, numbers and CSS text out.
  Angles are whole degrees, clockwise from the x axis, since SVG's y axis points
  down.
  """

  alias Hextank.{Hex, Tank}

  # How long the hull takes to turn before a leg, and the turret to aim.
  @turn_ms 150
  @aim_ms 250
  # How long driving one cell takes: a long drive goes faster per cell, so it never
  # takes much more than @drive_budget_ms.
  @drive_budget_ms 2_400
  @slowest_leg_ms 220
  @fastest_leg_ms 100

  @doc """
  The angle of a tank's hull: one of the six directions, 60 degrees apart.

      iex> TankMotion.hull_angle(%Hextank.Tank{player_id: "a", name: "A", seat: 1, heading: 1})
      -60
  """
  @spec hull_angle(Tank.t()) :: integer()
  def hull_angle(%Tank{heading: heading}), do: heading * -60

  @doc "The angle of a tank's turret: toward its last target, or along the hull."
  @spec turret_angle(Tank.t()) :: integer()
  def turret_angle(%Tank{aim: nil} = tank), do: hull_angle(tank)
  def turret_angle(%Tank{aim: %Hex{} = aim}), do: angle({0, 0}, Hex.to_pixel(aim, 1))

  @doc """
  The angle of the line from one point to another.

      iex> TankMotion.angle({0, 0}, {0, 10})
      90
  """
  @spec angle({number(), number()}, {number(), number()}) :: integer()
  def angle({x1, y1}, {x2, y2}), do: round(:math.atan2(y2 - y1, x2 - x1) * 180 / :math.pi())

  @doc """
  How far to turn to go from angle `from` to angle `to` the shortest way: between
  -180 and 179 degrees. Turning from 170 to -170 is 20 degrees, not -340.

      iex> TankMotion.turn(170, -170)
      20

      iex> TankMotion.turn(0, 270)
      -90
  """
  @spec turn(integer(), integer()) :: integer()
  def turn(from, to), do: Integer.mod(to - from + 180, 360) - 180

  @doc """
  The timeline of a drive through `points`, the pixel centres of the cells from the
  start to the goal, with the hull at `angle` when it starts. On each leg the hull
  first turns to face the next cell (unless it already does), then the tank drives
  there.

  Returns the total `:duration` in milliseconds, the tank's `:positions` and the
  hull's `:angles` as `{ms, value}` keyframes, and the `:legs`, each with its
  `:from` and `:to` points, when it `:start`s and its `:duration`.
  """
  @spec drive([{float(), float()}], integer()) :: map()
  def drive([start | _] = points, angle) do
    leg_ms = leg_ms(length(points) - 1)
    initial = %{time: 0, angle: angle, positions: [{0, start}], angles: [{0, angle}], legs: []}

    plan =
      points
      |> Enum.zip(tl(points))
      |> Enum.reduce(initial, &add_leg(&1, &2, leg_ms))

    %{
      duration: plan.time,
      positions: Enum.reverse(plan.positions),
      angles: Enum.reverse(plan.angles),
      legs: Enum.reverse(plan.legs)
    }
  end

  # Angles keep adding up instead of wrapping around at 360, so that every turn in
  # the keyframes is the short one.
  defp add_leg({from, to}, plan, leg_ms) do
    new_angle = plan.angle + turn(plan.angle, angle(from, to))
    turned_at = if new_angle == plan.angle, do: plan.time, else: plan.time + @turn_ms
    arrived_at = turned_at + leg_ms

    %{
      plan
      | time: arrived_at,
        angle: new_angle,
        # The tank waits at `from` while the hull turns, then drives to `to`.
        positions: [{arrived_at, to}, {turned_at, from} | plan.positions],
        angles: [{arrived_at, new_angle}, {turned_at, new_angle} | plan.angles],
        legs: [%{from: from, to: to, start: turned_at, duration: leg_ms} | plan.legs]
    }
  end

  defp leg_ms(legs),
    do: (@drive_budget_ms / legs) |> round() |> min(@slowest_leg_ms) |> max(@fastest_leg_ms)

  @doc """
  The timeline of the turret turning from angle `from` to angle `to`, the short way.

      iex> TankMotion.aim(170, -170)
      %{duration: 250, angles: [{0, 170}, {250, 190}]}
  """
  @spec aim(integer(), integer()) :: map()
  def aim(from, to),
    do: %{duration: @aim_ms, angles: [{0, from}, {@aim_ms, from + turn(from, to)}]}

  @doc """
  CSS keyframes called `name` that set `transform` at each `{ms, value}` frame,
  turned into CSS by `to_css`.

      iex> TankMotion.keyframes("spin", [{0, 0}, {250, 90}], 250, &TankMotion.rotate/1)
      "@keyframes spin { 0.00% { transform: rotate(0deg); } 100.00% { transform: rotate(90deg); } }"
  """
  @spec keyframes(String.t(), [{non_neg_integer(), term()}], pos_integer(), (term() ->
                                                                               String.t())) ::
          String.t()
  def keyframes(name, frames, duration, to_css) do
    steps =
      Enum.map_join(frames, " ", fn {ms, value} ->
        "#{number(ms * 100 / duration)}% { transform: #{to_css.(value)}; }"
      end)

    "@keyframes #{name} { #{steps} }"
  end

  @doc "A CSS translation to a pixel position."
  @spec translate({number(), number()}) :: String.t()
  def translate({x, y}), do: "translate(#{number(x)}px, #{number(y)}px)"

  @doc "A CSS rotation by an angle in degrees."
  @spec rotate(integer()) :: String.t()
  def rotate(angle), do: "rotate(#{angle}deg)"

  defp number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
end
