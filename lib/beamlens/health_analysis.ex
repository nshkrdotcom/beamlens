defmodule Beamlens.HealthAnalysis do
  @moduledoc """
  Structured health analysis returned by the BeamLens agent.

  ## Fields

    * `:status` - Overall health status (`:healthy`, `:warning`, or `:critical`)
    * `:summary` - Brief 1-2 sentence summary of findings
    * `:concerns` - List of identified concerns (empty list if none)
    * `:recommendations` - Actionable recommendations (empty list if none)

  ## Example

      %Beamlens.HealthAnalysis{
        status: :warning,
        summary: "Memory usage is elevated but within acceptable limits.",
        concerns: ["Binary memory at 45% of total"],
        recommendations: ["Monitor binary memory growth"]
      }
  """

  @type status :: :healthy | :warning | :critical

  @type t :: %__MODULE__{
          status: status(),
          summary: String.t(),
          concerns: [String.t()],
          recommendations: [String.t()]
        }

  @derive Jason.Encoder
  @enforce_keys [:status, :summary]
  defstruct [:status, :summary, concerns: [], recommendations: []]

  @doc """
  Returns the ZOI schema for parsing BAML output into this struct.
  """
  def schema do
    Zoi.object(%{
      status: Zoi.string() |> Zoi.transform(&parse_status/1),
      summary: Zoi.string(),
      concerns: Zoi.array(Zoi.string()),
      recommendations: Zoi.array(Zoi.string())
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
