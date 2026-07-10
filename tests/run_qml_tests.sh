#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_NODE=$(command -v node)
if "$TEST_NODE" -e '
const node = (process.versions.node || "").split(".").map(Number);
const undici = (process.versions.undici || "").split(".").map(Number);
const nodeOk = node.length === 3 && node[0] === 24 && node[1] >= 17;
const undiciOk = undici.length === 3 && undici[0] === 7 && undici[1] >= 28;
process.exit(nodeOk && undiciOk ? 0 : 1);
'; then
    TEST_RUNTIME_OVERRIDE=0
else
    if [ "${CI:-}" = "true" ]; then
        printf 'CI must run the MCP QML suite with real Node >=24.17.0 and <25 with bundled Undici >=7.28.0 and <8\n' >&2
        exit 1
    fi
    TEST_RUNTIME_OVERRIDE=1
fi
RUNTIME_DIR=$(mktemp -d /tmp/ephemera-qml-test.XXXXXX)
trap 'rm -rf "$RUNTIME_DIR"' EXIT
chmod 700 "$RUNTIME_DIR"
CONFIG_DIR="$RUNTIME_DIR/config"
mkdir -p "$CONFIG_DIR/src/services" "$CONFIG_DIR/src/lib" \
    "$CONFIG_DIR/src/runtime" \
    "$CONFIG_DIR/Common" "$CONFIG_DIR/Services"
cp "$ROOT/tests/McpServiceHarness.qml" "$CONFIG_DIR/McpServiceHarness.qml"
cp "$ROOT/tests/McpApprovalHarness.qml" "$CONFIG_DIR/McpApprovalHarness.qml"
cp "$ROOT/tests/ProviderIsolationHarness.qml" "$CONFIG_DIR/ProviderIsolationHarness.qml"
cp "$ROOT/tests/CoordinatorHarness.qml" "$CONFIG_DIR/CoordinatorHarness.qml"
cp "$ROOT/tests/fixtures/qml/Common/"* "$CONFIG_DIR/Common/"
cp "$ROOT/tests/fixtures/qml/Services/"* "$CONFIG_DIR/Services/"
cp "$ROOT/src/services/EphemeraService.qml" "$CONFIG_DIR/src/services/EphemeraService.qml"
cp "$ROOT/src/services/KeyringService.qml" "$CONFIG_DIR/src/services/KeyringService.qml"
cp "$ROOT/src/services/MCPService.qml" "$CONFIG_DIR/src/services/MCPService.qml"
cp "$ROOT/src/services/OllamaManager.qml" "$CONFIG_DIR/src/services/OllamaManager.qml"
cp "$ROOT/src/services/StreamingService.qml" "$CONFIG_DIR/src/services/StreamingService.qml"
cp "$ROOT/src/lib/ChatExport.js" "$CONFIG_DIR/src/lib/ChatExport.js"
cp "$ROOT/src/lib/Mcp.js" "$CONFIG_DIR/src/lib/Mcp.js"
cp "$ROOT/src/lib/McpSchema.js" "$CONFIG_DIR/src/lib/McpSchema.js"
cp "$ROOT/src/lib/Providers.js" "$CONFIG_DIR/src/lib/Providers.js"
cp "$ROOT/src/lib/StreamParser.js" "$CONFIG_DIR/src/lib/StreamParser.js"
cp "$ROOT/src/lib/VariantStore.js" "$CONFIG_DIR/src/lib/VariantStore.js"
cp "$ROOT/src/lib/ErrorHints.js" "$CONFIG_DIR/src/lib/ErrorHints.js"
cp "$ROOT/src/lib/Backoff.js" "$CONFIG_DIR/src/lib/Backoff.js"
cp "$ROOT/src/runtime/McpFetchGuard.cjs" "$CONFIG_DIR/src/runtime/McpFetchGuard.cjs"

GUARD_MODULES="$RUNTIME_DIR/guard/node_modules"
mkdir -p "$GUARD_MODULES/mcp-remote/dist" "$GUARD_MODULES/undici" \
    "$GUARD_MODULES/open"
