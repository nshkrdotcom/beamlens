defmodule Beamlens.HealthAnalysis do
  @moduledoc """
  Structured health analysis returned by the BeamLens agent.

  ## Fields

    * `:status` - Overall health status (`:healthy`, `:warning`, or `:critical`)
    * `:summary` - Brief 1-2 sentence summary of findings
    * `:concerns` - List of identified concerns (empty list if none)
    * `:recommendations` - Actionable recommendations (empty list if none)
    * `:reasoning` - Brief explanation of how the assessment was reached (optional)
    * `:events` - Ordered list of events that occurred during analysis,
      providing data provenance for verification

  ## Example

      %Beamlens.HealthAnalysis{
        status: :warning,
        summary: "Memory usage is elevated but within acceptable limits.",
        concerns: ["Binary memory at 45% of total"],
        recommendations: ["Monitor binary memory growth"],
        reasoning: "Memory: 65% (warning). Process: 0.2% (healthy). Binary: 45% of total.",
        events: [
          %Beamlens.Events.LLMCall{occurred_at: ~U[...], iteration: 0, tool_selected: "get_system_info"},
          %Beamlens.Events.ToolCall{intent: "get_system_info", occurred_at: ~U[...], result: %{...}},
          %Beamlens.Events.LLMCall{occurred_at: ~U[...], iteration: 1, tool_selected: "done"}
        ]
      }
  """

  alias Beamlens.Events

  @type status :: :healthy | :warning | :critical

  @type t :: %__MODULE__{
          status: status(),
          summary: String.t(),
          concerns: [String.t()],
          recommendations: [String.t()],
          reasoning: String.t() | nil,
          events: [Events.t()]
        }

  @derive Jason.Encoder
  @enforce_keys [:status, :summary]
  defstruct [:status, :summary, :reasoning, concerns: [], recommendations: [], events: []]

  @doc """
  Returns the ZOI schema for parsing BAML output into this struct.
  """
  def schema do
    Zoi.object(%{
      status: Zoi.string() |> Zoi.transform(&parse_status/1),
      summary: Zoi.string(),
      concerns: Zoi.array(Zoi.string()),
      recommendations: Zoi.array(Zoi.string()),
      reasoning: Zoi.string() |> Zoi.optional()
    })
    |> Zoi.transform(&to_struct/1)
  end

  defp parse_status("healthy"), do: {:ok, :healthy}
  defp parse_status("warning"), do: {:ok, :warning}
  defp parse_status("critical"), do: {:ok, :critical}

  defp parse_status(invalid) do
    {:error, "invalid status '#{invalid}', expected one of: healthy, warning, critical"}
  end

  defp to_struct(map), do: {:ok, struct(__MODULE__, map)}
end
