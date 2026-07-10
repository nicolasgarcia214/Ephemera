#!/usr/bin/env node

if (process.argv[3] === "--guard-test") {
    runGuardTest().catch(function(error) {
        process.stderr.write(String(error && error.stack || error) + "\n");
        process.exitCode = 1;
    });
} else if (process.argv[3] === "--guard-http-test") {
    runHttpGuardTest().catch(function(error) {
        process.stderr.write(String(error && error.stack || error) + "\n");
        process.exitCode = 1;
    });
} else if (process.argv[3] === "--guard-coordination-block-test") {
    runCoordinationBlockTest().catch(function(error) {
        process.stderr.write(String(error && error.stack || error) + "\n");
        process.exitCode = 1;
    });
} else if ((process.argv.length !== 3 && process.argv.length !== 4)
        || (process.argv[2] !== "https://mcp.example.test/sse"
            && process.argv[2] !== "https://changed.example.test/sse"
            && process.argv[2] !== "http://mcp-http.example.test/sse")
        || (process.argv.length === 4 && process.argv[3] !== "--allow-http")) {
    process.stderr.write("unexpected bridge invocation\n");
    process.exit(2);
} else {
    runBridge().catch(function(error) {
        process.stderr.write(String(error && error.stack || error) + "\n");
        process.exitCode = 1;
    });
}

async function fetchGuardIsInstalled() {
    var undici = require("undici");
    var staticFetch = (await import("../static-fetch.mjs")).staticFetch;
    var browserUrlWasBlocked = (await import("../browser-spawn.mjs"))
        .browserUrlWasBlocked;
    undici.testRedirectModes.length = 0;
    await undici.testRawFetch("https://fetch.example.test/redirect-guard-test", {
        redirect: "follow"
    });
    var negativeControl = undici.testRedirectModes.length === 1
        && undici.testRedirectModes[0] === "follow";
    var everyImportGuarded = globalThis.fetch === undici.fetch
        && staticFetch === undici.fetch;
    if (!negativeControl || !everyImportGuarded)
        return false;

    undici.testRedirectModes.length = 0;
    await globalThis.fetch("https://fetch.example.test/redirect-guard-test", {
        redirect: "follow"
    });
    await undici.fetch("https://fetch.example.test/redirect-guard-test", {
        redirect: "follow"
    });
    await staticFetch("https://fetch.example.test/redirect-guard-test", {
        redirect: "follow"
    });
    var redirectsGuarded = undici.testRedirectModes.length === 3
        && undici.testRedirectModes[0] === "error"
        && undici.testRedirectModes[1] === "error"
        && undici.testRedirectModes[2] === "error";
    if (!redirectsGuarded)
        return false;

    var blockedDowngrades = 0;
    var guardedFetches = [globalThis.fetch, undici.fetch, staticFetch];
    for (var i = 0; i < guardedFetches.length; i++) {
        try {
            await guardedFetches[i]("http://downgrade.example.test/resource");
        } catch (error) {
            blockedDowngrades++;
        }
    }
    var browserDowngradeBlocked = browserUrlWasBlocked(
        "http://downgrade.example.test/authorize");
    var approvedHttpsBrowserBlocked = browserUrlWasBlocked(
        "https://mcp.example.test/authorize");
    var unsupportedLauncherBlocked = browserUrlWasBlocked(
        "https://mcp.example.test/authorize", "/usr/bin/powershell.exe");
    return blockedDowngrades === guardedFetches.length
        && undici.testRedirectModes.length === 3
        && undici.testBlockedTargetHits() === 0
        && browserDowngradeBlocked
        && !approvedHttpsBrowserBlocked
        && unsupportedLauncherBlocked;
}

async function runGuardTest() {
    if (!await fetchGuardIsInstalled())
        throw new Error("redirect guard did not cover every Fetch path");
    process.stdout.write("MCP_FETCH_GUARD_PASS\n");
}

async function runCoordinationBlockTest() {
    var undici = require("undici");
    await undici.fetch(
        "http://127.0.0.1:45678/wait-for-auth?poll=false");
    process.stdout.write("MCP_COORDINATION_UNGUARDED\n");
}

