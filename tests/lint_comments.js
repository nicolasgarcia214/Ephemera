#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");
const BASELINE_PATH = path.join(__dirname, "comment-baseline.json");
const C_LIKE_EXTENSIONS = new Set([".js", ".cjs", ".mjs", ".qml"]);
const SHELLS = new Set(["sh", "bash", "zsh", "dash", "ksh"]);
const DIRECTIVES = [
    /^# shellcheck (?:disable|enable|source|source-path|shell|external-sources)=\S/,
    /^\/\/ qmllint (?:disable|enable)\b/,
    /^\/\/ x-release-please-(?:version|major|minor|patch|start-\w+|end)$/,
    /^\/\/@ pragma \w/
];
const REGEX_PRECEDING_WORDS = new Set([
    "return", "typeof", "case", "in", "of", "void", "delete", "throw", "new",
    "else", "do", "instanceof", "yield", "await"
]);
const REGEX_PRECEDING_PUNCTUATION = new Set("(,=:[!&|?{;+-*%<>~^");
const OPERAND = "operand";

function lineEndFrom(source, index) {
    const end = source.indexOf("\n", index);
    return end < 0 ? source.length : end;
}

function scanCLike(source) {
    const comments = [];
    const templateDepths = [];
    let braceDepth = 0;
    let previous = "";
    let i = source.startsWith("#!") ? lineEndFrom(source, 0) : 0;

    const skipQuoted = quote => {
        i++;
        while (i < source.length && source[i] !== quote && source[i] !== "\n") i += source[i] === "\\" ? 2 : 1;
        i++;
        return OPERAND;
    };
    const skipTemplateText = () => {
        while (i < source.length) {
            if (source[i] === "\\") i += 2;
            else if (source[i] === "`") { i++; return OPERAND; }
            else if (source[i] === "$" && source[i + 1] === "{") {
                i += 2;
                templateDepths.push(braceDepth++);
                return "(";
            } else i++;
        }
        return OPERAND;
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
        return OPERAND;
    };
    const skipWord = () => {
        const start = i;
        while (i < source.length && /[\w$]/.test(source[i])) i++;
        return previous === "." ? OPERAND : source.slice(start, i);
    };
    const regexAllowed = () => previous === ""
        || REGEX_PRECEDING_PUNCTUATION.has(previous)
        || REGEX_PRECEDING_WORDS.has(previous);

    while (i < source.length) {
        const ch = source[i];
        const next = source[i + 1];
        if (/\s/.test(ch)) i++;
        else if (ch === "/" && (next === "/" || next === "*")) {
            const start = i;
            if (next === "/") i = lineEndFrom(source, i);
            else {
                const end = source.indexOf("*/", i + 2);
                i = end < 0 ? source.length : end + 2;
            }
            comments.push({ start, end: i });
        } else if (ch === "\"" || ch === "'") previous = skipQuoted(ch);
        else if (ch === "`") { i++; previous = skipTemplateText(); }
        else if (ch === "/" && regexAllowed()) previous = skipRegex();
        else if (/[\w$]/.test(ch)) previous = skipWord();
        else if ((ch === "+" || ch === "-") && next === ch) { i += 2; previous = OPERAND; }
        else if (ch === "}") {
            braceDepth--;
            i++;
            previous = ch;
            if (templateDepths.at(-1) === braceDepth) {
                templateDepths.pop();
                previous = skipTemplateText();
            }
        } else {
            if (ch === "{") braceDepth++;
            i++;
            previous = ch;
        }
    }
    return comments;
}

function scanShell(source) {
    const comments = [];
    const pendingHeredocs = [];
    let i = 0;
    let doubleQuoted = false;

    const skipPast = (terminator, from) => {
        const end = source.indexOf(terminator, from);
        i = end < 0 ? source.length : end + terminator.length;
    };
    const skipHeredocBodies = () => {
        for (const heredoc of pendingHeredocs.splice(0)) {
            while (i < source.length) {
                const stop = lineEndFrom(source, i);
                const line = source.slice(i, stop).replace(/\r$/, "");
                i = Math.min(stop + 1, source.length);
                if ((heredoc.stripTabs ? line.replace(/^\t+/, "") : line) === heredoc.tag) break;
            }
        }
    };

    while (i < source.length) {
        const ch = source[i];
        if (ch === "\\") i += 2;
        else if (doubleQuoted) {
            if (ch === "\"") doubleQuoted = false;
            i++;
        } else if (ch === "\"") { doubleQuoted = true; i++; }
        else if (ch === "'") skipPast("'", i + 1);
        else if (ch === "`") skipPast("`", i + 1);
        else if (source.startsWith("$'", i)) {
            i += 2;
            while (i < source.length && source[i] !== "'") i += source[i] === "\\" ? 2 : 1;
            i++;
        } else if (source.startsWith("$((", i)) skipPast("))", i + 3);
        else if (source.startsWith("${", i)) skipPast("}", i + 2);
        else if (source.startsWith("<<", i) && source[i + 2] !== "<") {
            const match = /^<<(-?)[ \t]*(?:\\?([\w.-]+)|'([^'\n]+)'|"([^"\n]+)")/.exec(source.slice(i, i + 200));
            if (match) pendingHeredocs.push({ tag: match[2] ?? match[3] ?? match[4], stripTabs: match[1] === "-" });
            i += match ? match[0].length : 2;
        } else if (ch === "\n" && pendingHeredocs.length > 0) {
            i++;
            skipHeredocBodies();
        } else if (ch === "#" && (i === 0 || /[\s;|&(]/.test(source[i - 1]))) {
            const start = i;
            i = lineEndFrom(source, i);
            if (start > 0 || source[1] !== "!") comments.push({ start, end: i });
        } else i++;
    }
    return comments;
}

