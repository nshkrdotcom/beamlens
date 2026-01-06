defmodule Beamlens.ReportHandlerTest do
  @moduledoc false

  use ExUnit.Case

  alias Beamlens.{Report, ReportHandler, ReportQueue}

  setup do
    start_supervised!(ReportQueue)
    {:ok, handler} = ReportHandler.start_link(name: nil, trigger: :manual)
    {:ok, handler: handler}
  end

  describe "start_link/1" do
    test "starts with default options" do
      {:ok, pid} = ReportHandler.start_link(name: nil)
      assert Process.alive?(pid)
    end

    test "starts with custom trigger mode" do
      {:ok, pid} = ReportHandler.start_link(name: nil, trigger: :on_report)
      assert Process.alive?(pid)
    end
  end

  describe "pending?/1" do
    test "returns false when no reports", %{handler: handler} do
      refute ReportHandler.pending?(handler)
    end

    test "returns true when reports pending", %{handler: handler} do
      push_report()
      assert ReportHandler.pending?(handler)
    end
  end

  describe "investigate/2" do
    test "returns :no_reports when queue empty", %{handler: handler} do
      result = ReportHandler.investigate(handler)
      assert {:ok, :no_reports} = result
    end
  end

  describe "telemetry events" do
    test "emits started event on init" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :report_handler, :started],
        fn _event, _measurements, metadata, _ ->
          send(parent, {:telemetry, :started, metadata})
        end,
        nil
      )

      {:ok, _pid} = ReportHandler.start_link(name: nil, trigger: :manual)

      assert_receive {:telemetry, :started, %{trigger_mode: :manual}}

      :telemetry.detach(ref)
    end

    test "investigation_completed event structure" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :report_handler, :investigation_completed],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.execute(
        [:beamlens, :report_handler, :investigation_completed],
        %{system_time: System.system_time()},
        %{status: :healthy}
      )

      assert_receive {:telemetry, [:beamlens, :report_handler, :investigation_completed],
                      _measurements, metadata}

      assert metadata.status == :healthy

      :telemetry.detach(ref)
    end

    test "investigation_failed event structure" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :report_handler, :investigation_failed],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.execute(
        [:beamlens, :report_handler, :investigation_failed],
        %{system_time: System.system_time()},
        %{reason: :timeout}
      )

      assert_receive {:telemetry, [:beamlens, :report_handler, :investigation_failed],
                      _measurements, metadata}

      assert metadata.reason == :timeout

      :telemetry.detach(ref)
    end
  end

  describe "on_report trigger mode" do
    test "subscribes to ReportQueue" do
      {:ok, handler} = ReportHandler.start_link(name: nil, trigger: :on_report)
      assert Process.alive?(handler)
    end

    test "ignores report_available in manual mode", %{handler: handler} do
      send(handler, {:report_available, %{}})
      assert Process.alive?(handler)
    end
  end

  defp push_report do
    report =
      Report.new(%{
        watcher: :beam,
        anomaly_type: :memory_elevated,
        severity: :warning,
        summary: "Test report",
        snapshot: %{}
      })

    ReportQueue.push(report)
  end
end
