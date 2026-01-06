defmodule Beamlens.Integration.InvestigationTest do
  @moduledoc """
  Integration tests for Agent.investigate/2.

  Tests the investigation flow where watcher reports are analyzed by the agent.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  alias Beamlens.{Agent, Report}

  describe "Agent.investigate/2" do
    @describetag timeout: 120_000

    test "returns :no_reports when given empty list" do
      assert {:ok, :no_reports} = Agent.investigate([])
    end

    test "investigates single report and returns health analysis" do
      report = build_report(:warning, "Memory usage elevated at 85%")

      {:ok, analysis} = Agent.investigate([report])

      assert %Beamlens.HealthAnalysis{} = analysis
      assert analysis.status in [:healthy, :warning, :critical]
      assert is_binary(analysis.summary)
      assert is_list(analysis.concerns)
      assert is_list(analysis.recommendations)
    end

    test "investigates multiple reports and correlates findings" do
      reports = [
        build_report(:warning, "Memory usage elevated at 85%"),
        build_report(:info, "Process count increased by 20%"),
        build_report(:warning, "Scheduler run queue growing")
      ]

      {:ok, analysis} = Agent.investigate(reports)

      assert %Beamlens.HealthAnalysis{} = analysis
      assert analysis.status in [:healthy, :warning, :critical]
    end

    test "first event is watcher_reports, not snapshot" do
      report = build_report(:warning, "Test anomaly")

      {:ok, analysis} = Agent.investigate([report])

      [first_event | _] = analysis.events
      assert %Beamlens.Events.ToolCall{intent: "watcher_reports"} = first_event
      assert is_map(first_event.result)
      assert Map.has_key?(first_event.result, :reports)
    end

    test "watcher_reports event contains report data" do
      report = build_report(:critical, "Critical memory exhaustion")

      {:ok, analysis} = Agent.investigate([report])

      [first_event | _] = analysis.events
      [report_data | _] = first_event.result.reports

      assert report_data.watcher == :beam
      assert report_data.severity == :critical
      assert is_binary(report_data.summary)
    end

    test "includes LLMCall events showing agent reasoning" do
      report = build_report(:warning, "Elevated memory usage")

      {:ok, analysis} = Agent.investigate([report])

      llm_calls =
        Enum.filter(analysis.events, &match?(%Beamlens.Events.LLMCall{}, &1))

      assert llm_calls != [], "Expected at least one LLMCall event"

      [first_llm_call | _] = llm_calls
      assert is_binary(first_llm_call.tool_selected)
      assert %DateTime{} = first_llm_call.occurred_at
    end

    test "includes JudgeCall event when judge is enabled (default)" do
      report = build_report(:warning, "Test anomaly")

      {:ok, analysis} = Agent.investigate([report])

      judge_calls =
        Enum.filter(analysis.events, &match?(%Beamlens.Events.JudgeCall{}, &1))

      assert judge_calls != [], "Expected at least one JudgeCall event"

      [judge_call | _] = judge_calls
      assert judge_call.verdict in [:accept, :retry]
      assert judge_call.confidence in [:high, :medium, :low]
    end

    test "excludes JudgeCall events when judge is disabled" do
      report = build_report(:warning, "Test anomaly")

      {:ok, analysis} = Agent.investigate([report], judge: false)

      judge_calls =
        Enum.filter(analysis.events, &match?(%Beamlens.Events.JudgeCall{}, &1))

      assert judge_calls == [], "Expected no JudgeCall events when judge: false"
    end
  end

  defp build_report(severity, summary) do
    Report.new(%{
      watcher: :beam,
      anomaly_type: :memory_elevated,
      severity: severity,
      summary: summary,
      snapshot: %{
        memory_utilization_pct: 85.0,
        process_count: 150,
        scheduler_run_queue: 5
      }
    })
  end
end
