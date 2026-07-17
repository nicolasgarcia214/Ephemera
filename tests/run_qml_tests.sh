#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HOST_XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}
HOST_WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}
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
WESTON_PID=""
cleanup() {
    if [ -n "$WESTON_PID" ]; then
        kill "$WESTON_PID" 2>/dev/null || true
        wait "$WESTON_PID" 2>/dev/null || true
    fi
    rm -rf "$RUNTIME_DIR"
}
trap cleanup EXIT
chmod 700 "$RUNTIME_DIR"

SHIPPING_WAYLAND_SOCKET=""
TEST_QT_QUICK_BACKEND=${QT_QUICK_BACKEND:-}
if [ -n "$HOST_XDG_RUNTIME_DIR" ] && [ -n "$HOST_WAYLAND_DISPLAY" ] \
        && [ -S "$HOST_XDG_RUNTIME_DIR/$HOST_WAYLAND_DISPLAY" ]; then
    SHIPPING_WAYLAND_SOCKET="$HOST_XDG_RUNTIME_DIR/$HOST_WAYLAND_DISPLAY"
elif command -v weston >/dev/null 2>&1; then
    WESTON_RUNTIME="$RUNTIME_DIR/weston"
    mkdir -p "$WESTON_RUNTIME"
    chmod 700 "$WESTON_RUNTIME"
    XDG_RUNTIME_DIR="$WESTON_RUNTIME" weston --backend=headless-backend.so \
        --renderer=pixman --width=1200 --height=800 --no-config \
        --socket=ephemera-test --idle-time=0 \
        --log="$RUNTIME_DIR/weston.log" >/dev/null 2>&1 &
    WESTON_PID=$!
    attempts=0
    while [ ! -S "$WESTON_RUNTIME/ephemera-test" ] && [ "$attempts" -lt 50 ]; do
        if ! kill -0 "$WESTON_PID" 2>/dev/null; then
            printf 'headless Weston exited before creating its Wayland socket\n' >&2
            cat "$RUNTIME_DIR/weston.log" >&2
            exit 1
        fi
        sleep 0.1
        attempts=$((attempts + 1))
    done
    if [ ! -S "$WESTON_RUNTIME/ephemera-test" ]; then
        printf 'headless Weston did not create its Wayland socket\n' >&2
        exit 1
    fi
    SHIPPING_WAYLAND_SOCKET="$WESTON_RUNTIME/ephemera-test"
    # Pixman Weston exposes no EGL context. Force Qt Quick's software scene
    # graph so animations and input-mask geometry still advance in headless CI.
    TEST_QT_QUICK_BACKEND=software
fi
CONFIG_DIR="$RUNTIME_DIR/config"
mkdir -p "$CONFIG_DIR/src/services" "$CONFIG_DIR/src/lib" \
    "$CONFIG_DIR/src/runtime" \
    "$CONFIG_DIR/src/components" \
    "$CONFIG_DIR/Common" "$CONFIG_DIR/Services" "$CONFIG_DIR/Widgets"
