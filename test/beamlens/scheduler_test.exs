defmodule Beamlens.SchedulerTest do
  use ExUnit.Case, async: false

  alias Beamlens.Scheduler

  # Use a fake run function for tests
  defp fake_run(_opts), do: {:ok, %{status: :healthy}}

  setup do
    # Stop the application supervisor to prevent conflicts with test instances
    # This stops both Scheduler and TaskSupervisor
    case Process.whereis(Beamlens.Supervisor) do
      nil ->
        :ok

      pid ->
        ref = Process.monitor(pid)
        Supervisor.stop(pid, :shutdown)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          1000 -> :ok
        end
    end

    :ok
  end

  describe "init/1" do
    test "starts with valid schedules" do
      opts = [
        schedules: [[name: :test, cron: "*/5 * * * *"]],
        run_fun: &fake_run/1
      ]

      assert {:ok, pid} = GenServer.start_link(Scheduler, opts)
      GenServer.stop(pid)
    end

    test "fails on invalid cron" do
      Process.flag(:trap_exit, true)

      opts = [
        schedules: [[name: :bad, cron: "invalid"]],
        run_fun: &fake_run/1
      ]

      assert {:error, {:invalid_cron, :bad, _}} = GenServer.start_link(Scheduler, opts)
    end

    test "fails on duplicate schedule names" do
      Process.flag(:trap_exit, true)

      opts = [
        schedules: [
          [name: :dupe, cron: "* * * * *"],
          [name: :dupe, cron: "*/5 * * * *"]
        ],
        run_fun: &fake_run/1
      ]

      assert {:error, {:duplicate_schedule, :dupe}} = GenServer.start_link(Scheduler, opts)
    end

    test "starts with empty schedules" do
      opts = [schedules: [], run_fun: &fake_run/1]
      assert {:ok, pid} = GenServer.start_link(Scheduler, opts)
      GenServer.stop(pid)
    end
  end

  describe "list_schedules/0" do
    test "returns sanitized schedule maps" do
      opts = [
        schedules: [
          [name: :frequent, cron: "*/5 * * * *"],
          [name: :hourly, cron: "0 * * * *"]
        ],
        run_fun: &fake_run/1
      ]

      {:ok, pid} = GenServer.start_link(Scheduler, opts, name: Scheduler)

      try do
        schedules = Scheduler.list_schedules()

        assert length(schedules) == 2
        assert Enum.all?(schedules, &is_map/1)
        assert Enum.all?(schedules, &Map.has_key?(&1, :name))
        assert Enum.all?(schedules, &Map.has_key?(&1, :running?))
        refute Enum.any?(schedules, &Map.has_key?(&1, :timer_ref))
      after
        GenServer.stop(pid)
      end
    end
  end

  describe "get_schedule/1" do
    test "returns schedule by name" do
      opts = [
        schedules: [[name: :test, cron: "*/5 * * * *"]],
        run_fun: &fake_run/1
      ]

      {:ok, pid} = GenServer.start_link(Scheduler, opts, name: Scheduler)

      try do
        schedule = Scheduler.get_schedule(:test)

        assert schedule.name == :test
        assert schedule.cron == "*/5 * * * *"
      after
        GenServer.stop(pid)
      end
    end

    test "returns nil for unknown schedule" do
      opts = [schedules: [], run_fun: &fake_run/1]
      {:ok, pid} = GenServer.start_link(Scheduler, opts, name: Scheduler)

      try do
        assert Scheduler.get_schedule(:unknown) == nil
      after
        GenServer.stop(pid)
      end
    end
  end

  describe "run_now/1" do
    test "returns :ok when schedule exists and is idle" do
      test_pid = self()

      run_fun = fn opts ->
        send(test_pid, {:run_called, opts})
        {:ok, %{status: :healthy}}
      end

      opts = [
        schedules: [[name: :test, cron: "0 0 1 1 *"]],
        run_fun: run_fun
      ]

      # Start TaskSupervisor for this test
      {:ok, sup} = Task.Supervisor.start_link(name: Beamlens.TaskSupervisor)
      {:ok, pid} = GenServer.start_link(Scheduler, opts, name: Scheduler)

      try do
        assert :ok = Scheduler.run_now(:test)

        # Wait for the task to run
        assert_receive {:run_called, _opts}, 1000
      after
        GenServer.stop(pid)
        Supervisor.stop(sup)
      end
    end

    test "returns error for unknown schedule" do
      opts = [schedules: [], run_fun: &fake_run/1]
      {:ok, pid} = GenServer.start_link(Scheduler, opts, name: Scheduler)

      try do
        assert {:error, :not_found} = Scheduler.run_now(:unknown)
      after
        GenServer.stop(pid)
      end
    end

    test "returns error when already running" do
      # Use a run_fun that blocks until signaled
      test_pid = self()

      run_fun = fn _opts ->
        send(test_pid, :started)

        receive do
          :continue -> {:ok, %{status: :healthy}}
        end
      end

      opts = [
        schedules: [[name: :test, cron: "0 0 1 1 *"]],
        run_fun: run_fun
      ]

      {:ok, sup} = Task.Supervisor.start_link(name: Beamlens.TaskSupervisor)
      {:ok, pid} = GenServer.start_link(Scheduler, opts, name: Scheduler)

      try do
        # First run starts
        assert :ok = Scheduler.run_now(:test)
        assert_receive :started, 1000

        # Second run should fail
        assert {:error, :already_running} = Scheduler.run_now(:test)
      after
        GenServer.stop(pid)
        Supervisor.stop(sup)
      end
    end
  end

  describe "crash isolation" do
    test "scheduler survives task crash" do
      run_fun = fn _opts ->
        raise "boom!"
      end

      opts = [
        schedules: [[name: :crasher, cron: "0 0 1 1 *"]],
        run_fun: run_fun
      ]

      {:ok, sup} = Task.Supervisor.start_link(name: Beamlens.TaskSupervisor)
      {:ok, pid} = GenServer.start_link(Scheduler, opts, name: Scheduler)

      try do
        # Trigger the crash
        assert :ok = Scheduler.run_now(:crasher)

        # Wait for crash to clear running state (poll with :sys.get_state)
        wait_until(fn ->
          schedule = Scheduler.get_schedule(:crasher)
          schedule.running? == false
        end)

        # Scheduler should still be alive
        assert Process.alive?(pid)

        # Schedule should be cleared (not running anymore)
        schedule = Scheduler.get_schedule(:crasher)
        assert schedule.running? == false
      after
        GenServer.stop(pid)
        Supervisor.stop(sup)
      end
    end
  end

  # Helper to wait for a condition without Process.sleep
  defp wait_until(fun, timeout \\ 1000, interval \\ 10) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline, interval)
  end

  defp do_wait_until(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        raise "Timed out waiting for condition"
      else
        :timer.sleep(interval)
        do_wait_until(fun, deadline, interval)
      end
    end
  end

  describe "agent opts merging" do
    test "merges global and per-schedule opts" do
      test_pid = self()

      run_fun = fn opts ->
        send(test_pid, {:opts_received, opts})
        {:ok, %{status: :healthy}}
      end

      opts = [
        schedules: [[name: :test, cron: "0 0 1 1 *", agent_opts: [timeout: 5000]]],
        agent_opts: [max_iterations: 10, timeout: 1000],
        run_fun: run_fun
      ]

      {:ok, sup} = Task.Supervisor.start_link(name: Beamlens.TaskSupervisor)
      {:ok, pid} = GenServer.start_link(Scheduler, opts, name: Scheduler)

      try do
        Scheduler.run_now(:test)

        assert_receive {:opts_received, received_opts}, 1000

        # Per-schedule timeout should override global
        assert Keyword.get(received_opts, :timeout) == 5000
        # Global max_iterations should be present
        assert Keyword.get(received_opts, :max_iterations) == 10
        # trace_id should be added
        assert Keyword.has_key?(received_opts, :trace_id)
      after
        GenServer.stop(pid)
        Supervisor.stop(sup)
      end
    end
  end
end
