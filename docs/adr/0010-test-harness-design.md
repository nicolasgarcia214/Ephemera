# 10. Test harness design

Status: accepted. Recorded 2026-11-24 from comments in `tests/`.

## Decisions

### Node unit tests (`run_tests.js`)

- `.pragma library` modules target the QML JavaScript engine, so
  `loadPragmaLib` evaluates their source in Node with the directive removed.
  Issue #16 tracks the regex rewriting it does on the way.

### Headless QML tests (`run_qml_tests.sh`)

- Pixman Weston exposes no EGL context. The runner forces Qt Quick's
  software scene graph so animations and input-mask geometry still advance
  in CI.
- Headless Weston has no layer-shell protocol. `EphemeraPanelHarness`
  verifies QML geometry there; surface sizing and mask placement need a
  compositor that can create the production layer surface, which is what
  `run_panel_qml_test.sh` is for.
- The fixture `curl` consumes its config from stdin so the QML process can
  close the pipe.

### What individual harnesses are built to expose

- `ShippingCompileHarness` sets the properties DMS injects before creating
  the daemon. It instantiates an explicit `EphemeraPanel`, independent of the
  screen-backed `Variants` delegate, and explicit instances of every
  component hidden behind an empty model, a lazy loader, a provider
  conditional, or a popup.
- `ProviderIsolationHarness` emits an OpenAI-compatible event from a launch
  that started under Ollama. If that line leaked past a provider switch, the
  replacement parser would accept it, which makes the isolation failure
  observable.
- `StreamingUsageHarness` splits U+20AC across two pipe writes and leaves
  the status line unterminated, so line splitting must flush the tail at
  exit. It backdates `streamStartTime` so the rate renders without a slow
  transport fixture.
- `CoordinatorHarness` saves a provider through PluginService to prove the
  synchronous signal does not re-enter `loadSettings` while persisted
  history is cleared. Its replacement launch uses the same coordinator path
  as a retry.
- `OllamaLifecycleHarness` checks that an idle timeout during a stream
  re-arms. Expiring silently would leave the owned server running forever.
  An MCP approval pause is covered only because it keeps `isStreaming`
  true.
