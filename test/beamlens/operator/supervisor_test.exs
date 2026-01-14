defmodule Beamlens.Operator.SupervisorTest do
  @moduledoc false

  use ExUnit.Case

  alias Beamlens.Operator.Supervisor, as: OperatorSupervisor

  defmodule TestSkill do
    @behaviour Beamlens.Skill

    def title, do: "Test Skill"

    def description, do: "Test skill for supervisor tests"

    def system_prompt, do: "You are a test skill for supervisor tests."

    def snapshot do
      %{
        memory_utilization_pct: 45.0,
        process_utilization_pct: 10.0,
        port_utilization_pct: 5.0,
        atom_utilization_pct: 2.0,
        scheduler_run_queue: 0,
        schedulers_online: 8
      }
    end

    def callbacks, do: %{}

    def callback_docs, do: "Test skill callbacks"
  end

  defmodule TestSkill2 do
    @behaviour Beamlens.Skill

    def title, do: "Test Skill 2"

    def description, do: "Second test skill for supervisor tests"

    def system_prompt, do: "You are a second test skill for supervisor tests."

    def snapshot do
      %{
        memory_utilization_pct: 50.0,
        process_utilization_pct: 15.0,
        port_utilization_pct: 6.0,
        atom_utilization_pct: 3.0,
        scheduler_run_queue: 1,
        schedulers_online: 8
      }
    end

    def callbacks, do: %{}

    def callback_docs, do: "Test skill 2 callbacks"
  end

  setup do
    :persistent_term.erase({Beamlens.Supervisor, :operators})
    start_supervised!({Registry, keys: :unique, name: Beamlens.OperatorRegistry})
    {:ok, supervisor} = OperatorSupervisor.start_link(name: nil)

    on_exit(fn ->
      :persistent_term.erase({Beamlens.Supervisor, :operators})
    end)

    {:ok, supervisor: supervisor}
  end

  describe "start_operator/2 with atom spec" do
    test "returns error for unknown builtin skill", %{supervisor: supervisor} do
      result = OperatorSupervisor.start_operator(supervisor, :unknown)

      assert {:error, {:invalid_skill_module, :unknown}} = result
    end
  end

  describe "start_operator/2 with keyword spec" do
    test "starts custom operator without loop", %{supervisor: supervisor} do
      result =
        OperatorSupervisor.start_operator(supervisor,
          skill: TestSkill,
          start_loop: false
        )

      assert {:ok, pid} = result
      assert Process.alive?(pid)
    end
  end

  describe "stop_operator/2" do
    test "stops running operator", %{supervisor: supervisor} do
      {:ok, pid} =
        OperatorSupervisor.start_operator(supervisor,
          skill: TestSkill,
          start_loop: false
        )

      ref = Process.monitor(pid)
      result = OperatorSupervisor.stop_operator(supervisor, TestSkill)

      assert :ok = result
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end

    test "returns error for non-existent operator", %{supervisor: supervisor} do
      result = OperatorSupervisor.stop_operator(supervisor, :nonexistent)

      assert {:error, :not_found} = result
    end
  end

  describe "list_operators/0" do
    test "returns empty list when no operators", %{supervisor: _supervisor} do
      assert OperatorSupervisor.list_operators() == []
    end

    test "returns list of operator statuses", %{supervisor: supervisor} do
      :persistent_term.put({Beamlens.Supervisor, :operators}, [
        [skill: TestSkill],
        [skill: TestSkill2]
      ])

      on_exit(fn -> :persistent_term.erase({Beamlens.Supervisor, :operators}) end)

      OperatorSupervisor.start_operator(supervisor,
        skill: TestSkill,
        start_loop: false
      )

      OperatorSupervisor.start_operator(supervisor,
        skill: TestSkill2,
        start_loop: false
      )

      operators = OperatorSupervisor.list_operators()

      assert length(operators) == 2
      names = Enum.map(operators, & &1.name)
      assert TestSkill in names
      assert TestSkill2 in names
    end

    test "includes title and description from skill module", %{supervisor: supervisor} do
      :persistent_term.put({Beamlens.Supervisor, :operators}, [
        [skill: TestSkill]
      ])

      on_exit(fn -> :persistent_term.erase({Beamlens.Supervisor, :operators}) end)

      OperatorSupervisor.start_operator(supervisor,
        skill: TestSkill,
        start_loop: false
      )

      [operator] = OperatorSupervisor.list_operators()

      assert operator.title == "Test Skill"
      assert operator.description == "Test skill for supervisor tests"
    end

    test "includes title and description for stopped operators", %{supervisor: _supervisor} do
      :persistent_term.put({Beamlens.Supervisor, :operators}, [
        [skill: TestSkill]
      ])

      on_exit(fn -> :persistent_term.erase({Beamlens.Supervisor, :operators}) end)

      [operator] = OperatorSupervisor.list_operators()

      assert operator.running == false
      assert operator.title == "Test Skill"
      assert operator.description == "Test skill for supervisor tests"
    end
  end

  describe "operator_status/1" do
    test "returns operator status", %{supervisor: supervisor} do
      OperatorSupervisor.start_operator(supervisor,
        skill: TestSkill,
        start_loop: false
      )

      {:ok, status} = OperatorSupervisor.operator_status(TestSkill)

      assert status.operator == TestSkill
      assert status.state == :healthy
    end

    test "returns error for non-existent operator" do
      assert {:error, :not_found} = OperatorSupervisor.operator_status(:nonexistent)
    end
  end

  describe "start_operator/3 with client_registry" do
    test "passes client_registry to Operator", %{supervisor: supervisor} do
      client_registry = %{primary: "Test", clients: []}

      {:ok, pid} =
        OperatorSupervisor.start_operator(
          supervisor,
          [skill: TestSkill, start_loop: false],
          client_registry
        )

      state = :sys.get_state(pid)
      assert state.client_registry == client_registry
    end
  end
end
