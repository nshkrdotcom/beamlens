# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `:client_registry` option to configure custom LLM providers (OpenAI, Ollama, AWS Bedrock, Google Gemini, etc.)
- Judge agent that double-checks AI conclusions against raw data
- Automatic retry when the judge finds issues with an analysis
- `:judge` option to enable/disable quality checks (enabled by default)
- `:max_judge_retries` option to control retry attempts (default: 2)
- Event tracking to trace how AI reached its conclusions
- `get_overview` tool for quick health snapshot with utilization percentages
- `reasoning` field in `HealthAnalysis` explaining how the agent reached its assessment
- `get_top_processes` tool for drilling into process-level details
- Tools can now accept parameters from the AI for focused data collection
- Watcher system — background monitors that run on schedules and report problems
- AI-based baseline learning — watchers learn what "normal" looks like, no manual thresholds
- Built-in BEAM watcher for VM metrics (memory, processes, schedulers)
- `Beamlens.investigate/1` — analyze pending watcher alerts using AI
- `Beamlens.list_watchers/0` — list all running watchers with status
- `Beamlens.trigger_watcher/1` — manually trigger a specific watcher
- `Beamlens.watcher_status/1` — get details about a specific watcher
- `Beamlens.pending_alerts?/0` — check if alerts are waiting for investigation
- `Watcher` behaviour for implementing custom monitors
- `:alert_handler` config option with `:on_alert` (auto) and `:manual` trigger modes
- Alert cooldown — watchers suppress re-alerts on the same metric category for an LLM-determined duration
- `:snapshot` option for `Beamlens.Agent` to use pre-computed metrics instead of live data
- Circuit breaker to prevent cascading failures when AI providers are unavailable
- `Beamlens.circuit_breaker_state/0` to check circuit breaker health
- `Beamlens.reset_circuit_breaker/0` to manually reset a tripped circuit
- `:circuit_breaker` configuration with `:failure_threshold`, `:reset_timeout`, `:success_threshold`

### Changed

- Upgraded Puck from 0.1.0 to 0.2.2 (adds context compaction support)
- Agent now collects a complete snapshot of all metrics upfront, reducing LLM roundtrips
- Configuration uses `:watchers` instead of `:schedules`
- `list_schedules/0` → `list_watchers/0`
- `get_schedule/1` → `watcher_status/1`
- `run_now/1` → `trigger_watcher/1`

## [0.1.0] - 2025-01-03

First release!

[Unreleased]: https://github.com/beamlens/beamlens/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/beamlens/beamlens/releases/tag/v0.1.0
