# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Judge agent that reviews health analyses for quality — verifies conclusions match collected data
- Evaluator-optimizer pattern with automatic retry when judge identifies issues
- `:judge` option to enable/disable quality verification (enabled by default)
- `:max_judge_retries` option to control retry attempts (default: 2)
- `JudgeCall` event type in `HealthAnalysis.events` for audit trail
- Telemetry events for judge lifecycle: `[:beamlens, :judge, :start | :stop | :exception]`
- Event system for data provenance — verify AI conclusions against raw data
- `HealthAnalysis.events` field with ordered list of all events during analysis
- `get_overview` tool that provides quick health snapshot with pre-calculated utilization percentages
- `reasoning` field in `HealthAnalysis` that explains how the agent reached its assessment
- `get_top_processes` tool for drilling into process-level details with pagination
- Parameterized tools — tools can now accept parameters from the LLM for progressive disclosure

### Changed

- Standardized telemetry events to follow Phoenix/Oban conventions
- All exception events now include `kind`, `reason`, and `stacktrace` metadata
- All stop events now include `duration` measurement and result data
- Tool execute functions now receive a params map, enabling tools to accept LLM-provided parameters
- Agent now collects a complete snapshot of all metrics upfront, reducing LLM roundtrips for typical analyses

## [0.1.0] - 2025-01-03

First release!

[Unreleased]: https://github.com/bradleygolden/beamlens/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bradleygolden/beamlens/releases/tag/v0.1.0
