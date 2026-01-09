// ============================================================================
// WATCHER AGENT TOOLS
// ============================================================================
// Continuous agent loop with 8 tools:
//
// Message class for conversation history
class Message {
  role string @description("assistant or tool")
  content string @description("JSON content")
}

//
// - SetState: Update watcher state
// - FireAlert: Create an alert with referenced snapshots
// - GetAlerts: See previous alerts
// - TakeSnapshot: Capture current metrics with unique ID
// - GetSnapshot: Retrieve a specific snapshot by ID
// - GetSnapshots: Retrieve multiple snapshots with pagination
// - Execute: Run Lua code for investigation
// - Wait: Sleep before next iteration

class SetState {
  intent "set_state"
  state "healthy" | "observing" | "warning" | "critical" @description("New watcher state")
  reason string @description("Why you're setting this state")
}

class FireAlert {
  intent "fire_alert"
  type string @description("Type of alert (e.g., memory_elevated, scheduler_contention)")
  summary string @description("Brief description of the issue")
  severity "info" | "warning" | "critical" @description("Alert severity")
  snapshot_ids string[] @description("IDs of snapshots to include with alert - required")
}

class GetAlerts {
  intent "get_alerts"
}

class TakeSnapshot {
  intent "take_snapshot"
}

class GetSnapshot {
  intent "get_snapshot"
  id string @description("Snapshot ID to retrieve")
}

class GetSnapshots {
  intent "get_snapshots"
  limit int? @description("Max snapshots to return")
  offset int? @description("Number of snapshots to skip")
}

class Execute {
  intent "execute"
  code string @description("Lua code to execute. Available functions: get_memory(), get_processes(), get_schedulers(), get_atoms(), get_system(), get_persistent_terms(), top_processes(limit, sort_by)")
}

class Wait {
  intent "wait"
  ms int @description("Milliseconds to sleep before next iteration")
}

// Main watcher loop function
function WatcherLoop(messages: Message[]) -> SetState | FireAlert | GetAlerts | TakeSnapshot | GetSnapshot | GetSnapshots | Execute | Wait {
  client Default
  prompt #"
{{ _.role("system") }}
You are a BEAM VM watcher agent running continuously. Your job is to monitor
the system, detect anomalies, and alert when necessary.

## State Model
You have a state that reflects your current assessment:
- healthy: Everything is normal
- observing: Something looks off, you're gathering more data
- warning: Elevated concern, but not critical
- critical: Active issue requiring immediate attention

## Available Tools

### set_state(state, reason)
Update your state. Use this to reflect your current assessment.
If everything is fine, set state to healthy with a brief reason.

### fire_alert(type, summary, severity, snapshot_ids)
Create an alert when you detect an anomaly.
- type: Descriptive name like "memory_elevated", "scheduler_contention"
- summary: Brief human-readable description
- severity: info/warning/critical based on impact
- snapshot_ids: REQUIRED - IDs of snapshots that show the issue (from take_snapshot)

IMPORTANT: You must include snapshot_ids referencing the snapshots that show
the anomaly. Alerts without snapshots will fail.

### get_alerts()
Retrieve previous alerts for correlation. Use this to avoid duplicate
alerts or to understand if an issue is recurring.

### take_snapshot()
Capture current system metrics and store with a unique ID. Returns:
- id: Unique snapshot identifier (use this in fire_alert)
- captured_at: Timestamp
- data: Metrics including memory_utilization_pct, process_utilization_pct, etc.

Call this to capture metrics at specific points during your investigation.

### get_snapshot(id)
Retrieve a specific snapshot by its ID. Use this to review a previously
captured snapshot.

### get_snapshots(limit?, offset?)
Retrieve multiple snapshots with optional pagination.
- limit: Maximum number to return
- offset: Number to skip from the beginning

### execute(code)
Run Lua code to gather detailed metrics. Available functions:
- get_memory() -> memory stats (total_mb, processes_mb, ets_mb, etc.)
- get_processes() -> process/port counts and limits
- get_schedulers() -> scheduler count and run queue
- get_atoms() -> atom table stats
- get_system() -> node info, uptime, versions
- get_persistent_terms() -> persistent term stats
- top_processes(limit, sort_by) -> top N processes by "memory"/"message_queue"/"reductions"

Example:
local mem = get_memory()
local procs = top_processes(10, "memory")
return { memory_mb = mem.total_mb, top_proc = procs.processes[1] }

### wait(ms)
Sleep for the specified milliseconds, then continue.
- Normal operation: wait(30000) -- 30 seconds
- Elevated concern: wait(5000) -- 5 seconds
- Critical monitoring: wait(1000) -- 1 second

## Guidelines

1. Start by calling take_snapshot() to capture current system metrics
2. If metrics look normal, confirm with set_state(healthy, "reason") then wait
3. If something looks off, take more snapshots and use execute() to investigate
4. When firing alerts, include the snapshot IDs that show the problem
5. Set appropriate wait times based on urgency

{% for message in messages %}
{{ _.role(message.role) }}
{{ message.content }}
{% endfor %}

What action do you want to take?

{{ ctx.output_format }}
"#
}

