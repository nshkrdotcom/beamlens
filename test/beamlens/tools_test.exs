defmodule Beamlens.ToolsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Beamlens.Tools

  describe "schema/0" do
    test "parses get_system_info response" do
      input = %{intent: "get_system_info"}

      assert {:ok, result} = Zoi.parse(Tools.schema(), input)
      assert %Tools.GetSystemInfo{intent: "get_system_info"} = result
    end

    test "parses get_memory_stats response" do
      input = %{intent: "get_memory_stats"}

      assert {:ok, result} = Zoi.parse(Tools.schema(), input)
      assert %Tools.GetMemoryStats{intent: "get_memory_stats"} = result
    end

    test "parses get_process_stats response" do
      input = %{intent: "get_process_stats"}

      assert {:ok, result} = Zoi.parse(Tools.schema(), input)
      assert %Tools.GetProcessStats{intent: "get_process_stats"} = result
    end

    test "parses get_scheduler_stats response" do
      input = %{intent: "get_scheduler_stats"}

      assert {:ok, result} = Zoi.parse(Tools.schema(), input)
      assert %Tools.GetSchedulerStats{intent: "get_scheduler_stats"} = result
    end

    test "parses get_atom_stats response" do
      input = %{intent: "get_atom_stats"}

      assert {:ok, result} = Zoi.parse(Tools.schema(), input)
      assert %Tools.GetAtomStats{intent: "get_atom_stats"} = result
    end

    test "parses get_persistent_terms response" do
      input = %{intent: "get_persistent_terms"}

      assert {:ok, result} = Zoi.parse(Tools.schema(), input)
      assert %Tools.GetPersistentTerms{intent: "get_persistent_terms"} = result
    end

    test "parses done response with valid analysis" do
      input = %{
        intent: "done",
        analysis: %{
          status: "healthy",
          summary: "System is healthy",
          concerns: [],
          recommendations: []
        }
      }

      assert {:ok, result} = Zoi.parse(Tools.schema(), input)
      assert %Tools.Done{intent: "done", analysis: analysis} = result
      assert analysis.status == :healthy
      assert analysis.summary == "System is healthy"
    end

    test "parses done response with concerns and recommendations" do
      input = %{
        intent: "done",
        analysis: %{
          status: "warning",
          summary: "Memory pressure detected",
          concerns: ["High binary usage", "Run queue elevated"],
          recommendations: ["Monitor memory", "Scale horizontally"]
        }
      }

      assert {:ok, result} = Zoi.parse(Tools.schema(), input)
      assert %Tools.Done{analysis: analysis} = result
      assert analysis.status == :warning
      assert length(analysis.concerns) == 2
      assert length(analysis.recommendations) == 2
    end

    test "returns error for invalid intent value" do
      input = %{intent: "invalid_tool"}

      assert {:error, _reason} = Zoi.parse(Tools.schema(), input)
    end

    test "returns error for missing intent field" do
      input = %{other_field: "value"}

      assert {:error, _reason} = Zoi.parse(Tools.schema(), input)
    end

    test "returns error for done with invalid analysis status" do
      input = %{
        intent: "done",
        analysis: %{
          status: "unknown",
          summary: "Test",
          concerns: [],
          recommendations: []
        }
      }

      assert {:error, _reason} = Zoi.parse(Tools.schema(), input)
    end

    test "returns error for done with missing analysis" do
      input = %{intent: "done"}

      assert {:error, _reason} = Zoi.parse(Tools.schema(), input)
    end
  end
end
