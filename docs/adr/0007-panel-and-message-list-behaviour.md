# 7. Panel and message list behaviour

Status: accepted. Recorded 2026-11-24 from comments in `EphemeraDaemon.qml`,
`EphemeraPanel.qml`, `ClearChatDialog.qml`, `MessageList.qml`, and
`EphemeraChat.qml`.

## Decisions

- One `EphemeraService` serves every screen. Conversation state is shared, so
  panels open on several screens show the same chat.
- `_togglePanels` closes every open panel. When none was open, it opens the
  focused screen's panel, falling back to the first panel when no screen
  name matches.
- `ClearChatDialog` focuses Cancel when it opens. Ctrl+L followed by Enter
  must not wipe the chat.
- The clear-chat dim overlay covers the widget only, not the whole window.
- Layer-shell applies each anchor property independently. `EphemeraPanel`
  releases the old edge before selecting the new one, so a side switch can
  never stretch the surface between both horizontal edges for a frame.

### Following the bottom of the list (`MessageList`)

- Only an upward move away from the end leaves the bottom. Following growth
  moves `contentY` downward, and the `ListView`'s sub-pixel alignment of its
  end position stays within `_atEnd()`'s tolerance, so neither is mistaken
  for the user scrolling away.
- New messages, streamed deltas, and a shrinking viewport all move the end.
  `onContentHeightChanged` coalesces them into one reposition per event-loop
  pass through `Qt.callLater`.