// ============================================================================
// WATCHER TESTS
// ============================================================================

test WatcherLoop_CallsTakeSnapshot {
  functions [WatcherLoop]
  args {
    messages [
      { role "user", content "Current state: healthy" }
    ]
  }
  @@assert(calls_take_snapshot, {{ this.intent == "take_snapshot" }})
}

test WatcherLoop_HealthySnapshot {
  functions [WatcherLoop]
  args {
    messages [
      { role "user", content #"Current state: healthy"# },
      { role "user", content #"{"id":"abc123","captured_at":"2024-01-06T10:30:00Z","data":{"memory_utilization_pct":45.2,"process_utilization_pct":12.1,"port_utilization_pct":3.4,"atom_utilization_pct":8.9,"scheduler_run_queue":0,"schedulers_online":8}}"# }
    ]
  }
  @@assert(stays_healthy_or_waits, {{
    (this.intent == "set_state" and this.state == "healthy") or
    this.intent == "wait"
  }})
}

test WatcherLoop_HighMemory_Investigates {
  functions [WatcherLoop]
  args {
    messages [
      { role "user", content #"Current state: healthy"# },
      { role "user", content #"{"id":"abc123","captured_at":"2024-01-06T10:30:00Z","data":{"memory_utilization_pct":78.5,"process_utilization_pct":12.1,"port_utilization_pct":3.4,"atom_utilization_pct":8.9,"scheduler_run_queue":0,"schedulers_online":8}}"# }
    ]
  }
  @@assert(investigates_or_alerts, {{
    this.intent == "execute" or
    this.intent == "fire_alert" or
    this.intent == "take_snapshot" or
    (this.intent == "set_state" and this.state != "healthy")
  }})
}

test WatcherLoop_CriticalMemory_Alerts {
  functions [WatcherLoop]
  args {
    messages [
      { role "user", content #"Current state: warning"# },
      { role "user", content #"{"id":"snap1","captured_at":"2024-01-06T10:30:00Z","data":{"memory_utilization_pct":85.0,"process_utilization_pct":12.1,"port_utilization_pct":3.4,"atom_utilization_pct":8.9,"scheduler_run_queue":0,"schedulers_online":8}}"# },
      { role "user", content #"{"id":"snap2","captured_at":"2024-01-06T10:30:30Z","data":{"memory_utilization_pct":92.5,"process_utilization_pct":12.1,"port_utilization_pct":3.4,"atom_utilization_pct":8.9,"scheduler_run_queue":0,"schedulers_online":8}}"# }
    ]
  }
  @@assert(alerts_or_escalates, {{
    this.intent == "fire_alert" or
    (this.intent == "set_state" and this.state == "critical") or
    this.intent == "execute"
  }})
}

test WatcherLoop_SchedulerContention {
  functions [WatcherLoop]
  args {
    messages [
      { role "user", content #"Current state: healthy"# },
      { role "user", content #"{"id":"abc123","captured_at":"2024-01-06T10:30:00Z","data":{"memory_utilization_pct":45.2,"process_utilization_pct":12.1,"port_utilization_pct":3.4,"atom_utilization_pct":8.9,"scheduler_run_queue":85,"schedulers_online":8}}"# }
    ]
  }
  @@assert(responds_to_contention, {{
    this.intent == "execute" or
    this.intent == "fire_alert" or
    this.intent == "take_snapshot" or
    (this.intent == "set_state" and this.state != "healthy")
  }})
}
