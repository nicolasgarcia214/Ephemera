# 5. Chat persistence, variants, and error state

Status: accepted. Recorded 2026-11-24 from comments in `ChatPersistence.js`,
`VariantStore.js`, `EphemeraService.qml`, `KeyringService.qml`,
`StreamingService.qml`, and `MessageBubble.qml`.

## Decisions

### Snapshot bounds

- Bounds apply only to snapshots stored through PluginService. The live
  message model and the active transport are never altered by them.
- The limits live in `ChatPersistence.js`: 200 completed messages (normally
  100 user and assistant pairs), 10 variants per assistant message, 32 KiB
  for each content and thinking field, 512 bytes for a model field, and 1 MiB
  for the serialized payload.
- Validation work is capped before walking attacker-controlled collections
  (`maxInputMessages` and its siblings). Oversized state below those
  inspection ceilings is normalised and pruned. Input beyond them is treated
  as structurally malicious and discarded.
- Payload size only grows as older turns are added, so the pruner binary
  searches for the largest suffix that fits and does not serialise every
  growing prefix.

### Ordering around PluginService

- PluginService emits change signals synchronously. A provider change is
  persisted only after every request and discovery consumer has received the
  new identity.
- A provider change calls `clearChat()` first, which resets the active
  request and its tool state before the identity changes.
- Legacy `chatHistory` and `chatVariants` keys are migrated by promoting the
  fully validated pair to plugin state first and erasing the legacy keys
  second.
- `_clearLegacyChatData` restarts `_settingsReloadDebounce` before erasing,
  because each erase emits `pluginDataChanged` synchronously and a reload
  between the two halves would see inconsistent data.

### Variants

- The variant store is a plain object: message id to an array of
  `{content, thinking, modelName, errorText?}`.
- `saveVariant` evicts from the front once a message exceeds the cap. The
  caller must correct the displayed index with `adjustAfterEviction`, whose
  count includes a variant that is still streaming.

### Errors travel apart from content

- Only a failed response carries `errorText`. Partial output stays the
  message body.
- A stored variant keeps the error it failed with, and the error banner
  belongs to whichever variant is on screen.
- An exported failed response is its partial text followed by the error.

### Keyring cache

- `_cloneCache` always returns a new object. QML skips change notification
  when a `property var` is reassigned the same reference, which would
  silently break the `hasApiKey` bindings.
