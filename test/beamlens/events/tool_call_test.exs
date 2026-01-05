defmodule Beamlens.Events.ToolCallTest do
  use ExUnit.Case

  alias Beamlens.Events.ToolCall

  describe "struct" do
    test "creates with required fields" do
      now = DateTime.utc_now()

      tool_call = %ToolCall{
        intent: "get_memory_stats",
        occurred_at: now,
        result: %{total_mb: 512.0, processes_mb: 100.0}
      }

      assert tool_call.intent == "get_memory_stats"
      assert tool_call.occurred_at == now
      assert tool_call.result == %{total_mb: 512.0, processes_mb: 100.0}
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(ToolCall, %{intent: "test"})
      end
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON" do
      now = DateTime.utc_now()

      tool_call = %ToolCall{
        intent: "get_system_info",
        occurred_at: now,
        result: %{node: "test@host", uptime_seconds: 3600}
      }

      assert {:ok, json} = Jason.encode(tool_call)
      assert json =~ "get_system_info"
      assert json =~ "test@host"
    end
  end
end
