defmodule Hextank.ModerationTest do
  use ExUnit.Case, async: true

  alias Hextank.Moderation
  alias Hextank.Moderation.Text

  doctest Hextank.Moderation
  doctest Hextank.Moderation.Text

  # Harmless stand-ins: tests never contain real slurs (CLAUDE.md).
  @words MapSet.new(["badword", "cao"])

  describe "check/2" do
    test "ignores case, accents, letter swaps and repeated letters" do
      for text <- ["BADWORD", "b4dw0rd", "baaadwooord", "b@dword", "CÃO", "c4000"] do
        assert {:error, {:prohibited, _word}} = Moderation.check(text, @words), text
      end
    end

    test "matches whole words only" do
      assert Moderation.check("badwords are fine, so is caolho", @words) == :ok
      assert {:error, {:prohibited, "badword"}} = Moderation.check("you...badword!", @words)
    end

    test "lets ordinary text through" do
      assert Moderation.check("I'll shoot you at noon, ally.", @words) == :ok
    end

    test "with a word's forms, catches its other gender, size and plural" do
      words = MapSet.new(Text.word_forms("gato"))

      for text <- ["GATA", "gatinhos", "que gatão", "gatonas", "gatões"] do
        assert {:error, {:prohibited, _word}} = Moderation.check(text, words), text
      end

      assert Moderation.check("gatilho e gateway", words) == :ok
    end
  end

  test "the real list lets the allowed words through" do
    assert Moderation.check("Eu queria um bicho, não um burro: que safado!") == :ok
  end

  test "the list file compiles into a set of normalized words" do
    assert %MapSet{} = Moderation.words()
    assert Enum.all?(Moderation.words(), &(&1 == Text.normalize(&1)))
  end
end
