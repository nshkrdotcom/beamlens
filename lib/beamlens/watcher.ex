defmodule Beamlens.Watcher do
  @moduledoc """
  GenServer that runs a watcher in a continuous LLM-driven loop.

  The LLM has full control over timing via the `wait` tool. The loop runs:

  1. Collect snapshot
  2. Send to LLM with current state
  3. LLM returns action (set_state, fire_alert, get_alerts, execute, wait)
  4. Execute action and loop

  The `wait` tool lets the LLM control its own cadence:
  - Normal operation: wait(30000) -- 30 seconds
  - Elevated concern: wait(5000) -- 5 seconds
  - Critical monitoring: wait(1000) -- 1 second

  ## State Model

  The watcher maintains one of four states:
  - `:healthy` - Everything is normal
  - `:observing` - Something looks off, gathering more data
  - `:warning` - Elevated concern, but not critical
  - `:critical` - Active issue requiring immediate attention

  ## Example

      {:ok, pid} = Beamlens.Watcher.start_link(
        name: {:via, Registry, {MyRegistry, :beam}},
        domain_module: Beamlens.Domain.Beam
      )
  """

  use GenServer

  alias Beamlens.Telemetry
  alias Beamlens.Watcher.{Alert, Snapshot, Tools}

  alias Beamlens.Watcher.Tools.{
    Execute,
    FireAlert,
    GetAlerts,
    GetSnapshot,
    GetSnapshots,
    SetState,
    TakeSnapshot,
    Wait
  }

  alias Puck.Context
  alias Puck.Sandbox.Eval

  @max_iterations 100

  defstruct [
    :name,
    :domain_module,
    :client,
    :client_registry,
    :context,
    alerts: [],
    snapshots: [],
    iteration: 0,
    state: :healthy,
    running: false
  ]

  @doc """
  Starts a watcher process.

  ## Options

    * `:name` - Optional process name for registration
    * `:domain_module` - Required module implementing `Beamlens.Domain`
    * `:client_registry` - Optional LLM provider configuration map
    * `:start_loop` - Whether to start the LLM loop on init (default: true)

  """
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Returns the current watcher status.

  Returns a map with:
    * `:watcher` - Domain atom (e.g., `:beam`)
    * `:state` - Current state (`:healthy`, `:observing`, `:warning`, `:critical`)
    * `:running` - Boolean indicating if the loop is active

  """
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Stops the watcher process.
  """
  def stop(server) do
    GenServer.stop(server)
  end

  @impl true
  def init(opts) do
    domain_module = Keyword.fetch!(opts, :domain_module)
    name = Keyword.get(opts, :name)
    client_registry = Keyword.get(opts, :client_registry)
    start_loop = Keyword.get(opts, :start_loop, true)
    client = build_puck_client(client_registry)

    state = %__MODULE__{
      name: name,
      domain_module: domain_module,
      client: client,
      client_registry: client_registry,
      context: Context.new(metadata: %{iteration: 0}),
      iteration: 0,
      state: :healthy,
      running: start_loop
    }

    emit_telemetry(:started, state)

    if start_loop do
      {:ok, state, {:continue, :loop}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:loop, %{iteration: iteration} = state) when iteration >= @max_iterations do
    emit_telemetry(:loop_stopped, state, %{final_state: state.state})
    {:noreply, %{state | running: false}}
  end

  def handle_continue(:loop, state) do
    trace_id = Telemetry.generate_trace_id()

    emit_telemetry(:iteration_start, state, %{
      trace_id: trace_id,
      iteration: state.iteration,
      watcher_state: state.state
    })

    input = build_input(state.state)

    case Puck.call(state.client, input, state.context, output_schema: Tools.schema()) do
      {:ok, response, new_context} ->
        handle_action(response.content, %{state | context: new_context}, trace_id)

      {:error, reason} ->
        emit_telemetry(:llm_error, state, %{trace_id: trace_id, reason: reason})
        {:noreply, %{state | running: false}}
    end
  end

  @impl true
  def handle_info(:continue_loop, state) do
    {:noreply, state, {:continue, :loop}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      watcher: state.domain_module.domain(),
      state: state.state,
      running: state.running
    }

    {:reply, status, state}
  end

  defp handle_action(%SetState{state: new_state, reason: reason}, state, trace_id) do
    emit_telemetry(:state_change, state, %{
      trace_id: trace_id,
      from: state.state,
      to: new_state,
      reason: reason
    })

    new_state = %{state | state: new_state, iteration: state.iteration + 1}
    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(
         %FireAlert{type: type, summary: summary, severity: severity, snapshot_ids: snapshot_ids},
         state,
         trace_id
       ) do
    case resolve_snapshots(snapshot_ids, state.snapshots) do
      {:ok, snapshots} ->
        alert = build_alert(state, type, summary, severity, snapshots)

        emit_telemetry(:alert_fired, state, %{
          trace_id: trace_id,
          alert: alert
        })

        new_state = %{state | alerts: state.alerts ++ [alert], iteration: state.iteration + 1}
        {:noreply, new_state, {:continue, :loop}}

      {:error, reason} ->
        emit_telemetry(:alert_failed, state, %{trace_id: trace_id, reason: reason})

        new_context = add_result(state.context, %{error: reason})
        new_state = %{state | context: new_context, iteration: state.iteration + 1}
        {:noreply, new_state, {:continue, :loop}}
    end
  end

  defp handle_action(%GetAlerts{}, state, trace_id) do
    alerts = state.alerts

    emit_telemetry(:get_alerts, state, %{
      trace_id: trace_id,
      count: length(alerts)
    })

    new_context = add_result(state.context, alerts)
    new_state = %{state | context: new_context, iteration: state.iteration + 1}
    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%TakeSnapshot{}, state, trace_id) do
    data = collect_snapshot(state)
    snapshot = Snapshot.new(data)

    emit_telemetry(:take_snapshot, state, %{trace_id: trace_id, snapshot_id: snapshot.id})

    new_context = add_result(state.context, snapshot)

    new_state = %{
      state
      | context: new_context,
        snapshots: state.snapshots ++ [snapshot],
        iteration: state.iteration + 1
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%GetSnapshot{id: id}, state, trace_id) do
    emit_telemetry(:get_snapshot, state, %{trace_id: trace_id, snapshot_id: id})

    result =
      case Enum.find(state.snapshots, fn s -> s.id == id end) do
        nil -> %{error: "snapshot_not_found", id: id}
        snapshot -> snapshot
      end

    new_context = add_result(state.context, result)
    new_state = %{state | context: new_context, iteration: state.iteration + 1}
    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%GetSnapshots{limit: limit, offset: offset}, state, trace_id) do
    offset = offset || 0
    snapshots = Enum.drop(state.snapshots, offset)

    snapshots =
      if limit do
        Enum.take(snapshots, limit)
      else
        snapshots
      end

    emit_telemetry(:get_snapshots, state, %{trace_id: trace_id, count: length(snapshots)})

    new_context = add_result(state.context, snapshots)
    new_state = %{state | context: new_context, iteration: state.iteration + 1}
    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%Execute{code: lua_code}, state, trace_id) do
    emit_telemetry(:execute_start, state, %{trace_id: trace_id})

    result =
      case Eval.eval(:lua, lua_code, callbacks: state.domain_module.callbacks()) do
        {:ok, result} ->
          emit_telemetry(:execute_complete, state, %{trace_id: trace_id})
          result

        {:error, reason} ->
          emit_telemetry(:execute_error, state, %{trace_id: trace_id, reason: reason})
          %{error: inspect(reason)}
      end

    new_context = add_result(state.context, result)
    new_state = %{state | context: new_context, iteration: state.iteration + 1}
    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%Wait{ms: ms}, state, trace_id) do
    emit_telemetry(:wait, state, %{trace_id: trace_id, ms: ms})
    Process.send_after(self(), :continue_loop, ms)

    fresh_context = Context.new(metadata: %{iteration: state.iteration + 1})
    new_state = %{state | context: fresh_context, iteration: state.iteration + 1}
    {:noreply, new_state}
  end

  defp collect_snapshot(state) do
    state.domain_module.snapshot()
  end

  defp build_input(watcher_state) do
    "Current state: #{watcher_state}"
  end

  defp build_alert(state, type, summary, severity, snapshots) do
    Alert.new(%{
      watcher: state.domain_module.domain(),
      anomaly_type: type,
      severity: severity,
      summary: summary,
      snapshots: snapshots
    })
  end

  defp resolve_snapshots([], _stored_snapshots) do
    {:error, "snapshot_ids required: alerts must reference at least one snapshot"}
  end

  defp resolve_snapshots(ids, stored_snapshots) do
    snapshot_map = Map.new(stored_snapshots, fn s -> {s.id, s} end)
    {found, missing} = Enum.split_with(ids, &Map.has_key?(snapshot_map, &1))

    if missing == [] do
      {:ok, Enum.map(found, &Map.fetch!(snapshot_map, &1))}
    else
      {:error, "snapshots not found: #{Enum.join(missing, ", ")}"}
    end
  end

  defp add_result(context, result) do
    case Jason.encode(result) do
      {:ok, encoded} ->
        message = Puck.Message.new(:user, encoded, %{tool_result: true})
        %{context | messages: context.messages ++ [message]}

      {:error, reason} ->
        error_msg = "Failed to encode tool result: #{inspect(reason)}"
        message = Puck.Message.new(:user, error_msg, %{tool_result: true})
        %{context | messages: context.messages ++ [message]}
    end
  end

  defp build_puck_client(client_registry) do
    backend_config =
      %{
        function: "WatcherLoop",
        args_format: :messages,
        path: Application.app_dir(:beamlens, "priv/baml_src")
      }
      |> maybe_add_client_registry(client_registry)

    Puck.Client.new(
      {Puck.Backends.Baml, backend_config},
      hooks: Beamlens.Telemetry.Hooks
    )
  end

  defp maybe_add_client_registry(config, nil), do: config

  defp maybe_add_client_registry(config, client_registry) when is_map(client_registry) do
    Map.put(config, :client_registry, client_registry)
  end

  defp emit_telemetry(event, state, extra \\ %{}) do
    :telemetry.execute(
      [:beamlens, :watcher, event],
      %{system_time: System.system_time()},
      Map.merge(
        %{watcher: state.domain_module.domain()},
        extra
      )
    )
  end
end
