.pragma library

// Secure markdown-to-HTML converter for Ephemera.
// Based on DMS AI Assistant's markdown2html.js with security fixes:
//   1. escapeHtml() helper used consistently
//   2. Code block language labels escaped
//   3. Table header/cell content escaped
//   4. Link scheme whitelist (http/https only)
//   5. Auto-linker excludes file: scheme

function escapeHtml(str) {
    if (!str) return "";
    return str.replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;');
}

/**
 * Build a stable cache key for every input that affects rendered markdown.
 *
 * QColor values are stringified explicitly because QML passes them as value
 * types rather than plain JavaScript strings.
 *
 * @param {string} text - Raw markdown text.
 * @param {Object} colors - Theme colors passed to markdownToHtml().
 * @returns {string} Stable render-input cache key.
 */
function renderCacheKey(text, colors) {
    var c = colors || {};
    return JSON.stringify([
        text || "",
        String(c.codeBg || ""),
        String(c.inlineCodeBg || ""),
        String(c.blockquoteBg || ""),
        String(c.blockquoteBorder || "")
    ]);
}

/**
 * Convert markdown text to Qt-compatible HTML for display in QML Text (RichText mode).
 *
 * Processing pipeline:
 * 1. Extract fenced code blocks and inline code into placeholders (pre-escaped).
 * 2. Extract markdown tables into pre-built HTML (cell content escaped).
 * 3. Escape remaining HTML entities (&, <, >).
 * 4. Transform markdown syntax (headers, bold, italic, links, lists, blockquotes, hr).
 * 5. Wrap/protect list and blockquote HTML in placeholders.
 * 6. Auto-link plain URLs (http/https only).
 * 7. Convert newlines to <br/> and paragraph breaks.
 * 8. Restore all placeholders in reverse order.
 * 9. Clean up redundant break/paragraph tags.
 *
 * Security: All user text is HTML-escaped before inline formatting is applied.
 * Code block contents, table cells, link text, and link URLs are independently escaped.
 * Link href attributes are restricted to http/https schemes.
 *
 * @param {string} text - Raw markdown text.
 * @param {Object} [colors] - Theme colors for styled elements.
 * @param {string} colors.codeBg - Background color for fenced code blocks.
 * @param {string} colors.inlineCodeBg - Background color for inline code spans.
 * @param {string} colors.blockquoteBg - Background color for blockquotes.
 * @param {string} colors.blockquoteBorder - Left border color for blockquotes.
 * @returns {string} HTML string safe for QML Text.RichText rendering.
 */
