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

    test "a destroyed tank bursts where it stood; the win only moves the camera" do
      before = game()
      before = %{before | tanks: Map.update!(before.tanks, "bruno", &%{&1 | hp: 1})}

      assert [%{kind: :won, cells: []}, %{kind: :destroyed, to: to}] =
               effects_of(before, {:shoot, "bruno"})

      assert to == Hex.to_pixel(Hex.new(1, 0, -1), 10)
    end

    test "a move drives along the shortest path, around rocks, leaving tread marks" do
      before = %{game() | board: Hextank.Board.new(4, [Hex.new(-1, 0, 1)])}

      # The rock at (-1, 0, 1) is in the way: 3 legs instead of 2.
      assert [%{kind: :moved} = effect] = effects_of(before, {:move, Hex.new(-2, 0, 2)})
      assert length(effect.tracks) == 6

      # Each pair of marks runs either side of a leg: their middle is the cell the
      # leg starts from, never the rock.
      starts =
        effect.tracks
        |> Enum.chunk_every(2)
        |> Enum.map(fn [one, other] -> middle(one.from, other.from) end)

      assert hd(starts) == rounded(Hex.to_pixel(Hex.new(0, 0, 0), 10))
      refute rounded(Hex.to_pixel(Hex.new(-1, 0, 1), 10)) in starts

      # The tank, its hull and (since it hasn't aimed at anyone) its turret move.
      assert %{drive: drive, hull: hull, turret: hull} = effect.animations
      assert drive =~ "#{effect.id}-drive "
      assert effect.css =~ "@keyframes #{effect.id}-drive"
      assert effect.css =~ "@keyframes #{effect.id}-hull"
    end

    test "a shot turns the turret first; after that, moving leaves the turret alone" do
      {:ok, aimed} = Game.act(game(), "ana", {:shoot, "bruno"}, @now)
      assert [%{kind: :shot} = shot] = effects_of(game(), {:shoot, "bruno"})
      assert shot.animations.turret =~ "#{shot.id}-turret "
      assert shot.css =~ "@keyframes #{shot.id}-turret"

      assert [%{kind: :moved} = move] = effects_of(aimed, {:move, Hex.new(-2, 0, 2)})
      refute Map.has_key?(move.animations, :turret)
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

  defp middle({x1, y1}, {x2, y2}), do: rounded({(x1 + x2) / 2, (y1 + y2) / 2})
  defp rounded({x, y}), do: {Float.round(x, 2), Float.round(y, 2)}
end