cp "$ROOT/tests/fixtures/mcp-remote-package/package.json" \
    "$GUARD_MODULES/mcp-remote/package.json"
cp "$ROOT/tests/fixtures/mcp-remote-package/dist/proxy.js" \
    "$GUARD_MODULES/mcp-remote/dist/proxy.js"
cp "$ROOT/tests/fixtures/mcp-remote-package/static-fetch.mjs" \
    "$GUARD_MODULES/mcp-remote/static-fetch.mjs"
cp "$ROOT/tests/fixtures/mcp-remote-package/browser-spawn.mjs" \
    "$GUARD_MODULES/mcp-remote/browser-spawn.mjs"
cp "$ROOT/tests/fixtures/mcp-remote-package/node_modules/undici/package.json" \
    "$GUARD_MODULES/undici/package.json"
cp "$ROOT/tests/fixtures/mcp-remote-package/node_modules/undici/index.js" \
    "$GUARD_MODULES/undici/index.js"
cp "$ROOT/tests/fixtures/mcp-remote-package/node_modules/open/package.json" \
    "$GUARD_MODULES/open/package.json"
cp "$ROOT/tests/fixtures/mcp-remote-package/node_modules/open/index.js" \
    "$GUARD_MODULES/open/index.js"

guard_output=$("$TEST_NODE" -r "$ROOT/src/runtime/McpFetchGuard.cjs" \
    "$GUARD_MODULES/mcp-remote/dist/proxy.js" \
    https://mcp.example.test/sse --guard-test)
printf '%s\n' "$guard_output"
if [ "$guard_output" != "MCP_FETCH_GUARD_PASS" ]; then
    exit 1
fi
if "$TEST_NODE" "$GUARD_MODULES/mcp-remote/dist/proxy.js" \
        https://mcp.example.test/sse --guard-test >/dev/null 2>&1; then
    printf 'unguarded MCP bridge unexpectedly passed redirect checks\n' >&2
    exit 1
fi

http_guard_output=$("$TEST_NODE" -r "$ROOT/src/runtime/McpFetchGuard.cjs" \
    "$GUARD_MODULES/mcp-remote/dist/proxy.js" \
    http://127.0.0.1:41739/sse --guard-http-test --allow-http)
printf '%s\n' "$http_guard_output"
case "$http_guard_output" in
    MCP_FETCH_HTTP_GUARD_PASS) ;;
    MCP_FETCH_HTTP_GUARD_SKIP)
        if [ "${CI:-}" = "true" ]; then
            printf 'HTTP redirect guard test cannot be skipped in CI\n' >&2
            exit 1
        fi
        ;;
    *) exit 1 ;;
esac
expect_guard_rejection() {
    label=$1
    expected_reason=$2
    shift 2
    set +e
    rejection_output=$("$@" 2>&1)
    rejection_status=$?
    set -e
    if [ "$rejection_status" -ne 78 ] \
            || ! printf '%s\n' "$rejection_output" \
                | grep -Fq 'Ephemera MCP fetch guard:' \
            || ! printf '%s\n' "$rejection_output" \
                | grep -Fq "$expected_reason"; then
        printf '%s was not rejected by the preload guard (status %s)\n%s\n' \
            "$label" "$rejection_status" "$rejection_output" >&2
        exit 1
    fi
}

expect_guard_rejection 'HTTP MCP target without explicit consent' \
    'does not match its explicit HTTP consent' \
    "$TEST_NODE" -r "$ROOT/src/runtime/McpFetchGuard.cjs" \
    "$GUARD_MODULES/mcp-remote/dist/proxy.js" \
    http://127.0.0.1:41739/sse --guard-http-test
expect_guard_rejection 'HTTPS MCP target with inconsistent HTTP consent' \
    'does not match its explicit HTTP consent' \
    "$TEST_NODE" -r "$ROOT/src/runtime/McpFetchGuard.cjs" \
    "$GUARD_MODULES/mcp-remote/dist/proxy.js" \
    https://mcp.example.test/sse --allow-http

