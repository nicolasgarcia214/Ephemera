# 9. Stream parsing, token usage, and backoff

Status: accepted. Recorded 2026-11-24 from comments in `StreamParser.js`,
`StreamingService.qml`, `Backoff.js`, `ErrorHints.js`, and their tests.

## Decisions

### Parsing

- `StreamParser.js` holds pure functions: state in, updates out.
- `parseDelta` reads four wire formats: Anthropic `content_block_delta`,
  Gemini `candidates[].content.parts[]`, Ollama native `message` and its
  OpenAI-compatible mode, and OpenAI-style `choices[].delta` with
  `reasoning_content` or `reasoning`.
- Gemini thought summaries arrive as parts flagged `thought: true` and route
  to thinking.
- `routeThinkTags` buffers a partial `<think>` or `</think>` tag across
  chunk boundaries and consumes one newline after each tag, so the output
  has no blank line where the tag was.
- `extractNonStreamingText` is the fallback when the HTTP response succeeded
  but no streaming delta arrived. It skips Gemini thought summaries.
- curl appends `\nEPH_STATUS:%{http_code}\n` through `-w`.
  `extractHttpStatus` strips that marker from the body and returns the code,
  or 0 when the marker is missing.

### Token usage

- Sources: Anthropic `usage.output_tokens` on `message_delta`; Gemini
  `usageMetadata.candidatesTokenCount` on any chunk; Ollama `eval_count` on
  the native final chunk; OpenAI-compatible `usage.completion_tokens` on the
  final chunk.
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
- `curlExitHint` gives Ollama-specific guidance for exit code 7 (connection
  refused) when the provider is Ollama.
