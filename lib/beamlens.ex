defmodule Beamlens do
  @moduledoc """
  BeamLens - AI-powered BEAM VM health monitoring.

  Specialized **watchers** autonomously monitor BEAM VM metrics using LLM-driven
  loops, detect anomalies, and fire alerts via telemetry when issues are found.

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────────┐
  │                      Watcher (Autonomous)                   │
  │  1. LLM controls timing via wait tool                       │
  │  2. Collects snapshots, analyzes patterns                   │
  │  3. Fires alerts via telemetry when anomalies detected      │
  │  4. Maintains state: healthy → observing → warning → critical│
  └─────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌────────────────────────────┐
              │     Telemetry Events       │
              │  [:beamlens, :watcher, *]  │
              │  - alert_fired             │
              │  - state_change            │
              │  - iteration_start         │
              └────────────────────────────┘
  ```

  ## Installation

  Add to your dependencies:

      {:beamlens, "~> 0.1.0"}

  ## Supervision Tree Setup

  Add BeamLens to your application's supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {Beamlens, watchers: [:beam]}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  ## Configuration Options

  Options passed to `Beamlens`:

    * `:watchers` - List of watcher configurations (see below)
    * `:client_registry` - LLM provider configuration (see below)

  ### LLM Provider Configuration

  By default, BeamLens uses Anthropic (requires `ANTHROPIC_API_KEY` env var).
  Configure a custom provider via `:client_registry`:

      {Beamlens,
        watchers: [:beam],
        client_registry: %{
          primary: "Ollama",
          clients: [
            %{
              name: "Ollama",
              provider: "openai-generic",
              options: %{base_url: "http://localhost:11434/v1", model: "qwen3:4b"}
            }
          ]
        }}

  Supported providers include: `anthropic`, `openai`, `openai-generic` (Ollama),
  `aws-bedrock`, `google-ai`, `azure-openai`, and more.

  ### Watcher Configuration

  Watchers can be specified as atoms or keyword lists:

      # Built-in BEAM watcher
      :beam

      # Custom domain module
      [name: :postgres, domain_module: MyApp.Domain.Postgres]

  ## Runtime API

      # List all running watchers
      Beamlens.list_watchers()

      # Get status of a specific watcher
      Beamlens.watcher_status(:beam)

  ## Telemetry Events

  BeamLens emits telemetry events for observability. See `Beamlens.Telemetry`
  for the full list of events.

  Subscribe to alert events:

      :telemetry.attach("beamlens-alerts", [:beamlens, :watcher, :alert_fired], fn
        _event, _measurements, metadata, _config ->
          IO.inspect(metadata, label: "Alert fired")
      end, nil)
  """

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(opts) do
    Beamlens.Supervisor.start_link(opts)
  end

  @doc """
  Lists all running watchers with their status.

  Returns a list of maps with watcher information including:
    * `:name` - Watcher name
    * `:watcher` - Domain being monitored
    * `:state` - Current watcher state (healthy, observing, warning, critical)
    * `:running` - Whether the watcher loop is running
  """
  defdelegate list_watchers(), to: Beamlens.Watcher.Supervisor

  @doc """
  Gets the status of a specific watcher.

  Returns `{:ok, status}` on success, `{:error, :not_found}` if watcher doesn't exist.
  """
  defdelegate watcher_status(name), to: Beamlens.Watcher.Supervisor
end
