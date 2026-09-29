defmodule HextankWeb.TankMotionTest do
  use ExUnit.Case, async: true

  alias HextankWeb.TankMotion

  doctest TankMotion

  describe "drive/2" do
    test "a tank already facing the way drives at once, one leg after the other" do
      plan = TankMotion.drive([{0, 0}, {10, 0}, {20, 0}], 0)

      assert plan.duration == 440

      assert plan.positions == [
               {0, {0, 0}},
               {0, {0, 0}},
               {220, {10, 0}},
               {220, {10, 0}},
               {440, {20, 0}}
             ]

      assert Enum.map(plan.legs, & &1.start) == [0, 220]
    end

    test "the hull turns before a leg that goes another way, the short way round" do
      # Facing 170 degrees, driving towards -170 (just below the x axis, to the left).
      plan = TankMotion.drive([{0, 0}, {-10, -1.76}], 170)

      assert plan.duration == 150 + 220
      # Waits at the start while turning 20 degrees, then drives.
      assert plan.angles == [{0, 170}, {150, 190}, {370, 190}]
      assert plan.positions == [{0, {0, 0}}, {150, {0, 0}}, {370, {-10, -1.76}}]
    end

    test "a long drive goes faster per cell" do
      points = for x <- 0..30, do: {x * 10, 0}
      plan = TankMotion.drive(points, 0)

      assert hd(plan.legs).duration == 100
    end
  end
end
