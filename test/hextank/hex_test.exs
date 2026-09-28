defmodule Hextank.HexTest do
  use ExUnit.Case, async: true

  alias Hextank.Hex

  doctest Hextank.Hex

  describe "new/3" do
    test "rejects coordinates that don't add up to 0" do
      assert_raise ArgumentError, fn -> Hex.new(1, 0, 0) end
    end

    test "rejects coordinates that are not integers" do
      assert_raise ArgumentError, fn -> Hex.new(0.5, -0.5, 0) end
    end
  end

  describe "directions/0" do
    test "are six different hexes one step away" do
      origin = Hex.new(0, 0, 0)
      directions = Hex.directions()

      assert length(Enum.uniq(directions)) == 6
      assert Enum.all?(directions, &(Hex.distance(origin, &1) == 1))
    end

    test "opposite directions cancel out" do
      for index <- 0..2 do
        opposite = index + 3
        assert Hex.add(Hex.direction(index), Hex.direction(opposite)) == Hex.new(0, 0, 0)
      end
    end
  end

  describe "distance/2" do
    test "is the same in both directions" do
      a = Hex.new(2, -3, 1)
      b = Hex.new(-1, 0, 1)

      assert Hex.distance(a, b) == Hex.distance(b, a)
      assert Hex.distance(a, b) == 3
    end
  end

  describe "range/2" do
    test "has 3n² + 3n + 1 hexes, all within n steps" do
      center = Hex.new(1, -2, 1)

      for n <- 0..5 do
        hexes = Hex.range(center, n)

        assert length(hexes) == 3 * n * n + 3 * n + 1
        assert length(Enum.uniq(hexes)) == length(hexes)
        assert Enum.all?(hexes, &(Hex.distance(center, &1) <= n))
      end
    end

    test "is made of the rings from 0 to n" do
      center = Hex.new(0, 0, 0)
      rings = Enum.flat_map(0..4, &Hex.ring(center, &1))

      assert MapSet.new(rings) == MapSet.new(Hex.range(center, 4))
    end
  end

  describe "ring/2" do
    test "has 6 * radius hexes, all exactly radius steps away" do
      center = Hex.new(-2, 0, 2)

      for radius <- 1..5 do
        hexes = Hex.ring(center, radius)

        assert length(hexes) == 6 * radius
        assert length(Enum.uniq(hexes)) == length(hexes)
        assert Enum.all?(hexes, &(Hex.distance(center, &1) == radius))
      end
    end
  end

  describe "to_pixel/2 and corners/2" do
    test "neighbours are sqrt(3) * size apart" do
      origin = Hex.new(0, 0, 0)
      {x0, y0} = Hex.to_pixel(origin, 10)

      for neighbor <- Hex.neighbors(origin) do
        {x, y} = Hex.to_pixel(neighbor, 10)
        assert_in_delta :math.sqrt((x - x0) ** 2 + (y - y0) ** 2), :math.sqrt(3) * 10, 1.0e-9
      end
    end

    test "every corner is size away from the centre" do
      hex = Hex.new(2, -1, -1)
      {center_x, center_y} = Hex.to_pixel(hex, 10)

      for {x, y} <- Hex.corners(hex, 10) do
        assert_in_delta :math.sqrt((x - center_x) ** 2 + (y - center_y) ** 2), 10, 1.0e-9
      end
    end
  end
end
