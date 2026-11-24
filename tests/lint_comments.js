#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");
const BASELINE_PATH = path.join(__dirname, "comment-baseline.json");
const C_LIKE = new Set([".js", ".cjs", ".mjs", ".qml"]);
const DIRECTIVE = /^(?:#!|#\s*shellcheck\s|\/[/*]\s*qmllint\s|\/\/\s*x-release-please-)/;
const REGEX_PRECEDING_WORD = /(?:^|[^\w$.])(?:return|typeof|case|in|of|void|delete|throw|new|else|do|instanceof|yield|await)$/;
const REGEX_PRECEDING_CHAR = new Set("(,=:[!&|?{};+-*%<>~^");

function scanCLike(source) {
    const comments = [];
    const templateDepths = [];
    let braceDepth = 0;
    let significant = "";
    let i = 0;

    const skipQuoted = quote => {
        i++;
        while (i < source.length && source[i] !== quote && source[i] !== "\n") i += source[i] === "\\" ? 2 : 1;
        i++;
    };
    const skipTemplateText = () => {
        while (i < source.length) {
            if (source[i] === "\\") i += 2;
            else if (source[i] === "`") { i++; return; }
            else if (source[i] === "$" && source[i + 1] === "{") {
                i += 2;
                templateDepths.push(braceDepth++);
                return;
            } else i++;
        }
    };
    const skipRegex = () => {
        let inClass = false;
        i++;
        while (i < source.length && source[i] !== "\n") {
            if (source[i] === "\\") i++;
            else if (source[i] === "[") inClass = true;
            else if (source[i] === "]") inClass = false;
            else if (source[i] === "/" && !inClass) break;
            i++;
        }
        i++;
    };
    const regexAllowed = () => significant === ""
        || REGEX_PRECEDING_CHAR.has(significant.at(-1))
        || REGEX_PRECEDING_WORD.test(significant);

    while (i < source.length) {
        const ch = source[i];
        const next = source[i + 1];
        if (ch === "/" && (next === "/" || next === "*")) {
            const start = i;
            if (next === "/") {
                while (i < source.length && source[i] !== "\n") i++;
            } else {
                const end = source.indexOf("*/", i + 2);
                i = end < 0 ? source.length : end + 2;
            }
            comments.push({ start, end: i });
            continue;
        }
        if (/\s/.test(ch)) { i++; continue; }
        const tokenStart = i;
        if (ch === "\"" || ch === "'") skipQuoted(ch);
        else if (ch === "`") { i++; skipTemplateText(); }
        else if (ch === "/" && regexAllowed()) skipRegex();
        else if (ch === "{") { braceDepth++; i++; }
        else if (ch === "}") {
            braceDepth--;
            i++;
            if (templateDepths.at(-1) === braceDepth) {
                templateDepths.pop();
                skipTemplateText();
            }
        } else i++;
        significant = (significant + source.slice(tokenStart, i)).slice(-16);
        if (tokenStart + 1 < i) significant = ")";
    }
    return comments;
}

function scanShell(source) {
    const comments = [];
    const pendingHeredocs = [];
    let i = 0;
    let doubleQuoted = false;

    while (i < source.length) {
        const ch = source[i];
        if (ch === "\\") { i += 2; continue; }
        if (doubleQuoted) {
            if (ch === "\"") doubleQuoted = false;
            i++;
            continue;
        }
        if (ch === "\"") { doubleQuoted = true; i++; continue; }
        if (ch === "'") {
            const end = source.indexOf("'", i + 1);
            i = end < 0 ? source.length : end + 1;
            continue;
        }
        if (ch === "<" && source[i + 1] === "<" && source[i + 2] !== "<") {
            const match = /^<<(-?)\s*(['"]?)([\w.]+)\2/.exec(source.slice(i, i + 200));
            if (match) {
                pendingHeredocs.push({ tag: match[3], stripTabs: match[1] === "-" });
                i += match[0].length;
                continue;
            }
        }
        if (ch === "\n" && pendingHeredocs.length > 0) {
            i++;
            for (const heredoc of pendingHeredocs.splice(0)) {
                while (i < source.length) {
                    const lineEnd = source.indexOf("\n", i);
                    const stop = lineEnd < 0 ? source.length : lineEnd;
                    const line = source.slice(i, stop);
                    i = Math.min(stop + 1, source.length);
                    if ((heredoc.stripTabs ? line.replace(/^\t+/, "") : line) === heredoc.tag) break;
                }
            }
            continue;
        }
        if (ch === "#" && (i === 0 || /[\s;|&(]/.test(source[i - 1]))) {
            const start = i;
            while (i < source.length && source[i] !== "\n") i++;
            comments.push({ start, end: i });
            continue;
        }
        i++;
    }
    return comments;
}

function isShell(file, source) {
    return path.extname(file) === ".sh" || /^#!.*\b(?:sh|bash|zsh)\b/.test(source);
}

function describe(source, { start, end }) {
    const lineStart = source.lastIndexOf("\n", start - 1) + 1;
    const nextNewline = source.indexOf("\n", end);
    const lineEnd = nextNewline < 0 ? source.length : nextNewline;
    const text = source.slice(start, end);
    const standalone = source.slice(lineStart, start).trim() === "" && source.slice(end, lineEnd).trim() === "";
    return {
        line: source.slice(0, start).split("\n").length,
        lines: text.split("\n").length,
        standalone,
        text,
        lineStart,
        lineEnd,
        start,
        end
    };
}

function commentsIn(file, source) {
    let ranges;
    if (C_LIKE.has(path.extname(file))) ranges = scanCLike(source);
    else if (isShell(file, source)) ranges = scanShell(source);
    else return null;
    return ranges
        .map(range => describe(source, range))
        .filter(comment => !DIRECTIVE.test(comment.text));
}

function strip(source, comments) {
    let result = "";
    let cursor = 0;
    for (const comment of comments) {
        if (!comment.standalone) {
            result += source.slice(cursor, comment.start).replace(/[ \t]+$/, "");
            cursor = comment.end;
            continue;
        }
        result += source.slice(cursor, comment.lineStart);
        cursor = Math.min(comment.lineEnd + 1, source.length);
        const opensGap = result === "" || /(?:\n|[{[(])[ \t]*\n$/.test(result);
        const rest = source.slice(cursor);
        if (opensGap && /^[ \t]*\n/.test(rest)) cursor += rest.indexOf("\n") + 1;
        else if (/^[ \t]*(?:[}\])]|$)/.test(rest)) result = result.replace(/\n[ \t]*\n$/, "\n");
    }
    return result + source.slice(cursor);
}

function trackedFiles() {
    return execFileSync("git", ["ls-files", "-z"], { cwd: ROOT, encoding: "utf8" })
        .split("\0")
        .filter(Boolean)
        .filter(file => fs.existsSync(path.join(ROOT, file)));
}

function survey() {
    const report = {};
    for (const file of trackedFiles()) {
        const buffer = fs.readFileSync(path.join(ROOT, file));
        if (buffer.includes(0)) continue;
        const comments = commentsIn(file, buffer.toString("utf8"));
        if (comments !== null) report[file] = comments;
    }
    return report;
}

function countsOf(report) {
    const counts = {};
    for (const [file, comments] of Object.entries(report)) {
        const lines = comments.reduce((sum, comment) => sum + comment.lines, 0);
        if (lines > 0) counts[file] = lines;
    }
    return counts;
}

function readBaseline() {
    return fs.existsSync(BASELINE_PATH) ? JSON.parse(fs.readFileSync(BASELINE_PATH, "utf8")) : {};
}

function writeBaseline(counts) {
    const sorted = Object.fromEntries(Object.entries(counts).sort(([a], [b]) => a.localeCompare(b)));
    fs.writeFileSync(BASELINE_PATH, `${JSON.stringify(sorted, null, 2)}\n`);
}

function check(report) {
    const counts = countsOf(report);
    const baseline = readBaseline();
    const problems = [];
    for (const [file, count] of Object.entries(counts)) {
        const allowed = baseline[file] ?? 0;
        if (count <= allowed) continue;
        problems.push(`${file}: ${count} comment lines, baseline allows ${allowed}`);
        for (const comment of report[file]) {
            problems.push(`  ${file}:${comment.line}: ${comment.text.split("\n")[0].slice(0, 100)}`);
        }
    }
    for (const [file, allowed] of Object.entries(baseline)) {
        const count = counts[file] ?? 0;
        if (count < allowed) {
            problems.push(`${file}: ${count} comment lines, baseline still allows ${allowed}; run \`node tests/lint_comments.js --tighten\` and commit the result`);
        }
    }
    return problems;
}

function tighten(report) {
    const counts = countsOf(report);
    const baseline = readBaseline();
    const tightened = {};
    const refused = [];
    for (const [file, count] of Object.entries(counts)) {
        const allowed = baseline[file] ?? 0;
        if (count > allowed) refused.push(`${file}: ${count} comment lines, baseline allows ${allowed}`);
        tightened[file] = Math.min(count, allowed);
    }
    for (const file of Object.keys(tightened)) if (tightened[file] === 0) delete tightened[file];
    writeBaseline(tightened);
    return refused;
}

function main(argv) {
    const mode = argv[0] ?? "--check";
    const report = survey();
    if (mode === "--list") {
        const rows = Object.entries(report).flatMap(([file, comments]) => comments.map(comment => ({ file, ...comment })));
        process.stdout.write(`${JSON.stringify(rows, null, 2)}\n`);
        return 0;
    }
    if (mode === "--stats") {
        const all = Object.values(report).flat();
        const standalone = all.filter(comment => comment.standalone);
        process.stdout.write(`${JSON.stringify({
            files: Object.keys(countsOf(report)).length,
            comments: all.length,
            standaloneComments: standalone.length,
            trailingComments: all.length - standalone.length,
            commentOnlyLines: standalone.reduce((sum, comment) => sum + comment.lines, 0),
            physicalLines: Object.keys(report).reduce((sum, file) => sum + fs.readFileSync(path.join(ROOT, file), "utf8").split("\n").length - 1, 0)
        }, null, 2)}\n`);
        return 0;
    }
    if (mode === "--strip") {
        const wanted = new Set(argv.slice(1));
        for (const [file, comments] of Object.entries(report)) {
            if (comments.length === 0 || (wanted.size > 0 && !wanted.has(file))) continue;
            const target = path.join(ROOT, file);
            fs.writeFileSync(target, strip(fs.readFileSync(target, "utf8"), comments));
        }
        return 0;
    }
    const problems = mode === "--tighten" ? tighten(report) : mode === "--check" ? check(report) : [`unknown mode ${mode}`];
    if (problems.length === 0) return 0;
    process.stderr.write(`Comments are banned (docs/adr/0001-ban-code-comments.md).\n${problems.join("\n")}\n`);
    return 1;
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));

module.exports = { commentsIn, strip };