cp "$ROOT/tests/McpServiceHarness.qml" "$CONFIG_DIR/McpServiceHarness.qml"
cp "$ROOT/tests/McpApprovalHarness.qml" "$CONFIG_DIR/McpApprovalHarness.qml"
cp "$ROOT/tests/StreamingErrorHarness.qml" "$CONFIG_DIR/StreamingErrorHarness.qml"
cp "$ROOT/tests/StreamingUsageHarness.qml" "$CONFIG_DIR/StreamingUsageHarness.qml"
cp "$ROOT/tests/ExportLifecycleHarness.qml" "$CONFIG_DIR/ExportLifecycleHarness.qml"
cp "$ROOT/tests/ProviderIsolationHarness.qml" "$CONFIG_DIR/ProviderIsolationHarness.qml"
cp "$ROOT/tests/CoordinatorHarness.qml" "$CONFIG_DIR/CoordinatorHarness.qml"
cp "$ROOT/tests/SubmissionHarness.qml" "$CONFIG_DIR/SubmissionHarness.qml"
cp "$ROOT/tests/PersistenceHarness.qml" "$CONFIG_DIR/PersistenceHarness.qml"
cp "$ROOT/tests/OllamaLifecycleHarness.qml" "$CONFIG_DIR/OllamaLifecycleHarness.qml"
cp "$ROOT/tests/KeyringHarness.qml" "$CONFIG_DIR/KeyringHarness.qml"
cp "$ROOT/tests/OllamaProbeLimitHarness.qml" "$CONFIG_DIR/OllamaProbeLimitHarness.qml"
cp "$ROOT/tests/EphemeraPanelHarness.qml" "$CONFIG_DIR/EphemeraPanelHarness.qml"
cp "$ROOT/tests/ShippingCompileHarness.qml" "$CONFIG_DIR/ShippingCompileHarness.qml"
cp "$ROOT/tests/fixtures/qml/Common/"* "$CONFIG_DIR/Common/"
cp "$ROOT/tests/fixtures/qml/Services/"* "$CONFIG_DIR/Services/"
cp "$ROOT/tests/fixtures/qml/Widgets/"* "$CONFIG_DIR/Widgets/"
cp "$ROOT/EphemeraDaemon.qml" "$CONFIG_DIR/EphemeraDaemon.qml"
cp "$ROOT/src/components/"*.qml "$CONFIG_DIR/src/components/"
cp "$ROOT/src/services/EphemeraService.qml" "$CONFIG_DIR/src/services/EphemeraService.qml"
cp "$ROOT/src/services/KeyringService.qml" "$CONFIG_DIR/src/services/KeyringService.qml"
cp "$ROOT/src/services/MCPService.qml" "$CONFIG_DIR/src/services/MCPService.qml"
cp "$ROOT/src/services/OllamaManager.qml" "$CONFIG_DIR/src/services/OllamaManager.qml"
cp "$ROOT/src/services/StreamingService.qml" "$CONFIG_DIR/src/services/StreamingService.qml"
cp "$ROOT/src/lib/ChatExport.js" "$CONFIG_DIR/src/lib/ChatExport.js"
cp "$ROOT/src/lib/Mcp.js" "$CONFIG_DIR/src/lib/Mcp.js"
cp "$ROOT/src/lib/McpSchema.js" "$CONFIG_DIR/src/lib/McpSchema.js"
cp "$ROOT/src/lib/Markdown.js" "$CONFIG_DIR/src/lib/Markdown.js"
cp "$ROOT/src/lib/Providers.js" "$CONFIG_DIR/src/lib/Providers.js"
cp "$ROOT/src/lib/StreamParser.js" "$CONFIG_DIR/src/lib/StreamParser.js"
cp "$ROOT/src/lib/Submission.js" "$CONFIG_DIR/src/lib/Submission.js"
cp "$ROOT/src/lib/VariantStore.js" "$CONFIG_DIR/src/lib/VariantStore.js"
cp "$ROOT/src/lib/ChatPersistence.js" "$CONFIG_DIR/src/lib/ChatPersistence.js"
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
    keyring_test=${3:-0}
    harness_runtime="$RUNTIME_DIR/$harness"
    mkdir -p "$harness_runtime"
    chmod 700 "$harness_runtime"

    test_openai_key="must-not-reach-mcp"
    test_anthropic_key="must-not-reach-mcp"
    test_gemini_key="must-not-reach-mcp"
    test_ephemera_key="must-not-reach-mcp"
    submission_fixture=0
    if [ "$harness" = "SubmissionHarness" ]; then
        test_openai_key=""
        test_anthropic_key=""
        test_gemini_key=""
        test_ephemera_key=""
        submission_fixture=1
    fi
    qpa_platform=offscreen
    wayland_display=""
    if [ "$harness" = "ShippingCompileHarness" ] \
            || [ "$harness" = "EphemeraPanelHarness" ]; then
        if [ -z "$SHIPPING_WAYLAND_SOCKET" ]; then
            printf 'Wayland QML harness requires an active compositor or headless Weston\n' >&2
            exit 1
        fi
        qpa_platform=wayland
        wayland_display=$SHIPPING_WAYLAND_SOCKET
    fi

    output=$(PATH="$ROOT/tests/fixtures/bin:$PATH" \
        EPHEMERA_TEST_NODE="$TEST_NODE" \
        EPHEMERA_TEST_RUNTIME_OVERRIDE="$TEST_RUNTIME_OVERRIDE" \
        EPHEMERA_KEYRING_TEST="$keyring_test" \
        EPHEMERA_TEST_EXPECT_LAYER_SHELL=0 \
        NODE_OPTIONS="--require=/ephemera-must-clear.cjs" \
        NODE_PATH="/ephemera-must-clear" \
        NODE_TLS_REJECT_UNAUTHORIZED=0 \
        NODE_DEBUG="http,https,tls" \
        __IS_WSL_TEST__=1 \
        OPENAI_API_KEY="$test_openai_key" \
        ANTHROPIC_API_KEY="$test_anthropic_key" \
        GEMINI_API_KEY="$test_gemini_key" \
        EPHEMERA_API_KEY="$test_ephemera_key" \
        EPHEMERA_SUBMISSION_FIXTURE="$submission_fixture" \
        XDG_RUNTIME_DIR="$harness_runtime" \
        WAYLAND_DISPLAY="$wayland_display" \
        QT_QPA_PLATFORM="$qpa_platform" \
        QT_QUICK_BACKEND="$TEST_QT_QUICK_BACKEND" \
        DMS_DISABLE_LAYER=1 \
        QS_NO_RELOAD_POPUP=1 \
        timeout 12s qs -p "$CONFIG_DIR/$harness.qml" 2>&1) || {
        printf '%s\n' "$output"
        exit 1
    }

    printf '%s\n' "$output"
    if ! printf '%s\n' "$output" | grep -Fq "$marker PASS"; then
        exit 1
    fi
    if [ "$harness" = "ShippingCompileHarness" ]; then
        unexpected=$(printf '%s\n' "$output" | grep -E \
            '(^|[[:space:]])(WARN|ERROR|FATAL)([[:space:]:]|$)|unexpected test (curl|ollama|Node|which|secret-tool|wl-copy|pkill|kill)' \
            || true)
    else
        unexpected=$(printf '%s\n' "$output" | grep -E \
            '(^|[[:space:]])(ERROR|FATAL)([[:space:]:]|$)|ReferenceError:|TypeError:|Binding loop|Cannot assign|Cannot read property|Unable to assign|Failed to load configuration|Type .* unavailable|is not a type|Required property .* was not initialized|No PanelWindow backend loaded|unexpected test (curl|ollama|Node|which|secret-tool|wl-copy|pkill|kill)' \
            || true)
    fi
    if [ -n "$unexpected" ]; then
        printf 'unexpected QML harness diagnostics:\n%s\n' "$unexpected" >&2
        exit 1
    fi
}

