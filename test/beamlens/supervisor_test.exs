defmodule Beamlens.SupervisorTest do
  use ExUnit.Case, async: false

  describe "start_link/1 with client_registry" do
    test "starts supervisor with client_registry" do
      client_registry = %{primary: "Test", clients: []}

      {:ok, supervisor} =
        start_supervised({Beamlens.Supervisor, client_registry: client_registry, watchers: []})

      assert Process.alive?(supervisor)
    end
  end

  describe "quick start pattern" do
    test "starts with on_demand operators that can be listed" do
      {:ok, _supervisor} =
        start_supervised(
          {Beamlens,
           operators: [
             [name: :beam, skill: Beamlens.Skill.Beam, mode: :on_demand],
             [name: :ets, skill: Beamlens.Skill.Ets, mode: :on_demand],
             [name: :system, skill: Beamlens.Skill.System, mode: :on_demand]
           ]}
        )

      # Verify operators are listed correctly as shown in Quick Start
      operators = Beamlens.list_operators()

      assert length(operators) == 3
      assert Enum.all?(operators, &(&1.running == false))

      names = Enum.map(operators, & &1.name)
      assert :beam in names
      assert :ets in names
      assert :system in names

      # Verify each operator has expected structure
      beam_op = Enum.find(operators, &(&1.name == :beam))
      assert beam_op.state == :healthy
      assert beam_op.title == "BEAM VM"
    end

    test "coordinator is started by supervisor" do
      {:ok, _supervisor} =
        start_supervised(
          {Beamlens,
           operators: [
             [name: :beam, skill: Beamlens.Skill.Beam, mode: :on_demand]
           ]}
        )

      # Verify the supervisor-started coordinator is accessible
      status = Beamlens.Coordinator.status()

      assert status.running == false
      assert status.notification_count == 0
      assert status.iteration == 0
    end
  end
end