async function runHttpGuardTest() {
    var http = require("node:http");
    var browserUrlWasBlocked = (await import("../browser-spawn.mjs"))
        .browserUrlWasBlocked;
    var origin = "http://127.0.0.1:41739";
    var foreignOrigin = "http://127.0.0.1:41740";
    var foreignRequestCount = 0;
    var server = http.createServer(function(request, response) {
        if (request.url === "/redirect") {
            response.writeHead(302, { Location: origin + "/ok" });
            response.end();
            return;
        }
        response.writeHead(200, { "Content-Type": "text/plain" });
        response.end("ok");
    });
    var foreignServer = http.createServer(function(request, response) {
        foreignRequestCount++;
        response.writeHead(200, { "Content-Type": "text/plain" });
        response.end("foreign reached");
    });
    try {
        await new Promise(function(resolve, reject) {
            server.once("error", reject);
            server.listen(41739, "127.0.0.1", resolve);
        });
    } catch (error) {
        if (error && (error.code === "EPERM" || error.code === "EACCES")) {
            process.stdout.write("MCP_FETCH_HTTP_GUARD_SKIP\n");
            return;
        }
        throw error;
    }
    try {
        await new Promise(function(resolve, reject) {
            foreignServer.once("error", reject);
            foreignServer.listen(41740, "127.0.0.1", resolve);
        });
    } catch (error) {
        await new Promise(function(resolve) { server.close(resolve); });
        throw error;
    }

    try {
        var allowed = await globalThis.fetch(origin + "/ok");
        if (await allowed.text() !== "ok")
            throw new Error("approved HTTP origin was not reachable");

        var redirectBlocked = false;
        try {
            await globalThis.fetch(origin + "/redirect", { redirect: "follow" });
        } catch (error) {
            redirectBlocked = true;
        }
        var foreignOriginBlocked = false;
        try {
            await globalThis.fetch(foreignOrigin + "/foreign");
        } catch (error) {
            foreignOriginBlocked = true;
        }
        var foreignBrowserBlocked = browserUrlWasBlocked(
            foreignOrigin + "/authorize");
        var approvedBrowserBlocked = browserUrlWasBlocked(origin + "/authorize");
        if (!redirectBlocked || !foreignOriginBlocked || !foreignBrowserBlocked
                || approvedBrowserBlocked || foreignRequestCount !== 0)
            throw new Error("HTTP origin or redirect policy was bypassed");
        process.stdout.write("MCP_FETCH_HTTP_GUARD_PASS\n");
    } finally {
        await Promise.all([
            new Promise(function(resolve) { server.close(resolve); }),
            new Promise(function(resolve) { foreignServer.close(resolve); })
        ]);
    }
}

async function runBridge() {
if (process.env.NODE_OPTIONS || process.env.NODE_PATH
        || process.env.NODE_TLS_REJECT_UNAUTHORIZED || process.env.NODE_DEBUG
        || process.env.__IS_WSL_TEST__ || process.env.OPENAI_API_KEY
        || process.env.ANTHROPIC_API_KEY || process.env.GEMINI_API_KEY
        || process.env.EPHEMERA_API_KEY)
    throw new Error("unsafe inherited Node environment reached the bridge");
if (!await fetchGuardIsInstalled())
    throw new Error("redirect guard did not cover every Fetch path");
var buffer = "";

function write(message) {
    process.stdout.write(JSON.stringify(message) + "\n");
}

function handle(message) {
    if (!message || message.jsonrpc !== "2.0") return;
    if (message.method === "initialize") {
        write({ jsonrpc: "2.0", id: "__proto__", result: {} });
        write({ jsonrpc: "2.0", method: 7, params: {} });
        write({
            jsonrpc: "2.0",
            id: message.id,
            result: {
                protocolVersion: message.params.protocolVersion,
                capabilities: { tools: { listChanged: true } },
                serverInfo: { name: "ephemera-test-bridge", version: "1.0.0" }
            }
        });
    } else if (message.method === "tools/list") {
        write({
            jsonrpc: "2.0",
            id: message.id,
            result: {
                tools: [
                    {
                        name: "echo",
                        description: "Echo one string",
                        inputSchema: {
                            type: "object",
                            properties: { text: { type: "string" } },
                            required: ["text"],
                            additionalProperties: false
                        }
                    },
                    {
                        name: "unsupported_output",
                        description: "Must be ignored before exposure",
                        inputSchema: { type: "object" },
                        outputSchema: {
                            type: "object",
                            properties: {
                                value: { "$ref": "https://attacker.example/output.json" }
                            }
                        }
                    },
                    {
                        name: "unsupported_input",
                        description: "Must be ignored before exposure",
                        inputSchema: {
                            type: "object",
                            properties: {
                                value: { "$ref": "https://attacker.example/input.json" }
                            }
                        }
                    }
                ]
            }
        });
    } else if (message.method === "tools/call") {
        if (message.params.arguments.text === "__large_error__") {
            write({
                jsonrpc: "2.0",
                id: message.id,
                error: { code: -32000, message: "\u202e" + "x".repeat(6000) }
            });
            return;
        }
        if (message.params.arguments.text === "__malformed_error__") {
            write({
                jsonrpc: "2.0",
                id: message.id,
                result: {},
                error: { code: "invalid", message: 7 }
            });
            return;
        }
        if (message.params.arguments.text === "__invalid_result__") {
            write({
                jsonrpc: "2.0",
                id: message.id,
                result: { content: "not-an-array", isError: false }
            });
            return;
        }
        write({
            jsonrpc: "2.0",
            id: message.id,
            result: {
                content: [{ type: "text", text: String(message.params.arguments.text || "") }],
                isError: false
            }
        });
    }
}

process.stdin.setEncoding("utf8");
process.stdin.on("data", function(chunk) {
    buffer += chunk;
    var lines = buffer.split("\n");
    buffer = lines.pop();
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line) continue;
        try { handle(JSON.parse(line)); }
        catch (e) { process.exitCode = 1; }
    }
});

process.on("SIGTERM", function() {
    setTimeout(function() { process.exit(0); }, 150);
});
}
