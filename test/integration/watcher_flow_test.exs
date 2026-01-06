defmodule Beamlens.Integration.WatcherFlowTest do
  @moduledoc """
  Integration tests for the watcher → report → investigation flow.

  Tests the full orchestrator-workers pattern where:
  1. Reports are pushed to ReportQueue
  2. ReportHandler receives notification
  3. Agent.investigate/2 is called
  4. HealthAnalysis is produced
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias Beamlens.{Report, ReportHandler, ReportQueue}

  describe "ReportHandler.investigate/1 with real LLM" do
    @describetag timeout: 120_000

    setup do
      {:ok, queue} = start_supervised(ReportQueue)
      {:ok, handler} = start_supervised({ReportHandler, trigger: :manual})
      {:ok, queue: queue, handler: handler}
    end

    test "investigates pending reports and returns analysis", %{handler: handler} do
      report = build_report(:warning, "Memory elevated to 80%")
      ReportQueue.push(report)

      assert ReportHandler.pending?(handler)

      {:ok, analysis} = ReportHandler.investigate(handler)

      assert %Beamlens.HealthAnalysis{} = analysis
      assert analysis.status in [:healthy, :warning, :critical]
      refute ReportHandler.pending?(handler)
    end

    test "returns :no_reports when queue is empty", %{handler: handler} do
      refute ReportHandler.pending?(handler)

      {:ok, :no_reports} = ReportHandler.investigate(handler)
    end

    test "processes multiple reports in single investigation", %{handler: handler} do
      reports = [
        build_report(:warning, "Memory elevated"),
        build_report(:info, "Process count spike"),
        build_report(:warning, "Run queue growing")
      ]

      Enum.each(reports, &ReportQueue.push/1)
      assert ReportQueue.count() == 3

      {:ok, analysis} = ReportHandler.investigate(handler)

      assert %Beamlens.HealthAnalysis{} = analysis
      assert ReportQueue.count() == 0
    end

    test "analysis includes watcher_reports as first event", %{handler: handler} do
      report = build_report(:critical, "Critical memory exhaustion")
      ReportQueue.push(report)

      {:ok, analysis} = ReportHandler.investigate(handler)

      [first_event | _] = analysis.events
      assert %Beamlens.Events.ToolCall{intent: "watcher_reports"} = first_event
    end
  end

  describe "Full supervision tree flow" do
    @describetag timeout: 120_000

    test "Beamlens.investigate/0 processes pending reports" do
      {:ok, _supervisor} =
        start_supervised(
          {Beamlens,
           watchers: [], report_handler: [trigger: :manual], circuit_breaker: [enabled: false]}
        )

      report = build_report(:warning, "Test anomaly from watcher")
      ReportQueue.push(report)

      {:ok, analysis} = Beamlens.investigate()

      assert %Beamlens.HealthAnalysis{} = analysis
      assert analysis.status in [:healthy, :warning, :critical]
    end

    test "Beamlens.pending_reports?/0 reflects queue state" do
      {:ok, _supervisor} =
        start_supervised(
          {Beamlens,
           watchers: [], report_handler: [trigger: :manual], circuit_breaker: [enabled: false]}
        )

      refute Beamlens.pending_reports?()

      report = build_report(:info, "Test report")
      ReportQueue.push(report)

      assert Beamlens.pending_reports?()
    end
  end

  defp build_report(severity, summary) do
    Report.new(%{
      watcher: :beam,
      anomaly_type: :memory_elevated,
      severity: severity,
      summary: summary,
      snapshot: %{
        memory_utilization_pct: 80.0,
        process_count: 120,
        scheduler_run_queue: 3
      }
    })
  end
end
