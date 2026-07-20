# 2. ADR-002: Riverpod for State Management

## Status

Accepted (initial architecture decision).

## Context

Spectra requires state management that handles:
- **Async data**: Database queries, file I/O, thumbnail generation.
- **Caching**: Prevent redundant DB queries and thumbnail recomputation.
- **Disposal**: Clean up resources when leaving screens.
- **Testability**: Mock providers for unit tests.

Options considered: Riverpod, BLoC, Provider, GetIt.

## Decision

Use **Riverpod** (`flutter_riverpod` + `riverpod_generator`) as the state management solution.

Rationale:

1. Compile-time safety — no `BuildContext`-based lookups.
2. Built-in `AsyncValue` for loading/error/data states.
3. `family` modifiers for parameterized providers (e.g., photo by ID).
4. `keepAlive` / `autoDispose` fine-grained lifecycle control.
5. `riverpod_generator` reduces boilerplate with code generation.
6. Excellent testability — providers can be overridden in tests.

## Consequences

- Requires `build_runner` for code generation.
- Provider graph complexity needs careful structuring as the app grows.
- Riverpod 2.x learning curve for new contributors.
