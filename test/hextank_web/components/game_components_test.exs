defmodule HextankWeb.GameComponentsTest do
  use ExUnit.Case, async: true

  alias Hextank.{Game, Hex}
  alias HextankWeb.GameComponents

  doctest GameComponents

  @now ~U[2026-03-01 12:00:00Z]

  # Ana and Bruno side by side on a small board with no rocks, each with some AP.
  defp game do
    game =
      Game.new(
        id: "t1",
        name: "Test",
        visibility: :public,
        creator_id: "ana",
        tick_interval: 60,
        created_at: @now,
        settings: %{Hextank.Settings.defaults() | obstacle_percent: 0}
      )

    {:ok, game} = Game.add_player(game, "ana", "Ana", @now)
    {:ok, game} = Game.add_player(game, "bruno", "Bruno", @now)
    {:ok, game} = Game.start(game, "ana", @now, 1)

    tanks =
      game.tanks
      |> Map.update!("ana", &%{&1 | position: Hex.new(0, 0, 0), ap: 5})
      |> Map.update!("bruno", &%{&1 | position: Hex.new(1, 0, -1), ap: 5})

    %{game | tanks: tanks}
  end

  # Ana acts; returns the effects of what she did.
  defp effects_of(before, action) do
    {:ok, game} = Game.act(before, "ana", action, @now)
    new_events = Enum.take(game.events, length(game.events) - length(before.events))
    GameComponents.effects_for(new_events, before, game)
  end

  describe "effects_for/3" do
    test "a shot goes from the shooter to the target" do
      assert [%{kind: :shot, from: from, to: to}] = effects_of(game(), {:shoot, "bruno"})
      assert from == Hex.to_pixel(Hex.new(0, 0, 0), 10)
      assert to == Hex.to_pixel(Hex.new(1, 0, -1), 10)
    end

    test "a destroyed tank bursts where it stood, and the win itself has no effect" do
      before = game()
      before = %{before | tanks: Map.update!(before.tanks, "bruno", &%{&1 | hp: 1})}

      assert [%{kind: :destroyed, to: to}] = effects_of(before, {:shoot, "bruno"})
      assert to == Hex.to_pixel(Hex.new(1, 0, -1), 10)
    end

    test "a move leaves tracks on every cell but the one the tank arrives on" do
      target = Hex.new(-2, 0, 2)

      assert [%{kind: :moved, trail: trail}] = effects_of(game(), {:move, target})
      assert length(trail) == 2
      assert hd(trail) == Hex.to_pixel(Hex.new(0, 0, 0), 10)
      refute Hex.to_pixel(target, 10) in trail
    end

    test "giving AP and upgrading the range have their own effects" do
      assert [%{kind: :gave_ap}] = effects_of(game(), {:give_ap, "bruno"})
      assert [%{kind: :upgraded, radius: radius}] = effects_of(game(), :upgrade_range)
      # Range 3, three steps of sqrt(3) * 10.
      assert radius == "51.96"
    end

    test "every effect gets its own id" do
      [first] = effects_of(game(), :upgrade_range)
      [second] = effects_of(game(), :upgrade_range)
      assert first.id != second.id
    end
  end
end
