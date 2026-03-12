# Central Station

## Development

- Build: `swift build` from `app/`
- Test: `swift test` from `app/`
- Coverage: `./scripts/coverage.sh` from `app/`
- Run: `.build/debug/CentralStation` from `app/`

## Architecture

- `CentralStationCore` — library target with models and testable services (can be `@testable import`ed)
- `CentralStation` — executable target with UI, re-exports `CentralStationCore` via `@_exported import`
- Tests import `CentralStationCore` directly. For logic in the executable target (e.g. TaskCoordinator handlers), tests mirror the logic.

## Rules

- Always write tests to verify all functionality that is added. Tests live in `app/Tests/CentralStationTests/`. Use the Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`). Import testable types with `@testable import CentralStationCore`.
