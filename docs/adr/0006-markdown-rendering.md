# 6. Markdown rendering

Status: accepted. Recorded 2026-11-24 from comments in `Markdown.js` and
`MessageBubble.qml`.

## Context

`Markdown.js` derives from the DMS AI Assistant's `markdown2html.js`. It
renders model output, which is untrusted, into Qt rich text.

## Decisions

### Ordering constraints in `markdownToHtml`

- All text is HTML-escaped before inline formatting is applied. Code
  contents, code language labels, and table cells are escaped independently.
- Tables are extracted before entity escaping. Splitting a row keeps empty
  cells so columns stay aligned, drops the empty strings produced by the
  outer pipes, and pads or trims each row to the header's column count.
- Links are extracted immediately after escaping. Each part is then escaped
  exactly once, and emphasis markers inside a URL are never interpreted.
  Only the href, or the whole auto-link, is protected; link text keeps its
  formatting.
- Link hrefs are limited to http and https. Any other scheme renders as
  plain text. Auto-linking covers http and https only, and trailing emphasis
  markers and sentence punctuation stay outside the URL.
- Underscore emphasis is anchored to word boundaries, so `snake_case` stays
  literal.
- Blockquotes match `&gt;`, because `>` is already escaped by that step.
- Placeholders are restored in the order protected blocks, code blocks,
  inline code, links. Code and links come after protected blocks so a
  placeholder captured inside a list, blockquote, or table is still reached.

### Rendering in `MessageBubble`

- `markdownToHtml` runs only in a terminal state. Rendering stays deferred
  during streaming, even when the theme changes, and reruns if the text
  changes while the message is already terminal.
- `renderCacheKey` stringifies each colour explicitly, because QML passes
  `QColor` as a value type and not as a JavaScript string.
- Qt drops the `text` binding when `textFormat` switches between `RichText`
  and `PlainText`. A `Connections` handler re-establishes it with
  `Qt.binding()` after each switch.
- `onLinkActivated` opens http and https links only.
