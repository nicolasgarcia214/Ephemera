"use strict";

// This preload is part of the MCP transport security boundary. It is loaded by
// the already version-checked Node executable before mcp-remote's entry point.

var fs = require("node:fs");
var childProcess = require("node:child_process");
var createRequire = require("node:module").createRequire;
var os = require("node:os");
var path = require("node:path");

var REVIEWED_BRIDGE_VERSION = "0.1.38";
var MINIMUM_UNDICI_VERSION = [7, 28, 0];
var REVIEWED_OPEN_VERSIONS = ["10.1.0", "10.2.0"];

function fail(message) {
    process.stderr.write("Ephemera MCP fetch guard: " + message + "\n");
    process.exit(78);
}

function readJson(filename) {
    return JSON.parse(fs.readFileSync(filename, "utf8"));
}

function isReviewedUndiciVersion(version) {
    var match = /^(\d+)\.(\d+)\.(\d+)$/.exec(String(version || ""));
    if (!match || Number(match[1]) !== MINIMUM_UNDICI_VERSION[0])
        return false;
    for (var i = 1; i < MINIMUM_UNDICI_VERSION.length; i++) {
        var current = Number(match[i + 1]);
        if (current > MINIMUM_UNDICI_VERSION[i]) return true;
        if (current < MINIMUM_UNDICI_VERSION[i]) return false;
    }
    return true;
}

function isInside(child, parent) {
    var relative = path.relative(parent, child);
    return relative !== "" && relative !== ".."
        && relative.slice(0, 3) !== ".." + path.sep
        && !path.isAbsolute(relative);
}

