# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Google AI (Gemini) provider support for integration tests via `BEAMLENS_TEST_PROVIDER=google-ai`

### Fixed

- Unit tests no longer make LLM provider calls
- Eval tests now respect `BEAMLENS_TEST_PROVIDER` configuration
- `OperatorSupervisor.start_operator/2` test uses module-based skill identification

## [0.2.0] - 2026-01-14

See the updated [README.md](README.md)!

## [0.1.0] - 2025-01-03

First release!

[Unreleased]: https://github.com/beamlens/beamlens/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/beamlens/beamlens/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/beamlens/beamlens/releases/tag/v0.1.0