function scannerFor(file, source) {
    const extension = path.extname(file).toLowerCase();
    if (C_LIKE_EXTENSIONS.has(extension)) return scanCLike;
    if (extension === ".sh") return scanShell;
    const interpreter = /^#!\s*(?:\S*\/env\s+)?(?:\S*\/)?([\w.-]+)/.exec(source)?.[1];
    if (interpreter === "node") return scanCLike;
    return SHELLS.has(interpreter) ? scanShell : null;
}

function commentsIn(file, source) {
    const scan = scannerFor(file, source);
    if (scan === null) return null;
    return scan(source)
        .map(({ start, end }) => {
            const lineStart = source.lastIndexOf("\n", start - 1) + 1;
            const lineEnd = lineEndFrom(source, end);
            const text = source.slice(start, end);
            return {
                line: source.slice(0, start).split("\n").length,
                lines: text.split("\n").length,
                standalone: source.slice(lineStart, start).trim() === "" && source.slice(end, lineEnd).trim() === "",
                text,
                start,
                end,
                lineStart,
                lineEnd
            };
        })
        .filter(comment => !DIRECTIVES.some(directive => directive.test(comment.text)));
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

function survey() {
    const report = {};
    const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: ROOT, encoding: "utf8" }).split("\0");
    for (const file of tracked) {
        const target = path.join(ROOT, file);
        if (file === "" || !fs.statSync(target, { throwIfNoEntry: false })?.isFile()) continue;
        const comments = commentsIn(file, fs.readFileSync(target, "utf8"));
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

function check(counts, baseline) {
    const problems = [];
    for (const file of new Set([...Object.keys(counts), ...Object.keys(baseline)])) {
        const count = counts[file] ?? 0;
        const allowed = baseline[file] ?? 0;
        if (count !== allowed) problems.push({ file, count, allowed });
    }
    return problems;
}

function tighten(counts, baseline) {
    const tightened = {};
    for (const file of Object.keys(counts).sort()) {
        const allowed = Math.min(counts[file], baseline[file] ?? 0);
        if (allowed > 0) tightened[file] = allowed;
    }
    return tightened;
}

function readBaseline() {
    return fs.existsSync(BASELINE_PATH) ? JSON.parse(fs.readFileSync(BASELINE_PATH, "utf8")) : {};
}

function writeBaseline(baseline) {
    if (Object.keys(baseline).length > 0) fs.writeFileSync(BASELINE_PATH, `${JSON.stringify(baseline, null, 2)}\n`);
    else fs.rmSync(BASELINE_PATH, { force: true });
}

function describeProblem({ file, count, allowed }, comments) {
    if (count < allowed)
        return [`${file}: ${count} comment lines, baseline still allows ${allowed}; run \`node tests/lint_comments.js --tighten\` and commit the result`];
    return [
        `${file}: ${count} comment lines, baseline allows ${allowed}`,
        ...comments.map(comment => `  ${file}:${comment.line}: ${comment.text.split("\n")[0].slice(0, 100)}`)
    ];
}

function selectFiles(report, args) {
    const wanted = args.map(arg => path.relative(ROOT, path.resolve(arg)));
    const unknown = wanted.filter(file => !(file in report));
    if (unknown.length > 0) throw new Error(`not a tracked source file: ${unknown.join(", ")}`);
    return wanted.length > 0 ? wanted : Object.keys(report);
}

const MODES = {
    "--check"(report) {
        const problems = check(countsOf(report), readBaseline());
        if (problems.length === 0) return 0;
        const lines = problems.flatMap(problem => describeProblem(problem, report[problem.file] ?? []));
        process.stderr.write(`Comments are banned (docs/adr/0001-ban-code-comments.md).\n${lines.join("\n")}\n`);
        return 1;
    },
    "--tighten"(report) {
        writeBaseline(tighten(countsOf(report), readBaseline()));
        return MODES["--check"](report);
    },
    "--list"(report, args) {
        const rows = selectFiles(report, args).flatMap(file => report[file].map(
            ({ line, lines, standalone, text }) => ({ file, line, lines, standalone, text })));
        process.stdout.write(`${JSON.stringify(rows, null, 2)}\n`);
        return 0;
    },
    "--strip"(report, args) {
        if (args.length === 0) throw new Error("--strip needs at least one file");
        for (const file of selectFiles(report, args)) {
            const target = path.join(ROOT, file);
            fs.writeFileSync(target, strip(fs.readFileSync(target, "utf8"), report[file]));
        }
        return 0;
    }
};

function main([mode = "--check", ...args]) {
    try {
        if (!(mode in MODES)) throw new Error(`unknown mode ${mode}; expected one of ${Object.keys(MODES).join(", ")}`);
        return MODES[mode](survey(), args);
    } catch (error) {
        process.stderr.write(`lint_comments: ${error.message}\n`);
        return 2;
    }
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));

module.exports = { commentsIn, strip, check, tighten };