function markdownToHtml(text, colors) {
    if (!text) return "";

    var c = colors || {
        codeBg: "#20FFFFFF",
        inlineCodeBg: "#30FFFFFF",
        blockquoteBg: "transparent",
        blockquoteBorder: "#808080"
    };

    var codeBlocks = [];
    var inlineCode = [];
    var protectedBlocks = [];
    var blockIndex = 0;
    var inlineIndex = 0;
    var protectedIndex = 0;

    // Extract code blocks with placeholders
    var html = text.replace(/```(?:([^\n]*)\n)?([\s\S]*?)```/g, function(match, lang, code) {
        var trimmedCode = (code || "").replace(/^\n+|\n+$/g, '');
        var escapedCode = escapeHtml(trimmedCode);

        // Escape language label — security fix
        var languageLabel = lang && lang.trim()
            ? '<div style="font-size: 9px; opacity: 0.6; padding-bottom: 4px;">' + escapeHtml(lang.trim()) + '</div>'
            : '';

        codeBlocks.push('<div style="background-color: ' + c.codeBg + '; padding: 10px; margin: 8px 0;">' + languageLabel + '<pre style="margin: 0;"><code>' + escapedCode + '</code></pre></div>');
        return '\x00CODEBLOCK' + (blockIndex++) + '\x00';
    });

    // Extract inline code
    html = html.replace(/`([^`]+)`/g, function(match, code) {
        var escapedCode = escapeHtml(code);
        inlineCode.push('<span style="font-family: monospace; background-color: ' + c.inlineCodeBg + ';">&nbsp;' + escapedCode + '&nbsp;</span>');
        return '\x00INLINECODE' + (inlineIndex++) + '\x00';
    });

    // Extract tables BEFORE HTML entity escaping — with escaped cell content
    html = html.replace(/^\|(.+)\|\s*\n\|[\s\-:|]+\|\s*\n((?:\|.+\|\s*\n?)+)/gm, function(match, headerRow, dataRows) {
        // Split by | but keep empty cells to preserve column alignment
        var rawHeaders = headerRow.split('|').map(function(h) { return h.trim(); });
        // Remove leading/trailing empty strings from the split (outer pipes)
        if (rawHeaders.length > 0 && rawHeaders[0] === '') rawHeaders.shift();
        if (rawHeaders.length > 0 && rawHeaders[rawHeaders.length - 1] === '') rawHeaders.pop();
        var headers = rawHeaders;
        var numCols = headers.length;

        var rows = dataRows.trim().split('\n').map(function(row) {
            var cells = row.split('|').map(function(cell) { return cell.trim(); });
            if (cells.length > 0 && cells[0] === '') cells.shift();
            if (cells.length > 0 && cells[cells.length - 1] === '') cells.pop();
            // Pad or trim to match header column count
            while (cells.length < numCols) cells.push("");
            if (cells.length > numCols) cells = cells.slice(0, numCols);
            return cells;
        });

        var tableHtml = '<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; margin: 8px 0;">';

        tableHtml += '<tr>';
        for (var h = 0; h < headers.length; h++) {
            tableHtml += '<th style="background-color: #30FFFFFF; padding: 5px;">' + escapeHtml(headers[h]) + '</th>';
        }
        tableHtml += '</tr>';

        for (var r = 0; r < rows.length; r++) {
            tableHtml += '<tr>';
            for (var cl = 0; cl < numCols; cl++) {
                tableHtml += '<td style="padding: 5px;">' + escapeHtml(rows[r][cl]) + '</td>';
            }
            tableHtml += '</tr>';
        }

        tableHtml += '</table>';
        protectedBlocks.push(tableHtml);
        return '\x00PROTECTEDBLOCK' + (protectedIndex++) + '\x00\n';
    });

    // Escape HTML entities (not in code blocks or tables — those are already protected)
    html = html.replace(/&/g, '&amp;')
               .replace(/</g, '&lt;')
               .replace(/>/g, '&gt;');

    // Headers
    html = html.replace(/^######\s+([\s\S]*?)$/gm, '<h6 style="margin-bottom: 8px;"><font size="2">$1</font></h6>');
    html = html.replace(/^#####\s+([\s\S]*?)$/gm, '<h5 style="margin-bottom: 8px;"><i><font size="3">$1</font></i></h5>');
    html = html.replace(/^####\s+([\s\S]*?)$/gm, '<h4 style="margin-bottom: 8px;"><font size="3">$1</font></h4>');
    html = html.replace(/^###\s+([\s\S]*?)$/gm, '<h3 style="margin-bottom: 8px;"><font size="4">$1</font></h3>');
    html = html.replace(/^##\s+([\s\S]*?)$/gm, '<h2 style="margin-bottom: 8px;"><font size="5">$1</font></h2>');
    html = html.replace(/^#\s+([\s\S]*?)$/gm, '<h1 style="margin-bottom: 10px;"><font size="6">$1</font></h1>');

    // Horizontal Rule
    html = html.replace(/^(\*{3,}|-{3,}|_{3,})$/gm, '<hr style="margin: 12px 0;"/>');

    // Bold and italic
    html = html.replace(/\*\*\*(.*?)\*\*\*/g, '<b><i>$1</i></b>');
    html = html.replace(/\*\*(.*?)\*\*/g, '<b>$1</b>');
    html = html.replace(/\*(.*?)\*/g, '<i>$1</i>');
    html = html.replace(/___(.*?)___/g, '<b><i>$1</i></b>');
    html = html.replace(/__(.*?)__/g, '<b>$1</b>');
    html = html.replace(/_(.*?)_/g, '<i>$1</i>');

    // Strikethrough
    html = html.replace(/~~(.*?)~~/g, '<s>$1</s>');

    // Links — with scheme whitelist; text and URL are escaped for safety
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(match, text, url) {
        if (/^https?:\/\//i.test(url)) {
            return '<a href="' + escapeHtml(url) + '">' + escapeHtml(text) + '</a>';
        }
        // Non-http(s) schemes: render as plain text
        return escapeHtml(text) + ' (' + escapeHtml(url) + ')';
    });

    // Task Lists
    html = html.replace(/^\s*[\*\-] \[([ xX])\] (.*?)$/gm, function(match, checked, content) {
        var checkbox = checked.toLowerCase() === 'x' ? '\u2611' : '\u2610';
        return '<li_task>' + checkbox + ' ' + content + '</li_task>';
    });

    // Lists
    html = html.replace(/^\s*[\*\-] (.*?)$/gm, '<li_ul>$1</li_ul>');
    html = html.replace(/^\s*\d+\. (.*?)$/gm, '<li_ol>$1</li_ol>');

    // Wrap and protect lists
    html = html.replace(/(<li_ul>[\s\S]*?<\/li_ul>\s*)+/g, function(match) {
        var content = match.replace(/<\/?li_ul>/g, function(tag) { return tag.replace('li_ul', 'li'); }).replace(/\n/g, '');
        var block = '<ul style="margin: 8px 0;">' + content + '</ul>';
        protectedBlocks.push(block);
        return '\x00PROTECTEDBLOCK' + (protectedIndex++) + '\x00\n';
    });

    html = html.replace(/(<li_ol>[\s\S]*?<\/li_ol>\s*)+/g, function(match) {
        var content = match.replace(/<\/?li_ol>/g, function(tag) { return tag.replace('li_ol', 'li'); }).replace(/\n/g, '');
        var block = '<ol style="margin: 8px 0;">' + content + '</ol>';
        protectedBlocks.push(block);
        return '\x00PROTECTEDBLOCK' + (protectedIndex++) + '\x00\n';
    });

    html = html.replace(/(<li_task>[\s\S]*?<\/li_task>\s*)+/g, function(match) {
        var content = match.replace(/<\/?li_task>/g, function(tag) { return tag.replace('li_task', 'li'); }).replace(/\n/g, '');
        var block = '<ul style="list-style-type: none; margin: 8px 0;">' + content + '</ul>';
        protectedBlocks.push(block);
        return '\x00PROTECTEDBLOCK' + (protectedIndex++) + '\x00\n';
    });

    // Blockquotes ('>' is already escaped to '&gt;')
    html = html.replace(/^&gt; (.*?)$/gm, '<bq_line>$1</bq_line>');
    html = html.replace(/(<bq_line>[\s\S]*?<\/bq_line>\s*)+/g, function(match) {
        var inner = match.replace(/<\/bq_line>\s*<bq_line>/g, '<br/>')
                        .replace(/<bq_line>/g, '')
                        .replace(/<\/bq_line>/g, '')
                        .trim();
        var block = '<blockquote style="background-color: ' + c.blockquoteBg + '; border-left: 4px solid ' + c.blockquoteBorder + '; padding: 4px; margin: 8px 0;"><font color="#a0a0a0"><i>' + inner + '</i></font></blockquote>';
        protectedBlocks.push(block);
        return '\x00PROTECTEDBLOCK' + (protectedIndex++) + '\x00\n';
    });

    // Auto-link plain URLs — http/https only (no file: scheme)
    html = html.replace(/(^|[^"'>])(https?:\/\/[^\s<]+)/g, function(match, pre, url) {
        return pre + '<a href="' + escapeHtml(url) + '">' + escapeHtml(url) + '</a>';
    });

    // Line breaks
    html = html.replace(/\n\n/g, '</p><p>');
    html = html.replace(/\n/g, '<br/>');

    if (!html.startsWith('<') && !html.startsWith('\x00')) {
        html = '<p>' + html + '</p>';
    }

    // Restore protected blocks (with bounds checking)
    html = html.replace(/\x00PROTECTEDBLOCK(\d+)\x00/g, function(match, index) {
        var idx = parseInt(index);
        return idx < protectedBlocks.length ? protectedBlocks[idx] : match;
    });

    // Restore code blocks and inline code AFTER protected blocks,
    // so placeholders captured inside lists/blockquotes/tables are reached
    html = html.replace(/\x00CODEBLOCK(\d+)\x00/g, function(match, index) {
        var idx = parseInt(index);
        return idx < codeBlocks.length ? codeBlocks[idx] : match;
    });

    html = html.replace(/\x00INLINECODE(\d+)\x00/g, function(match, index) {
        var idx = parseInt(index);
        return idx < inlineCode.length ? inlineCode[idx] : match;
    });

    // Cleanup
    html = html.replace(/<br\/>\s*(<pre>)/g, '$1');
    html = html.replace(/<br\/>\s*(<ul[^>]*>)/g, '$1');
    html = html.replace(/<br\/>\s*(<ol[^>]*>)/g, '$1');
    html = html.replace(/<br\/>\s*(<blockquote[^>]*>)/g, '$1');
    html = html.replace(/<br\/>\s*(<table[^>]*>)/g, '$1');
    html = html.replace(/<br\/>\s*(<h[1-6][^>]*>)/g, '$1');
    html = html.replace(/<p>\s*<\/p>/g, '');
    html = html.replace(/<p>\s*<br\/>\s*<\/p>/g, '');
    html = html.replace(/(<br\/>){3,}/g, '<br/><br/>');
    html = html.replace(/(<\/p>)\s*(<p>)/g, '$1$2');
    html = html.trim();

    return html;
}
