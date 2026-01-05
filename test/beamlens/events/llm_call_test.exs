defmodule Beamlens.Events.LLMCallTest do
  use ExUnit.Case

  alias Beamlens.Events.LLMCall

  describe "struct" do
    test "creates with required fields" do
      now = DateTime.utc_now()

      llm_call = %LLMCall{
        occurred_at: now,
        iteration: 0,
        tool_selected: "get_system_info"
      }

      assert llm_call.occurred_at == now
      assert llm_call.iteration == 0
      assert llm_call.tool_selected == "get_system_info"
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(LLMCall, %{iteration: 0})
      end
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON" do
      now = DateTime.utc_now()

      llm_call = %LLMCall{
        occurred_at: now,
        iteration: 2,
        tool_selected: "done"
      }

      assert {:ok, json} = Jason.encode(llm_call)
      assert json =~ "done"
      assert json =~ "2"
    end
  end
end
