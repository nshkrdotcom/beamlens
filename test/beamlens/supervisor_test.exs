defmodule Beamlens.SupervisorTest do
  use ExUnit.Case, async: false

  describe "start_link/1" do
    test "starts supervisor" do
      {:ok, supervisor} = start_supervised({Beamlens.Supervisor, []})

      assert Process.alive?(supervisor)
    end
  end

  describe "quick start pattern" do
    test "lists configured operators" do
      {:ok, _supervisor} =
        start_supervised(
          {Beamlens,
           operators: [
             [skill: Beamlens.Skill.Beam],
             [skill: Beamlens.Skill.Ets],
             [skill: Beamlens.Skill.System]
           ]}
        )

      # Verify operators are listed correctly
      operators = Beamlens.list_operators()

      assert length(operators) == 3
      assert Enum.all?(operators, &(&1.running == false))

      names = Enum.map(operators, & &1.name)
      assert Beamlens.Skill.Beam in names
      assert Beamlens.Skill.Ets in names
      assert Beamlens.Skill.System in names

      # Verify each operator has expected structure (stopped until manually started)
      beam_op = Enum.find(operators, &(&1.name == Beamlens.Skill.Beam))
      assert beam_op.state == :stopped
      assert beam_op.title == "BEAM VM"
    end
  end
end