try {
    var proxyArgument = process.argv[1];
    if (!proxyArgument)
        fail("the bridge entry point is missing");

    var targetUrl = new URL(String(process.argv[2] || ""));
    if ((targetUrl.protocol !== "https:" && targetUrl.protocol !== "http:")
            || targetUrl.username || targetUrl.password
            || targetUrl.search || targetUrl.hash)
        fail("the MCP target URL is outside the approved transport policy");
    var allowHttp = process.argv.slice(3).indexOf("--allow-http") >= 0;
    if ((targetUrl.protocol === "http:") !== allowHttp)
        fail("the MCP target URL does not match its explicit HTTP consent");

    var approvedTransportUrl = function(value) {
        var candidate;
        try {
            candidate = new URL(String(value || ""));
        } catch (error) {
            return false;
        }
        if (candidate.username || candidate.password)
            return false;
        if (candidate.protocol === "https:")
            return true;
        return targetUrl.protocol === "http:"
            && candidate.protocol === "http:"
            && candidate.origin === targetUrl.origin;
    };

    var isOAuthCoordinationUrl = function(value) {
        var candidate;
        try {
            candidate = new URL(String(value || ""));
        } catch (error) {
            return false;
        }
        return candidate.protocol === "http:"
            && candidate.hostname === "127.0.0.1"
            && /^[1-9]\d{0,4}$/.test(candidate.port)
            && Number(candidate.port) <= 65535
            && !candidate.username && !candidate.password && !candidate.hash
            && candidate.pathname === "/wait-for-auth"
            && (candidate.search === "" || candidate.search === "?poll=false");
    };

    var proxyPath = fs.realpathSync(proxyArgument);
    if (path.basename(proxyPath) !== "proxy.js"
            || path.basename(path.dirname(proxyPath)) !== "dist")
        fail("the bridge entry point has an unsupported layout");

    var bridgeRoot = fs.realpathSync(path.dirname(path.dirname(proxyPath)));
    var bridgePackage = readJson(path.join(bridgeRoot, "package.json"));
    if (!bridgePackage || bridgePackage.name !== "mcp-remote"
            || bridgePackage.version !== REVIEWED_BRIDGE_VERSION
            || !bridgePackage.bin
            || bridgePackage.bin["mcp-remote"] !== "dist/proxy.js"
            || !bridgePackage.dependencies
            || typeof bridgePackage.dependencies.undici !== "string"
            || bridgePackage.dependencies.open !== "^10.1.0")
        fail("the loaded bridge is not the reviewed mcp-remote release");

    var bridgeRequire = createRequire(proxyPath);
    var undiciPackagePath = fs.realpathSync(
        bridgeRequire.resolve("undici/package.json"));
    var resolvedUndiciRoot = path.dirname(undiciPackagePath);
    var installModulesRoot = fs.realpathSync(path.dirname(bridgeRoot));
    var standardGlobalLayout = path.basename(bridgeRoot) === "mcp-remote"
        && path.basename(installModulesRoot) === "node_modules";
    var hoistedUndiciRoot = standardGlobalLayout
        ? path.join(installModulesRoot, "undici") : "";
    var nestedUndiciRoot = path.join(bridgeRoot, "node_modules", "undici");
    if ((!hoistedUndiciRoot || resolvedUndiciRoot !== hoistedUndiciRoot)
            && resolvedUndiciRoot !== nestedUndiciRoot)
        fail("Undici resolved outside the bridge's direct dependency layouts");

    var undiciPackage = readJson(undiciPackagePath);
    if (!undiciPackage || undiciPackage.name !== "undici"
            || !isReviewedUndiciVersion(undiciPackage.version))
        fail("the loaded Undici release is not >=7.28.0 and <8");

    var undiciEntry = fs.realpathSync(bridgeRequire.resolve("undici"));
    if (!isInside(undiciEntry, resolvedUndiciRoot))
        fail("the resolved Undici module escaped its checked package");

    var undici = require(undiciEntry);
    if (!undici || typeof undici.fetch !== "function"
            || typeof undici.install !== "function")
        fail("the checked Undici module does not expose the required API");

    // The reviewed open 10.1.0/10.2.0 Linux implementations delegate the initial
    // OAuth URL to child_process.spawn with the URL as its final argument.
    // Gate those exact releases and layouts before relying on this hook.
    var openEntry = fs.realpathSync(bridgeRequire.resolve("open"));
    var resolvedOpenRoot = path.dirname(openEntry);
    var hoistedOpenRoot = standardGlobalLayout
        ? path.join(installModulesRoot, "open") : "";
    var nestedOpenRoot = path.join(bridgeRoot, "node_modules", "open");
    if ((!hoistedOpenRoot || resolvedOpenRoot !== hoistedOpenRoot)
            && resolvedOpenRoot !== nestedOpenRoot)
        fail("open resolved outside the bridge's direct dependency layouts");
    var openPackage = readJson(path.join(resolvedOpenRoot, "package.json"));
    if (!openPackage || openPackage.name !== "open"
            || REVIEWED_OPEN_VERSIONS.indexOf(openPackage.version) < 0
            || openPackage.type !== "module"
            || !openPackage.exports
            || openPackage.exports.default !== "./index.js"
            || path.basename(openEntry) !== "index.js"
            || !isInside(openEntry, resolvedOpenRoot))
        fail("the loaded open release is not within the reviewed 10.1/10.2 range");
    if (process.platform !== "linux" || /microsoft/i.test(os.release()))
        fail("the guarded OAuth browser handoff requires native Linux");

    // Install the reviewed implementation for transports which use Node's
    // global Fetch, then guard both that path and mcp-remote's direct import.
    undici.install();
    var directFetch = undici.fetch.bind(undici);
    var guardedFetch = function(input, init) {
        var inputValue = input && typeof input.url === "string"
            ? input.url : String(input || "");
        var transportApproved = approvedTransportUrl(inputValue);
        if (!transportApproved && isOAuthCoordinationUrl(inputValue)) {
            // mcp-remote 0.1.38 catches an ordinary rejection here, deletes a
            // live peer's OAuth lock, and starts a competing flow. Terminate
            // instead: concurrent OAuth is unsupported, but the lock and the
            // peer performing authorization remain intact.
            fail("concurrent MCP OAuth coordination is unsupported");
        }
        if (!transportApproved) {
            return Promise.reject(new TypeError(
                "Ephemera blocked a Fetch request outside the approved transport"));
        }
        var options = Object.assign({}, init || {});
        options.redirect = "error";
        return directFetch(input, options);
    };

    Object.defineProperty(undici, "fetch", {
        value: guardedFetch,
        configurable: false,
        enumerable: true,
        writable: false
    });
    Object.defineProperty(globalThis, "fetch", {
        value: guardedFetch,
        configurable: false,
        enumerable: true,
        writable: false
    });
    if (undici.fetch !== guardedFetch || globalThis.fetch !== guardedFetch)
        fail("the redirect guard could not be installed");

    // mcp-remote opens OAuth authorization URLs through the ESM `open`
    // package, outside Fetch. On Linux that package delegates to xdg-open;
    // apply the same transport policy before a browser process is spawned.
    var directSpawn = childProcess.spawn.bind(childProcess);
    var guardedSpawn = function(command, args, options) {
        var executable = path.basename(String(command || ""));
        if (executable !== "xdg-open")
            throw new TypeError(
                "Ephemera blocked an unsupported browser launcher");
        var values = Array.isArray(args) ? args : [];
        var browserTarget = values.length > 0
            ? values[values.length - 1] : "";
        if (!approvedTransportUrl(browserTarget))
            throw new TypeError(
                "Ephemera blocked a browser URL outside the approved transport");
        return directSpawn(command, args, options);
    };
    Object.defineProperty(childProcess, "spawn", {
        value: guardedSpawn,
        configurable: false,
        enumerable: true,
        writable: false
    });
    if (childProcess.spawn !== guardedSpawn)
        fail("the browser transport guard could not be installed");
} catch (error) {
    fail(error && error.message ? error.message : String(error));
}
