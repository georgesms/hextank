defmodule Hextank.Hex do
  @moduledoc """
  Hexagons in cube coordinates, following Red Blob Games' guide:
  <https://www.redblobgames.com/grids/hexagons/>

  A hex has three coordinates `q`, `r` and `s`, always with `q + r + s == 0`.
  The board uses **pointy-top** hexes.

      iex> Hex.new(1, -1, 0)
      %Hex{q: 1, r: -1, s: 0}
  """

  @enforce_keys [:q, :r, :s]
  defstruct [:q, :r, :s]

  @type t :: %__MODULE__{q: integer(), r: integer(), s: integer()}

  # redblobgames: "Neighbors". Index 0..5, written as {q, r, s}.
  @directions [{1, 0, -1}, {1, -1, 0}, {0, -1, 1}, {-1, 0, 1}, {-1, 1, 0}, {0, 1, -1}]

  @doc """
  Builds a hex. Raises `ArgumentError` unless the coordinates are integers with
  `q + r + s == 0`: a wrong hex is a bug, not a game error.

      iex> Hex.new(0, 0, 0)
      %Hex{q: 0, r: 0, s: 0}

      iex> Hex.new(1, 1, 1)
      ** (ArgumentError) invalid hex (q: 1, r: 1, s: 1): q + r + s must be 0
  """
  @spec new(integer(), integer(), integer()) :: t()
  def new(q, r, s)
      when is_integer(q) and is_integer(r) and is_integer(s) and q + r + s == 0 do
    %__MODULE__{q: q, r: r, s: s}
  end

  def new(q, r, s) do
    raise ArgumentError,
          "invalid hex (q: #{inspect(q)}, r: #{inspect(r)}, s: #{inspect(s)}): q + r + s must be 0"
  end

  @doc """
  Adds two hexes, coordinate by coordinate.

      iex> Hex.add(Hex.new(1, -1, 0), Hex.new(0, 1, -1))
      Hex.new(1, 0, -1)
  """
  # redblobgames: "Coordinate arithmetic"
  @spec add(t(), t()) :: t()
  def add(a, b), do: new(a.q + b.q, a.r + b.r, a.s + b.s)

  @doc """
  Subtracts hex `b` from hex `a`, coordinate by coordinate.

      iex> Hex.subtract(Hex.new(1, 0, -1), Hex.new(1, -1, 0))
      Hex.new(0, 1, -1)
  """
  # redblobgames: "Coordinate arithmetic"
  @spec subtract(t(), t()) :: t()
  def subtract(a, b), do: new(a.q - b.q, a.r - b.r, a.s - b.s)

  @doc """
  Multiplies every coordinate by `factor`.

      iex> Hex.scale(Hex.new(1, -1, 0), 3)
      Hex.new(3, -3, 0)
  """
  # redblobgames: "Coordinate arithmetic"
  @spec scale(t(), integer()) :: t()
  def scale(hex, factor), do: new(hex.q * factor, hex.r * factor, hex.s * factor)

  @doc """
  The six directions, as hexes one step away from `Hex.new(0, 0, 0)`.

      iex> length(Hex.directions())
      6

      iex> hd(Hex.directions())
      Hex.new(1, 0, -1)
  """
  @spec directions() :: [t()]
  def directions, do: Enum.map(@directions, fn {q, r, s} -> new(q, r, s) end)

  @doc """
  The direction with the given index, from 0 to 5.

      iex> Hex.direction(4)
      Hex.new(-1, 1, 0)
  """
  @spec direction(0..5) :: t()
  def direction(index) when index in 0..5, do: Enum.at(directions(), index)

  @doc """
  The index (0..5) of a direction, or `nil` if the hex isn't one of the six
  directions. The opposite of `direction/1`.

      iex> Hex.direction_index(Hex.new(-1, 1, 0))
      4

      iex> Hex.direction_index(Hex.new(2, -2, 0))
      nil
  """
  @spec direction_index(t()) :: 0..5 | nil
  def direction_index(hex), do: Enum.find_index(directions(), &(&1 == hex))

  @doc """
  The neighbouring hex in the direction with the given index, from 0 to 5.

      iex> Hex.neighbor(Hex.new(0, 0, 0), 1)
      Hex.new(1, -1, 0)
  """
  # redblobgames: "Neighbors"
  @spec neighbor(t(), 0..5) :: t()
  def neighbor(hex, index), do: add(hex, direction(index))

  @doc """
  The six neighbours of a hex, in direction order.

      iex> Hex.neighbors(Hex.new(2, -1, -1))
      [
        Hex.new(3, -1, -2),
        Hex.new(3, -2, -1),
        Hex.new(2, -2, 0),
        Hex.new(1, -1, 0),
        Hex.new(1, 0, -1),
        Hex.new(2, 0, -2)
      ]
  """
  # redblobgames: "Neighbors"
  @spec neighbors(t()) :: [t()]
  def neighbors(hex), do: Enum.map(directions(), &add(hex, &1))

  @doc """
  The number of steps between two hexes.

      iex> Hex.distance(Hex.new(0, 0, 0), Hex.new(3, -1, -2))
      3

      iex> Hex.distance(Hex.new(-1, 2, -1), Hex.new(-1, 2, -1))
      0
  """
  # redblobgames: "Distances"
  @spec distance(t(), t()) :: non_neg_integer()
  def distance(a, b) do
    max(abs(a.q - b.q), max(abs(a.r - b.r), abs(a.s - b.s)))
  end

  @doc """
  Every hex at most `n` steps away from `center`, `center` included.
  There are `3n² + 3n + 1` of them.

      iex> Hex.range(Hex.new(0, 0, 0), 0)
      [Hex.new(0, 0, 0)]

      iex> length(Hex.range(Hex.new(0, 0, 0), 2))
      19
  """
  # redblobgames: "Movement range"
  @spec range(t(), non_neg_integer()) :: [t()]
  def range(center, n) when is_integer(n) and n >= 0 do
    for q <- -n..n, r <- max(-n, -q - n)..min(n, -q + n) do
      add(center, new(q, r, -q - r))
    end
  end

  @doc """
  Every hex exactly `radius` steps away from `center`. There are `6 * radius` of
  them (and just `center` itself for radius 0).

      iex> Hex.ring(Hex.new(0, 0, 0), 1)
      [
        Hex.new(-1, 1, 0),
        Hex.new(0, 1, -1),
        Hex.new(1, 0, -1),
        Hex.new(1, -1, 0),
        Hex.new(0, -1, 1),
        Hex.new(-1, 0, 1)
      ]

      iex> length(Hex.ring(Hex.new(0, 0, 0), 3))
      18
  """
  # redblobgames: "Rings"
  @spec ring(t(), non_neg_integer()) :: [t()]
  def ring(center, 0), do: [center]

  def ring(center, radius) when is_integer(radius) and radius > 0 do
    start = add(center, scale(direction(4), radius))

    # Walk around the ring: `radius` steps along each of the six sides.
    sides = for side <- 0..5, _step <- 1..radius, do: side

    {hexes, _back_at_start} =
      Enum.map_reduce(sides, start, fn side, hex -> {hex, neighbor(hex, side)} end)

    hexes
  end

  @doc """
  The shortest path from `start` to `goal`, stepping only on hexes where
  `passable?.(hex)` is true, in at most `max_steps` steps. Returns the hexes to walk
  through, `start` excluded and `goal` included, or `:error` if there's no such path.

  A breadth-first search: look at every hex 1 step away, then 2 steps, and so on,
  remembering where each hex was reached from, until the goal is found.

      iex> Hex.find_path(Hex.new(0, 0, 0), Hex.new(2, 0, -2), fn _ -> true end, 10)
      {:ok, [Hex.new(1, 0, -1), Hex.new(2, 0, -2)]}

      iex> wall = Hex.new(1, 0, -1)
      iex> {:ok, path} = Hex.find_path(Hex.new(0, 0, 0), Hex.new(2, 0, -2), &(&1 != wall), 10)
      iex> {length(path), wall in path}
      {3, false}

      iex> Hex.find_path(Hex.new(0, 0, 0), Hex.new(3, 0, -3), fn _ -> true end, 2)
      :error
  """
  # redblobgames: "Movement range" (breadth-first search around obstacles)
  @spec find_path(t(), t(), (t() -> boolean()), non_neg_integer()) :: {:ok, [t()]} | :error
  def find_path(start, goal, passable?, max_steps) do
    search([start], %{start => nil}, goal, passable?, max_steps)
  end

  # `came_from` maps each hex reached to the hex it was reached from.
  defp search(_frontier, came_from, goal, _passable?, _steps_left)
       when is_map_key(came_from, goal) do
    {:ok, trace_back(came_from, goal, [])}
  end

  defp search([], _came_from, _goal, _passable?, _steps_left), do: :error
  defp search(_frontier, _came_from, _goal, _passable?, 0), do: :error

  defp search(frontier, came_from, goal, passable?, steps_left) do
    # One step further: every new passable neighbour of the current frontier.
    {next_frontier, came_from} =
      for hex <- frontier, neighbor <- neighbors(hex), reduce: {[], came_from} do
        {next, came_from} ->
          if Map.has_key?(came_from, neighbor) or not passable?.(neighbor),
            do: {next, came_from},
            else: {[neighbor | next], Map.put(came_from, neighbor, hex)}
      end

    search(next_frontier, came_from, goal, passable?, steps_left - 1)
  end

  # Walk back from the goal to the start (whose came_from is nil), start excluded.
  defp trace_back(came_from, hex, path) do
    case Map.fetch!(came_from, hex) do
      nil -> path
      previous -> trace_back(came_from, previous, [hex | path])
    end
  end

  @doc """
  The pixel position `{x, y}` of the centre of a pointy-top hex of the given `size`
  (the distance from the centre to a corner). `Hex.new(0, 0, 0)` is at `{0.0, 0.0}`.

  The guide's formula doesn't use `s`, but the function still takes a full hex.

      iex> Hex.to_pixel(Hex.new(0, 0, 0), 10)
      {0.0, 0.0}

      iex> {x, y} = Hex.to_pixel(Hex.new(0, 1, -1), 10)
      iex> {Float.round(x, 2), Float.round(y, 2)}
      {8.66, 15.0}
  """
  # redblobgames: "Hex to pixel" (pointy-top)
  @spec to_pixel(t(), number()) :: {float(), float()}
  def to_pixel(hex, size) do
    x = size * (:math.sqrt(3) * hex.q + :math.sqrt(3) / 2 * hex.r)
    y = size * (3 / 2 * hex.r)
    {x, y}
  end

  @doc """
  The six corners `{x, y}` of a pointy-top hex of the given `size`, ready to draw as
  an SVG polygon. Corner `i` is at angle `60 * i - 30` degrees from the centre.

      iex> corners = Hex.corners(Hex.new(0, 0, 0), 10)
      iex> length(corners)
      6
      iex> {x, y} = hd(corners)
      iex> {Float.round(x, 2), Float.round(y, 2)}
      {8.66, -5.0}
  """
  # redblobgames: "Angles" (pointy-top)
  @spec corners(t(), number()) :: [{float(), float()}]
  def corners(hex, size) do
    {center_x, center_y} = to_pixel(hex, size)

    for i <- 0..5 do
      angle = :math.pi() / 180 * (60 * i - 30)
      {center_x + size * :math.cos(angle), center_y + size * :math.sin(angle)}
    end
  end
end
