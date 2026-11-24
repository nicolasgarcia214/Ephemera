# 9. Stream parsing, token usage, and backoff

Status: accepted. Recorded 2026-11-24 from comments in `StreamParser.js`,
`StreamingService.qml`, `Backoff.js`, and their tests.

## Decisions

### Parsing

- `routeThinkTags` buffers a partial `<think>` or `</think>` tag across
  chunk boundaries and consumes one newline after each tag, so the output
  has no blank line where the tag was.
- `extractNonStreamingText` is the fallback when the HTTP response succeeded
  but no streaming delta arrived. It skips Gemini thought summaries.
- curl appends `\nEPH_STATUS:%{http_code}\n` through `-w`.
  `extractHttpStatus` strips that marker from the body and returns the code,
  or 0 when the marker is missing.

### Token usage

- Gemini's `usageMetadata.candidatesTokenCount` is read only from chunks
  that carry `candidates[0].content.parts`. A usage-only chunk is skipped.
- OpenAI Chat Completions sends `finish_reason` before a usage-only chunk.
  Some compatible providers send both in one chunk. Both orders are
  accepted.
- The displayed rate prefers the API-reported count. When a provider sends
  none, the delta count stands in as an approximation.

### Backoff

- `computeDelay` uses exponential backoff with full jitter:
  `random(floor, min(maxDelayMs, baseDelayMs * 2^attempt))`, with
  `floor = baseDelayMs * 0.5` so there is always a minimum wait. Defaults
  are 2,000 ms and 30,000 ms. Jitter spreads retries and avoids
  thundering-herd synchronisation.
- `computeCooldownUntil` is called once per error and its absolute timestamp
  is stored. Later checks compare against it, so the delay is never
  re-randomised.