run_ollama_lifecycle_harness() {
    lifecycle_dir="$RUNTIME_DIR/ollama-lifecycle"
    mkdir -p "$lifecycle_dir"
    chmod 700 "$lifecycle_dir"
    EPHEMERA_OLLAMA_LIFECYCLE_DIR="$lifecycle_dir"
    export EPHEMERA_OLLAMA_LIFECYCLE_DIR
    run_harness OllamaLifecycleHarness EPHEMERA_OLLAMA_LIFECYCLE_TEST
    unset EPHEMERA_OLLAMA_LIFECYCLE_DIR
}

run_ollama_probe_limit_harness() {
    probe_dir="$RUNTIME_DIR/ollama-probe-limit"
    mkdir -p "$probe_dir"
    chmod 700 "$probe_dir"
    EPHEMERA_OLLAMA_PROBE_DIR="$probe_dir"
    export EPHEMERA_OLLAMA_PROBE_DIR
    run_harness OllamaProbeLimitHarness EPHEMERA_OLLAMA_PROBE_LIMIT_TEST
    unset EPHEMERA_OLLAMA_PROBE_DIR
}

run_harness McpServiceHarness EPHEMERA_MCP_QML_TEST
run_harness McpApprovalHarness EPHEMERA_MCP_APPROVAL_TEST
run_harness StreamingErrorHarness EPHEMERA_STREAM_ERROR_TEST
run_harness StreamingUsageHarness EPHEMERA_STREAM_USAGE_TEST
run_harness ExportLifecycleHarness EPHEMERA_EXPORT_LIFECYCLE_TEST
run_harness ProviderIsolationHarness EPHEMERA_PROVIDER_ISOLATION_TEST
run_harness CoordinatorHarness EPHEMERA_COORDINATOR_TEST
run_harness SubmissionHarness EPHEMERA_SUBMISSION_TEST
run_harness PersistenceHarness EPHEMERA_PERSISTENCE_TEST
run_ollama_lifecycle_harness
run_harness KeyringHarness EPHEMERA_KEYRING_TEST 1
run_ollama_probe_limit_harness
run_harness EphemeraPanelHarness EPHEMERA_PANEL_QML_TEST
run_harness ShippingCompileHarness EPHEMERA_SHIPPING_COMPILE_TEST
