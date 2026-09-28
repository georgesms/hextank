defmodule Hextank.BoardTest do
  use ExUnit.Case, async: true

  alias Hextank.{Board, Hex, Random}

  doctest Hextank.Board
  doctest Hextank.Random

  describe "generate/2" do
    test "is the same for the same seed" do
      assert Board.generate(4, 123) == Board.generate(4, 123)
    end

    test "has about one obstacle in ten cells, all on the board" do
      board = Board.generate(4, 123)

      assert MapSet.size(board.obstacles) == round(Board.cell_count(board.radius) * 0.1)
      assert Enum.all?(board.obstacles, &Board.on_board?(board, &1))
    end
  end

  describe "radius_for/1" do
    test "gives every player at least 15 cells" do
      for players <- 2..20 do
        assert Board.cell_count(Board.radius_for(players)) >= players * 15
      end
    end
  end

  describe "open_cells/1" do
    test "are the cells that are not obstacles" do
      board = Board.new(1, [Hex.new(0, 0, 0)])

      assert length(Board.open_cells(board)) == 6
      refute Hex.new(0, 0, 0) in Board.open_cells(board)
    end
  end

  test "Random.shuffle/2 gives different orders for different seeds" do
    list = Enum.to_list(1..20)
    refute Random.shuffle(list, 1) == Random.shuffle(list, 2)
  end
end
