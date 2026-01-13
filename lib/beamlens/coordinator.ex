defmodule Beamlens.Coordinator do
  @moduledoc """
  GenServer that correlates notifications from operators into insights.

  Receives notifications via direct message passing from operators and manages a
  notification inbox with status tracking. Runs an LLM tool-calling loop to identify
  patterns across notifications and emit insights.

  ## Notification States

  - `:unread` - New notification, not yet processed
  - `:acknowledged` - Currently being analyzed
  - `:resolved` - Processed (correlated into insight or dismissed)

  ## Single Node Example (Continuous Mode)

      {:ok, pid} = Beamlens.Coordinator.start_link(
        client_registry: %{...}
      )

  ## Clustered Example

  When running in a cluster with PubSub, the Coordinator can receive notifications
  from other nodes:

      {:ok, pid} = Beamlens.Coordinator.start_link(
        client_registry: %{...},
        pubsub: MyApp.PubSub
      )

  In clustered mode, wrap with Highlander to ensure only one runs cluster-wide:

      children = [
        {Highlander, {Beamlens.Coordinator, client_registry: %{...}, pubsub: MyApp.PubSub}}
      ]

  ## On-Demand Mode

  For one-shot analysis, use `run/3` which spawns a temporary coordinator,
  analyzes notifications, and returns results:

      {:ok, result} = Beamlens.Coordinator.run(notifications, client_registry,
        context: %{reason: "health check"})

      # result contains:
      # %{insights: [...], operator_results: [...]}

  """

  use GenServer

  alias Beamlens.Coordinator.{Insight, Tools}

  alias Beamlens.Coordinator.Tools.{
    Done,
    GetNotifications,
    GetOperatorStatuses,
    InvokeOperators,
    MessageOperator,
    ProduceInsight,
    Think,
    UpdateNotificationStatuses,
    Wait
  }

  alias Beamlens.Operator

  alias Beamlens.Coordinator.Status
  alias Beamlens.LLM.Utils
  alias Beamlens.NotificationForwarder
  alias Beamlens.Operator.Notification
  alias Beamlens.Telemetry
  alias Puck.Context

  defstruct [
    :client,
    :client_registry,
    :context,
    :pending_task,
    :pending_trace_id,
    :pubsub,
    :caller,
    mode: :continuous,
    max_iterations: 10,
    notifications: %{},
    iteration: 0,
    running: false,
    insights: [],
    operator_results: [],
    running_operators: %{}
  ]

  @doc """
  Starts the coordinator process.

  ## Options

    * `:name` - Optional process name for registration (default: `__MODULE__`)
    * `:client_registry` - Optional LLM provider configuration map
    * `:pubsub` - Phoenix.PubSub module for cross-node notifications (optional)
    * `:compaction_max_tokens` - Token threshold for compaction (default: 50_000)
    * `:compaction_keep_last` - Messages to keep verbatim after compaction (default: 5)

  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the current coordinator status.
  """
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @doc """
  Runs a one-shot coordinator analysis and returns results.

  Spawns a temporary coordinator in on-demand mode, processes notifications,
  and blocks until analysis is complete.

  ## Arguments

    * `notifications` - List of `Notification` structs to analyze
    * `client_registry` - LLM provider configuration map
    * `opts` - Options passed to coordinator

  ## Options

    * `:context` - Map with context to pass to the LLM (optional)
    * `:max_iterations` - Maximum iterations before stopping (default: 10)
    * `:timeout` - Timeout for await in milliseconds (default: 300_000)

  ## Returns

    * `{:ok, result}` - Analysis completed successfully
    * `{:error, reason}` - Analysis failed

  ## Result Structure

      %{
        insights: [Insight.t()],
        operator_results: [map()]
      }

  """
  def run(notifications, client_registry, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 300_000)

    coordinator_opts =
      opts
      |> Keyword.put(:mode, :on_demand)
      |> Keyword.put(:client_registry, client_registry)
      |> Keyword.put(:initial_notifications, notifications)

    {:ok, pid} = start_link(coordinator_opts)

    try do
      await(pid, timeout)
    after
      if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    end
  end

  @doc """
  Blocks until an on-demand coordinator completes its analysis.

  Only valid for coordinators started in `:on_demand` mode.

  ## Returns

    * `{:ok, result}` - Analysis completed
    * `{:error, :not_on_demand}` - Coordinator is in continuous mode
    * `{:error, :already_awaiting}` - Another process is already awaiting

  """
  def await(server, timeout \\ 300_000) do
    GenServer.call(server, :await, timeout)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    mode = Keyword.get(opts, :mode, :continuous)
    client = build_puck_client(Keyword.get(opts, :client_registry), mode, opts)
    pubsub = Keyword.get(opts, :pubsub)

    if mode == :continuous and pubsub do
      Phoenix.PubSub.subscribe(pubsub, NotificationForwarder.pubsub_topic())
    end

    initial_notifications =
      Keyword.get(opts, :initial_notifications, [])
      |> Enum.reduce(%{}, fn notification, acc ->
        Map.put(acc, notification.id, %{notification: notification, status: :unread})
      end)

    state = %__MODULE__{
      client: client,
      client_registry: Keyword.get(opts, :client_registry),
      pubsub: pubsub,
      mode: mode,
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      notifications: initial_notifications,
      context: Context.new()
    }

    emit_telemetry(:started, state)

    if mode == :on_demand do
      {:ok, %{state | running: true}, {:continue, :loop}}
    else
      {:ok, state}
    end
  end

  @impl true
  def terminate(reason, %{pending_task: %Task{} = task} = state) do
    Task.shutdown(task, :brutal_kill)
    maybe_emit_takeover(reason, state)
  end

  def terminate(reason, state) do
    maybe_emit_takeover(reason, state)
  end

  defp maybe_emit_takeover(:shutdown, state) do
    :telemetry.execute(
      [:beamlens, :coordinator, :takeover],
      %{system_time: System.system_time()},
      %{notification_count: map_size(state.notifications)}
    )
  end

  defp maybe_emit_takeover(_reason, _state), do: :ok

  @impl true
  def handle_continue(
        :loop,
        %{mode: :on_demand, iteration: iteration, max_iterations: max} = state
      )
      when iteration >= max do
    emit_telemetry(:max_iterations_reached, state, %{iteration: iteration})
    finish_on_demand(state, :max_iterations)
  end

  def handle_continue(:loop, state) do
    trace_id = Telemetry.generate_trace_id()

    emit_telemetry(:iteration_start, state, %{
      trace_id: trace_id,
      iteration: state.iteration
    })

    context = %{
      state.context
      | metadata: Map.put(state.context.metadata || %{}, :trace_id, trace_id)
    }

    task =
      Task.async(fn ->
        Puck.call(state.client, "Process notifications", context,
          output_schema: Tools.schema(state.mode)
        )
      end)

    {:noreply, %{state | pending_task: task, pending_trace_id: trace_id}}
  end

  @impl true
  def handle_info({ref, result}, %{pending_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | pending_task: nil}

    case result do
      {:ok, response, new_context} ->
        parsed = ensure_parsed(response.content, state.mode)
        handle_action(parsed, %{state | context: new_context}, state.pending_trace_id)

      {:error, reason} ->
        emit_telemetry(:llm_error, state, %{trace_id: state.pending_trace_id, reason: reason})
        {:noreply, %{state | running: false, pending_trace_id: nil}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{pending_task: %Task{ref: ref}} = state) do
    emit_telemetry(:llm_error, state, %{
      trace_id: state.pending_trace_id,
      reason: {:task_crashed, reason}
    })

    {:noreply, %{state | pending_task: nil, pending_trace_id: nil, running: false}}
  end

  def handle_info({:beamlens_notification, %Notification{} = notification, source_node}, state) do
    emit_telemetry(:pubsub_notification_received, state, %{
      notification_id: notification.id,
      operator: notification.operator,
      source_node: source_node
    })

    new_notifications =
      Map.put(state.notifications, notification.id, %{
        notification: notification,
        status: :unread
      })

    new_state = %{state | notifications: new_notifications}

    if state.running do
      {:noreply, new_state}
    else
      {:noreply, %{new_state | running: true, iteration: 0, context: Context.new()},
       {:continue, :loop}}
    end
  end

  def handle_info({:operator_notification, pid, notification}, state) do
    case Map.get(state.running_operators, pid) do
      nil ->
        {:noreply, state}

      _info ->
        new_notifications =
          Map.put(state.notifications, notification.id, %{
            notification: notification,
            status: :unread
          })

        emit_telemetry(:operator_notification_received, state, %{
          notification_id: notification.id,
          operator_pid: pid
        })

        {:noreply, %{state | notifications: new_notifications}}
    end
  end

  def handle_info({:operator_complete, pid, skill, result}, state) do
    case Map.get(state.running_operators, pid) do
      nil ->
        {:noreply, state}

      %{ref: ref} ->
        Process.demonitor(ref, [:flush])

        emit_telemetry(:operator_complete, state, %{skill: skill, result: result})

        new_notifications = merge_operator_notifications(state.notifications, result)

        new_state = %{
          state
          | running_operators: Map.delete(state.running_operators, pid),
            notifications: new_notifications,
            operator_results: [Map.put(result, :skill, skill) | state.operator_results]
        }

        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state)
      when not is_struct(state.pending_task, Task) or state.pending_task.ref != ref do
    case find_operator_by_ref(state.running_operators, ref) do
      nil ->
        {:noreply, state}

      {^pid, %{skill: skill}} ->
        emit_telemetry(:operator_crashed, state, %{skill: skill, reason: reason})

        new_state = %{state | running_operators: Map.delete(state.running_operators, pid)}

        {:noreply, new_state}
    end
  end

  def handle_info({:EXIT, pid, reason}, state) do
    case Map.get(state.running_operators, pid) do
      nil ->
        {:noreply, state}

      %{skill: skill, ref: ref} ->
        Process.demonitor(ref, [:flush])
        emit_telemetry(:operator_crashed, state, %{skill: skill, reason: reason})
        new_state = %{state | running_operators: Map.delete(state.running_operators, pid)}
        {:noreply, new_state}
    end
  end

  def handle_info(:continue_after_wait, state) do
    {:noreply, state, {:continue, :loop}}
  end

  def handle_info(msg, state) do
    emit_telemetry(:unexpected_message, state, %{message: inspect(msg)})
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %Status{
      running: state.running,
      notification_count: map_size(state.notifications),
      unread_count: count_by_status(state.notifications, :unread),
      iteration: state.iteration
    }

    {:reply, status, state}
  end

  def handle_call(:await, _from, %{mode: :continuous} = state) do
    {:reply, {:error, :not_on_demand}, state}
  end

  def handle_call(:await, _from, %{caller: caller} = state) when caller != nil do
    {:reply, {:error, :already_awaiting}, state}
  end

  def handle_call(:await, from, %{mode: :on_demand} = state) do
    {:noreply, %{state | caller: from}}
  end

  defp handle_action(%GetNotifications{status: status}, state, trace_id) do
    notifications = filter_notifications(state.notifications, status)

    result =
      Enum.map(notifications, fn {id, %{notification: notification, status: s}} ->
        %{
          id: id,
          status: s,
          operator: notification.operator,
          anomaly_type: notification.anomaly_type,
          severity: notification.severity,
          summary: notification.summary,
          detected_at: notification.detected_at
        }
      end)

    emit_telemetry(:get_notifications, state, %{trace_id: trace_id, count: length(result)})

    new_context = Utils.add_result(state.context, result)

    new_state = %{
      state
      | context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(
         %UpdateNotificationStatuses{notification_ids: ids, status: status, reason: reason},
         state,
         trace_id
       ) do
    new_notifications = update_notifications_status(state.notifications, ids, status)

    result = %{updated: ids, status: status}
    result = if reason, do: Map.put(result, :reason, reason), else: result

    emit_telemetry(:update_notification_statuses, state, %{
      trace_id: trace_id,
      notification_ids: ids,
      status: status
    })

    new_context = Utils.add_result(state.context, result)

    new_state = %{
      state
      | notifications: new_notifications,
        context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%ProduceInsight{} = tool, state, trace_id) do
    insight =
      Insight.new(%{
        notification_ids: tool.notification_ids,
        correlation_type: tool.correlation_type,
        summary: tool.summary,
        root_cause_hypothesis: tool.root_cause_hypothesis,
        confidence: tool.confidence
      })

    emit_telemetry(:insight_produced, state, %{
      trace_id: trace_id,
      insight: insight
    })

    new_notifications =
      update_notifications_status(state.notifications, tool.notification_ids, :resolved)

    new_context = Utils.add_result(state.context, %{insight_produced: insight.id})

    new_state = %{
      state
      | notifications: new_notifications,
        context: new_context,
        insights: [insight | state.insights],
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%Done{}, %{mode: :on_demand} = state, trace_id) do
    emit_telemetry(:done, state, %{trace_id: trace_id, mode: :on_demand})
    finish_on_demand(state, :done)
  end

  defp handle_action(%Done{}, state, trace_id) do
    has_unread = Enum.any?(state.notifications, fn {_, %{status: s}} -> s == :unread end)

    emit_telemetry(:done, state, %{trace_id: trace_id, has_unread: has_unread})

    if has_unread do
      fresh_context = Context.new()

      {:noreply, %{state | context: fresh_context, iteration: 0, pending_trace_id: nil},
       {:continue, :loop}}
    else
      {:noreply, %{state | running: false, pending_trace_id: nil}}
    end
  end

  defp handle_action(%Think{thought: thought}, state, trace_id) do
    emit_telemetry(:think, state, %{trace_id: trace_id})

    result = %{thought: thought, recorded: true}
    new_context = Utils.add_result(state.context, result)

    new_state = %{
      state
      | context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%InvokeOperators{skills: skills, context: context}, state, trace_id) do
    emit_telemetry(:invoke_operators, state, %{trace_id: trace_id, skills: skills})

    new_running =
      Enum.reduce(skills, state.running_operators, fn skill, acc ->
        start_operator(skill, context, state.client_registry, acc)
      end)

    started_count = map_size(new_running) - map_size(state.running_operators)
    result = %{started: skills, count: started_count}
    new_context = Utils.add_result(state.context, result)

    new_state = %{
      state
      | running_operators: new_running,
        context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%MessageOperator{skill: skill, message: message}, state, trace_id) do
    emit_telemetry(:message_operator, state, %{trace_id: trace_id, skill: skill})

    skill_atom = String.to_existing_atom(skill)

    result =
      case find_operator_by_skill(state.running_operators, skill_atom) do
        nil ->
          %{skill: skill, error: "operator not running"}

        {pid, _info} ->
          case Operator.message(pid, message) do
            {:ok, response} -> response
            {:error, reason} -> %{skill: skill, error: inspect(reason)}
          end
      end

    new_context = Utils.add_result(state.context, result)

    new_state = %{
      state
      | context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%GetOperatorStatuses{}, state, trace_id) do
    emit_telemetry(:get_operator_statuses, state, %{trace_id: trace_id})

    statuses =
      Enum.map(state.running_operators, fn {pid, %{skill: skill, started_at: started_at}} ->
        if Process.alive?(pid) do
          status = Operator.status(pid)

          %{
            skill: skill,
            alive: true,
            state: status.state,
            iteration: status.iteration,
            running: status.running,
            started_at: started_at
          }
        else
          %{skill: skill, alive: false}
        end
      end)

    new_context = Utils.add_result(state.context, statuses)

    new_state = %{
      state
      | context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state, {:continue, :loop}}
  end

  defp handle_action(%Wait{ms: ms}, state, trace_id) do
    emit_telemetry(:wait, state, %{trace_id: trace_id, ms: ms})

    Process.send_after(self(), :continue_after_wait, ms)

    new_context = Utils.add_result(state.context, %{waited: ms})

    new_state = %{
      state
      | context: new_context,
        iteration: state.iteration + 1,
        pending_trace_id: nil
    }

    {:noreply, new_state}
  end

  defp finish_on_demand(%{caller: nil} = state, _reason) do
    {:stop, :normal, state}
  end

  defp finish_on_demand(state, _reason) do
    result = %{
      insights: Enum.reverse(state.insights),
      operator_results: Enum.reverse(state.operator_results)
    }

    GenServer.reply(state.caller, {:ok, result})
    {:stop, :normal, %{state | caller: nil}}
  end

  defp merge_operator_notifications(notifications, operator_result) do
    Enum.reduce(operator_result.notifications, notifications, fn notification, acc ->
      Map.put(acc, notification.id, %{notification: notification, status: :unread})
    end)
  end

  defp start_operator(skill, context, client_registry, running_operators) do
    skill_atom =
      try do
        String.to_existing_atom(skill)
      rescue
        ArgumentError -> nil
      end

    case skill_atom && Operator.Supervisor.resolve_skill(skill_atom) do
      nil ->
        running_operators

      {:ok, {_name, skill_module}} ->
        run_opts =
          [
            skill: skill_module,
            client_registry: client_registry,
            mode: :on_demand,
            notify_pid: self()
          ] ++ if(context, do: [context: %{reason: context}], else: [])

        case Operator.start_link(run_opts) do
          {:ok, pid} ->
            Process.link(pid)
            ref = Process.monitor(pid)

            Map.put(running_operators, pid, %{
              skill: skill_atom,
              ref: ref,
              started_at: DateTime.utc_now()
            })

          {:error, _reason} ->
            running_operators
        end

      {:error, _reason} ->
        running_operators
    end
  end

  defp find_operator_by_skill(running_operators, skill) do
    Enum.find(running_operators, fn {_pid, %{skill: s}} -> s == skill end)
  end

  defp find_operator_by_ref(running_operators, ref) do
    Enum.find(running_operators, fn {_pid, %{ref: r}} -> r == ref end)
  end

  defp filter_notifications(notifications, nil), do: notifications

  defp filter_notifications(notifications, status) do
    notifications
    |> Enum.filter(fn {_, %{status: s}} -> s == status end)
    |> Map.new()
  end

  defp update_notifications_status(notifications, ids, new_status) do
    Enum.reduce(ids, notifications, fn id, acc ->
      case Map.get(acc, id) do
        nil -> acc
        entry -> Map.put(acc, id, %{entry | status: new_status})
      end
    end)
  end

  defp count_by_status(notifications, status) do
    Enum.count(notifications, fn {_, %{status: s}} -> s == status end)
  end

  defp ensure_parsed(%{__struct__: _} = struct, _mode), do: struct

  defp ensure_parsed(map, mode) when is_map(map) do
    {:ok, parsed} = Zoi.parse(Tools.schema(mode), map)
    parsed
  end

  defp build_puck_client(client_registry, mode, opts) do
    operator_descriptions = build_operator_descriptions()
    function_name = baml_function(mode)

    backend_config =
      %{
        function: function_name,
        args_format: :auto,
        args: build_args_fn(mode, operator_descriptions),
        path: Application.app_dir(:beamlens, "priv/baml_src")
      }
      |> Utils.maybe_add_client_registry(client_registry)

    Puck.Client.new(
      {Puck.Backends.Baml, backend_config},
      hooks: Beamlens.Telemetry.Hooks,
      auto_compaction: build_compaction_config(opts)
    )
  end

  defp baml_function(:continuous), do: "CoordinatorLoop"
  defp baml_function(:on_demand), do: "CoordinatorRun"

  defp build_args_fn(:continuous, operator_descriptions) do
    fn messages ->
      %{
        messages: Utils.format_messages_for_baml(messages),
        operator_descriptions: operator_descriptions
      }
    end
  end

  defp build_args_fn(:on_demand, operator_descriptions) do
    available_skills = build_available_skills()

    fn messages ->
      %{
        messages: Utils.format_messages_for_baml(messages),
        operator_descriptions: operator_descriptions,
        available_skills: available_skills
      }
    end
  end

  defp build_available_skills do
    Operator.Supervisor.configured_operators()
    |> Enum.map_join(", ", &to_string/1)
  end

  defp build_operator_descriptions do
    operators = Application.get_env(:beamlens, :operators, [])

    operators
    |> Enum.map(&Beamlens.Operator.Supervisor.resolve_skill/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map_join("\n", fn {:ok, {name, skill}} -> "- #{name}: #{skill.description()}" end)
  end

  defp build_compaction_config(opts) do
    max_tokens = Keyword.get(opts, :compaction_max_tokens, 50_000)
    keep_last = Keyword.get(opts, :compaction_keep_last, 5)

    {:summarize,
     max_tokens: max_tokens, keep_last: keep_last, prompt: coordinator_compaction_prompt()}
  end

  defp coordinator_compaction_prompt do
    """
    Summarize this notification analysis session, preserving:
    - Notification IDs and their statuses (exact IDs required)
    - Correlations identified between notifications
    - Insights produced and their reasoning
    - Pending analysis or patterns being investigated
    - Any notifications still needing attention

    Be concise. This summary will be used to continue correlation analysis.
    """
  end

  defp emit_telemetry(event, state, extra \\ %{}) do
    :telemetry.execute(
      [:beamlens, :coordinator, event],
      %{system_time: System.system_time()},
      Map.merge(
        %{
          running: state.running,
          notification_count: map_size(state.notifications)
        },
        extra
      )
    )
  end
end
