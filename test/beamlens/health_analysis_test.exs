defmodule Beamlens.HealthAnalysisTest do
  use ExUnit.Case

  alias Beamlens.HealthAnalysis

  describe "schema/0" do
    test "parses valid BAML output with healthy status" do
      baml_output = %{
        status: "healthy",
        summary: "BEAM VM is operating normally",
        concerns: [],
        recommendations: []
      }

      assert {:ok, analysis} = Zoi.parse(HealthAnalysis.schema(), baml_output)
      assert %HealthAnalysis{} = analysis
      assert analysis.status == :healthy
      assert analysis.summary == "BEAM VM is operating normally"
      assert analysis.concerns == []
      assert analysis.recommendations == []
    end

    test "parses valid BAML output with warning status" do
      baml_output = %{
        status: "warning",
        summary: "High memory usage detected",
        concerns: ["Memory usage at 85%"],
        recommendations: ["Consider increasing memory allocation"]
      }

      assert {:ok, analysis} = Zoi.parse(HealthAnalysis.schema(), baml_output)
      assert analysis.status == :warning
      assert analysis.concerns == ["Memory usage at 85%"]
    end

    test "parses valid BAML output with critical status" do
      baml_output = %{
        status: "critical",
        summary: "System is under heavy load",
        concerns: ["Run queue too high", "Memory exhaustion imminent"],
        recommendations: ["Scale horizontally", "Increase process limits"]
      }

      assert {:ok, analysis} = Zoi.parse(HealthAnalysis.schema(), baml_output)
      assert analysis.status == :critical
      assert length(analysis.concerns) == 2
      assert length(analysis.recommendations) == 2
    end

    test "parses analysis with reasoning field" do
      baml_output = %{
        status: "warning",
        summary: "Memory elevated at 70%",
        concerns: ["High memory usage"],
        recommendations: ["Monitor memory"],
        reasoning: "Memory utilization is above 60% threshold but below critical 85%."
      }

      assert {:ok, analysis} = Zoi.parse(HealthAnalysis.schema(), baml_output)

      assert analysis.reasoning ==
               "Memory utilization is above 60% threshold but below critical 85%."
    end

    test "reasoning field is optional" do
      baml_output = %{
        status: "healthy",
        summary: "All metrics nominal",
        concerns: [],
        recommendations: []
      }

      assert {:ok, analysis} = Zoi.parse(HealthAnalysis.schema(), baml_output)
      assert analysis.reasoning == nil
    end

    test "returns error for invalid status value" do
      baml_output = %{
        status: "unknown",
        summary: "Test summary",
        concerns: [],
        recommendations: []
      }

      assert {:error, _reason} = Zoi.parse(HealthAnalysis.schema(), baml_output)
    end

    test "returns error for uppercase status value" do
      baml_output = %{
        status: "HEALTHY",
        summary: "Test summary",
        concerns: [],
        recommendations: []
      }

      assert {:error, _reason} = Zoi.parse(HealthAnalysis.schema(), baml_output)
    end
  end

  describe "struct" do
    test "creates with events field defaulting to empty list" do
      analysis = %HealthAnalysis{
        status: :healthy,
        summary: "All good"
      }

      assert analysis.events == []
    end

    test "creates with events" do
      now = DateTime.utc_now()

      events = [
        %Beamlens.Events.LLMCall{
          occurred_at: now,
          iteration: 0,
          tool_selected: "get_system_info"
        },
        %Beamlens.Events.ToolCall{
          intent: "get_system_info",
          occurred_at: now,
          result: %{node: "test@host"}
        }
      ]

      analysis = %HealthAnalysis{
        status: :healthy,
        summary: "All good",
        events: events
      }

      assert length(analysis.events) == 2
    end
  end

  describe "JSON encoding" do
    test "encodes analysis with events to JSON" do
      now = DateTime.utc_now()

      analysis = %HealthAnalysis{
        status: :warning,
        summary: "Memory elevated",
        concerns: ["High memory"],
        recommendations: ["Monitor"],
        events: [
          %Beamlens.Events.LLMCall{
            occurred_at: now,
            iteration: 0,
            tool_selected: "get_memory_stats"
          }
        ]
      }

      assert {:ok, json} = Jason.encode(analysis)
      assert json =~ "warning"
      assert json =~ "get_memory_stats"
    end
  end
end
