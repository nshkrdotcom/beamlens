# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Event system for data provenance — verify AI conclusions against raw data
- `HealthAnalysis.events` field with ordered list of all events during analysis
- `get_top_processes` tool for drilling into process-level details with pagination
- Parameterized tools — tools can now accept parameters from the LLM for progressive disclosure

### Changed

- Standardized telemetry events to follow Phoenix/Oban conventions
- All exception events now include `kind`, `reason`, and `stacktrace` metadata
- All stop events now include `duration` measurement and result data
- `Tool.execute` now accepts a params map: `(map() -> map())` instead of `(-> map())`

## [0.1.0] - 2025-01-03

First release!

[Unreleased]: https://github.com/bradleygolden/beamlens/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bradleygolden/beamlens/releases/tag/v0.1.0