BAD_OPEN_MODULES="$RUNTIME_DIR/bad-open/node_modules"
mkdir -p "$BAD_OPEN_MODULES"
cp -R "$GUARD_MODULES/mcp-remote" "$BAD_OPEN_MODULES/mcp-remote"
cp -R "$GUARD_MODULES/undici" "$BAD_OPEN_MODULES/undici"
cp -R "$GUARD_MODULES/open" "$BAD_OPEN_MODULES/open"
sed 's/"version": "10.2.0"/"version": "10.2.1"/' \
    "$GUARD_MODULES/open/package.json" > "$BAD_OPEN_MODULES/open/package.json"
expect_guard_rejection 'unreviewed open patch release' \
    'loaded open release is not within the reviewed' \
    "$TEST_NODE" -r "$ROOT/src/runtime/McpFetchGuard.cjs" \
    "$BAD_OPEN_MODULES/mcp-remote/dist/proxy.js" \
    https://mcp.example.test/sse --guard-test

expect_guard_rejection 'concurrent OAuth loopback coordination' \
    'concurrent MCP OAuth coordination is unsupported' \
    "$TEST_NODE" -r "$ROOT/src/runtime/McpFetchGuard.cjs" \
    "$GUARD_MODULES/mcp-remote/dist/proxy.js" \
    https://mcp.example.test/sse --guard-coordination-block-test
coordination_control=$(
    "$TEST_NODE" "$GUARD_MODULES/mcp-remote/dist/proxy.js" \
        https://mcp.example.test/sse --guard-coordination-block-test
)
if [ "$coordination_control" != "MCP_COORDINATION_UNGUARDED" ]; then
    printf 'OAuth coordination negative control did not reach the fixture transport\n' >&2
    exit 1
fi

run_harness() {
    harness=$1
    marker=$2
    harness_runtime="$RUNTIME_DIR/$harness"
    mkdir -p "$harness_runtime"
    chmod 700 "$harness_runtime"

    output=$(PATH="$ROOT/tests/fixtures/bin:$PATH" \
        EPHEMERA_TEST_NODE="$TEST_NODE" \
        EPHEMERA_TEST_RUNTIME_OVERRIDE="$TEST_RUNTIME_OVERRIDE" \
        NODE_OPTIONS="--require=/ephemera-must-clear.cjs" \
        NODE_PATH="/ephemera-must-clear" \
        NODE_TLS_REJECT_UNAUTHORIZED=0 \
        NODE_DEBUG="http,https,tls" \
        __IS_WSL_TEST__=1 \
        OPENAI_API_KEY="must-not-reach-mcp" \
        ANTHROPIC_API_KEY="must-not-reach-mcp" \
        GEMINI_API_KEY="must-not-reach-mcp" \
        EPHEMERA_API_KEY="must-not-reach-mcp" \
        XDG_RUNTIME_DIR="$harness_runtime" \
        QT_QPA_PLATFORM=offscreen \
        QS_NO_RELOAD_POPUP=1 \
        timeout 12s qs -p "$CONFIG_DIR/$harness.qml" 2>&1) || {
        printf '%s\n' "$output"
        exit 1
    }

    printf '%s\n' "$output"
    if ! printf '%s\n' "$output" | grep -Fq "$marker PASS"; then
        exit 1
    fi
    unexpected=$(printf '%s\n' "$output" | grep -E \
        '(^|[[:space:]])(ERROR|FATAL)([[:space:]:]|$)|ReferenceError:|TypeError:|Binding loop|Cannot assign|Cannot read property|unexpected test (curl|ollama|Node|which|secret-tool)' \
        || true)
    if [ -n "$unexpected" ]; then
        printf 'unexpected QML harness diagnostics:\n%s\n' "$unexpected" >&2
        exit 1
    fi
}

run_harness McpServiceHarness EPHEMERA_MCP_QML_TEST
run_harness McpApprovalHarness EPHEMERA_MCP_APPROVAL_TEST
run_harness ProviderIsolationHarness EPHEMERA_PROVIDER_ISOLATION_TEST
run_harness CoordinatorHarness EPHEMERA_COORDINATOR_TEST
