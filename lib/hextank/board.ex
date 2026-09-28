defmodule Hextank.Board do
  @moduledoc """
  The board: a big hexagon of `radius` around `Hex.new(0, 0, 0)`, with some obstacle
  hexes that no tank can enter.

  The cells are not stored, they are computed from the radius (see README,
  *Frugality*). Only the obstacles are stored.
  """

  alias Hextank.{Hex, Random}

  @enforce_keys [:radius, :obstacles]
  defstruct [:radius, :obstacles]

  @type t :: %__MODULE__{radius: non_neg_integer(), obstacles: MapSet.t(Hex.t())}

  # About one cell in ten is an obstacle.
  @obstacle_share 0.1

  # The board gets bigger with more players: at least this many cells per player.
  @cells_per_player 15
  @min_radius 4

  @doc """
  Builds a board with the given obstacles.

      iex> board = Board.new(2, [Hex.new(1, -1, 0)])
      iex> Board.obstacle?(board, Hex.new(1, -1, 0))
      true
  """
  @spec new(non_neg_integer(), [Hex.t()]) :: t()
  def new(radius, obstacles \\ []) do
    %__MODULE__{radius: radius, obstacles: MapSet.new(obstacles)}
  end

  @doc """
  Builds a board for `player_count` players, with obstacles placed at random
  (repeatable with the same `seed`).
  """
  @spec generate(pos_integer(), integer()) :: t()
  def generate(player_count, seed) do
    radius = radius_for(player_count)
    cells = cells(new(radius))
    obstacle_count = round(length(cells) * @obstacle_share)

    obstacles =
      cells
      |> Random.shuffle(seed)
      |> Enum.take(obstacle_count)

    new(radius, obstacles)
  end

  @doc """
  The smallest radius that gives every player at least #{@cells_per_player} cells.

      iex> Board.radius_for(2)
      4

      iex> Board.radius_for(20)
      10
  """
  @spec radius_for(pos_integer()) :: pos_integer()
  def radius_for(player_count) do
    Stream.iterate(@min_radius, &(&1 + 1))
    |> Enum.find(fn radius -> cell_count(radius) >= player_count * @cells_per_player end)
  end

  @doc """
  How many cells a board of this radius has: `3r² + 3r + 1`.

      iex> Board.cell_count(5)
      91
  """
  @spec cell_count(non_neg_integer()) :: pos_integer()
  def cell_count(radius), do: 3 * radius * radius + 3 * radius + 1

  @doc "Every cell of the board, obstacles included."
  @spec cells(t()) :: [Hex.t()]
  def cells(board), do: Hex.range(Hex.new(0, 0, 0), board.radius)

  @doc """
  Whether a hex is on the board.

      iex> Board.on_board?(Board.new(2), Hex.new(2, -2, 0))
      true

      iex> Board.on_board?(Board.new(2), Hex.new(3, -3, 0))
      false
  """
  @spec on_board?(t(), Hex.t()) :: boolean()
  def on_board?(board, hex), do: Hex.distance(Hex.new(0, 0, 0), hex) <= board.radius

  @doc "Whether a hex is an obstacle."
  @spec obstacle?(t(), Hex.t()) :: boolean()
  def obstacle?(board, hex), do: MapSet.member?(board.obstacles, hex)

  @doc "The cells a tank could stand on: on the board and not an obstacle."
  @spec open_cells(t()) :: [Hex.t()]
  def open_cells(board), do: Enum.reject(cells(board), &obstacle?(board, &1))
end
