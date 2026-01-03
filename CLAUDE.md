A runtime AI agent that monitors BEAM application health and generates actionable analyses.

## Rules

- Zero production impact: all calls must be read-only with no side effects
- No sensitive data: never analyze or expose PII/PHI
- No backwards compatibility: write clean, current code
- Never use @spec
- Never use Process.sleep in tests. Instead rely on deterministic logic
- Never use non-critical comments
