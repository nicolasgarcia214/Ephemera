# 3. Request construction and endpoint policy

Status: accepted. Recorded 2026-11-24 from comments in `Providers.js`.

## Decisions

### Secrets stay out of argv

- `buildCurlCommand` returns a command array with no secrets. URL, auth
  headers, and body travel in a curl config written to stdin (`-K -`), so
  none of them appear in `/proc/cmdline` or `ps`.
- `escapeCurlConfig` escapes backslashes, double quotes, and whitespace
  control characters for curl's double-quoted config syntax. Without it a
  JSON body containing quotes breaks the config parser.
- The Gemini key is sent as the `x-goog-api-key` header, never as a URL query
  parameter.
- `sanitizeApiKey` strips CR, LF, NUL, and every C0 control, then trims. That
  closes HTTP header injection through a pasted key.

### Endpoint validation

- `validateUrl` accepts http and https only, at most 2048 characters, and
  rejects control characters, default-ignorable formatting code points, and
  characters unsafe in URLs. The last rule prevents injection through the
  path. Hostname and port syntax are checked by `_validateSecureProviderUrl`.
  An empty URL is invalid with an empty error message, so callers can treat
  it as absent.
- `validateCustomProviderUrl` allows HTTPS to any valid hostname. Plaintext
  HTTP is limited to the exact name `localhost` or an unambiguous
  dotted-decimal address in 127.0.0.0/8. Userinfo is never accepted, because
  curl would send it as credentials independently of the configured key.
- `isManagedLocalOllamaUrl` is true only for the default local HTTP
  identities that `ollama serve` uses. Every other valid endpoint is
  probe-only: Ephemera never starts or stops a server behind it.
- `_isUnsafeFormattingCodePoint` covers the Unicode 17
  `Default_Ignorable_Code_Point` ranges plus line separators and interlinear
  annotation controls. `_containsUnsafeUnicodeFormatting` also rejects
  unpaired surrogates, which can change when a JavaScript string is encoded
  for process argv.
- The Gemini model name is validated before it is placed in the URL path,
  because it is user-supplied free text and could traverse paths.

### Provider constraints

- Anthropic requires `max_tokens` and rejects values above each model's cap,
  so the request clamps to `_anthropicOutputCap`. Manual thinking needs a
  budget of at least 1,024 tokens that is strictly below `max_tokens`.
- `clampTemperature` returns `undefined` for OpenAI o-series and older GPT-5
  reasoning models, which reject the parameter.
- `normalizeOllamaContextWindow` treats zero as "model default". Explicit
  values are bounded to avoid extreme memory allocation and round up to a
  supported preset, so the persisted value and the settings UI cannot
  diverge.
