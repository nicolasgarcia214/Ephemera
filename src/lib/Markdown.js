.pragma library

function escapeHtml(str) {
    if (!str) return "";
    return str.replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;');
}

function renderCacheKey(text, colors) {
    var c = colors || {};
    return JSON.stringify([
        text || "",
        String(c.codeBg || ""),
        String(c.inlineCodeBg || ""),
        String(c.tableHeaderBg || ""),
        String(c.blockquoteBg || ""),
        String(c.blockquoteBorder || ""),
        String(c.blockquoteText || "")
    ]);
}

function markdownToHtml(text, colors) {
    if (!text) return "";

    var supplied = colors || {};
    var c = {
        codeBg: supplied.codeBg || "#20FFFFFF",
        inlineCodeBg: supplied.inlineCodeBg || "#30FFFFFF",
        tableHeaderBg: supplied.tableHeaderBg
            || supplied.inlineCodeBg || "#30FFFFFF",
        blockquoteBg: supplied.blockquoteBg || "transparent",
        blockquoteBorder: supplied.blockquoteBorder || "#808080",
        blockquoteText: supplied.blockquoteText || "#a0a0a0"
    };

    var codeBlocks = [];
    var inlineCode = [];
    var protectedBlocks = [];
    var blockIndex = 0;
    var inlineIndex = 0;
    var protectedIndex = 0;

    var html = text.replace(/```(?:([^\n]*)\n)?([\s\S]*?)```/g, function(match, lang, code) {
        var trimmedCode = (code || "").replace(/^\n+|\n+$/g, '');
        var escapedCode = escapeHtml(trimmedCode);

        var languageLabel = lang && lang.trim()
            ? '<div style="font-size: 9px; opacity: 0.6; padding-bottom: 4px;">' + escapeHtml(lang.trim()) + '</div>'
            : '';

        codeBlocks.push('<div style="background-color: ' + c.codeBg + '; padding: 10px; margin: 8px 0;">' + languageLabel + '<pre style="margin: 0;"><code>' + escapedCode + '</code></pre></div>');
        return '\x00CODEBLOCK' + (blockIndex++) + '\x00';
    });

    html = html.replace(/`([^`]+)`/g, function(match, code) {
        var escapedCode = escapeHtml(code);
        inlineCode.push('<span style="font-family: monospace; background-color: ' + c.inlineCodeBg + ';">&nbsp;' + escapedCode + '&nbsp;</span>');
        return '\x00INLINECODE' + (inlineIndex++) + '\x00';
    });

    html = html.replace(/^\|(.+)\|\s*\n\|[\s\-:|]+\|\s*\n((?:\|.+\|\s*\n?)+)/gm, function(match, headerRow, dataRows) {
        var rawHeaders = headerRow.split('|').map(function(h) { return h.trim(); });
        if (rawHeaders.length > 0 && rawHeaders[0] === '') rawHeaders.shift();
        if (rawHeaders.length > 0 && rawHeaders[rawHeaders.length - 1] === '') rawHeaders.pop();
        var headers = rawHeaders;
        var numCols = headers.length;

        var rows = dataRows.trim().split('\n').map(function(row) {
            var cells = row.split('|').map(function(cell) { return cell.trim(); });
            if (cells.length > 0 && cells[0] === '') cells.shift();
            if (cells.length > 0 && cells[cells.length - 1] === '') cells.pop();
            while (cells.length < numCols) cells.push("");
            if (cells.length > numCols) cells = cells.slice(0, numCols);
            return cells;
        });

        var tableHtml = '<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; margin: 8px 0;">';

        tableHtml += '<tr>';
        for (var h = 0; h < headers.length; h++) {
            tableHtml += '<th style="background-color: ' + c.tableHeaderBg + '; padding: 5px;">' + escapeHtml(headers[h]) + '</th>';
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

    html = html.replace(/&/g, '&amp;')
               .replace(/</g, '&lt;')
               .replace(/>/g, '&gt;');

    var links = [];
    function protectLink(anchorHtml) {
        links.push(anchorHtml);
        return '\x00LINK' + (links.length - 1) + '\x00';
    }
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(match, text, url) {
        if (/^https?:\/\//i.test(url))
            return '<a href="' + protectLink(url.replace(/"/g, '&quot;')) + '">' + text + '</a>';
        return text + ' (' + url + ')';
    });
    html = html.replace(/(^|[^"'>])(https?:\/\/[^\s<\x00]+)/g, function(match, pre, url) {
        var end = url.length;
        while (end > 0) {
            var last = url.charAt(end - 1);
            var unbalanced = last === ")"
                && url.slice(0, end).split(")").length > url.slice(0, end).split("(").length;
            if ("*_~.,;:!?".indexOf(last) < 0 && !unbalanced)
                break;
            end--;
        }
        var href = url.slice(0, end);
        if (!/^https?:\/\/./i.test(href))
            return match;
        return pre + protectLink('<a href="' + href.replace(/"/g, '&quot;') + '">' + href + '</a>')
            + url.slice(end);
    });

    html = html.replace(/^######\s+([\s\S]*?)$/gm, '<h6 style="margin-bottom: 8px;"><font size="2">$1</font></h6>');
    html = html.replace(/^#####\s+([\s\S]*?)$/gm, '<h5 style="margin-bottom: 8px;"><i><font size="3">$1</font></i></h5>');
    html = html.replace(/^####\s+([\s\S]*?)$/gm, '<h4 style="margin-bottom: 8px;"><font size="3">$1</font></h4>');
    html = html.replace(/^###\s+([\s\S]*?)$/gm, '<h3 style="margin-bottom: 8px;"><font size="4">$1</font></h3>');
    html = html.replace(/^##\s+([\s\S]*?)$/gm, '<h2 style="margin-bottom: 8px;"><font size="5">$1</font></h2>');
    html = html.replace(/^#\s+([\s\S]*?)$/gm, '<h1 style="margin-bottom: 10px;"><font size="6">$1</font></h1>');

    html = html.replace(/^(\*{3,}|-{3,}|_{3,})$/gm, '<hr style="margin: 12px 0;"/>');

    html = html.replace(/\*\*\*(.*?)\*\*\*/g, '<b><i>$1</i></b>');
    html = html.replace(/\*\*(.*?)\*\*/g, '<b>$1</b>');
    html = html.replace(/\*(.*?)\*/g, '<i>$1</i>');
    html = html.replace(/(^|[^A-Za-z0-9_])___(.+?)___(?![A-Za-z0-9_])/g, '$1<b><i>$2</i></b>');
    html = html.replace(/(^|[^A-Za-z0-9_])__(.+?)__(?![A-Za-z0-9_])/g, '$1<b>$2</b>');
    html = html.replace(/(^|[^A-Za-z0-9_])_(.+?)_(?![A-Za-z0-9_])/g, '$1<i>$2</i>');

    html = html.replace(/~~(.*?)~~/g, '<s>$1</s>');

    html = html.replace(/^\s*[\*\-] \[([ xX])\] (.*?)$/gm, function(match, checked, content) {
        var checkbox = checked.toLowerCase() === 'x' ? '\u2611' : '\u2610';
        return '<li_task>' + checkbox + ' ' + content + '</li_task>';
    });

    html = html.replace(/^\s*[\*\-] (.*?)$/gm, '<li_ul>$1</li_ul>');
    html = html.replace(/^\s*\d+\. (.*?)$/gm, '<li_ol>$1</li_ol>');

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

    html = html.replace(/^&gt; (.*?)$/gm, '<bq_line>$1</bq_line>');
    html = html.replace(/(<bq_line>[\s\S]*?<\/bq_line>\s*)+/g, function(match) {
        var inner = match.replace(/<\/bq_line>\s*<bq_line>/g, '<br/>')
                        .replace(/<bq_line>/g, '')
                        .replace(/<\/bq_line>/g, '')
                        .trim();
        var block = '<blockquote style="background-color: ' + c.blockquoteBg + '; border-left: 4px solid ' + c.blockquoteBorder + '; padding: 4px; margin: 8px 0;"><font color="' + c.blockquoteText + '"><i>' + inner + '</i></font></blockquote>';
        protectedBlocks.push(block);
        return '\x00PROTECTEDBLOCK' + (protectedIndex++) + '\x00\n';
    });

    html = html.replace(/\n\n/g, '</p><p>');
    html = html.replace(/\n/g, '<br/>');

    if (!html.startsWith('<') && !html.startsWith('\x00')) {
        html = '<p>' + html + '</p>';
    }

    html = html.replace(/\x00PROTECTEDBLOCK(\d+)\x00/g, function(match, index) {
        var idx = parseInt(index);
        return idx < protectedBlocks.length ? protectedBlocks[idx] : match;
    });

    html = html.replace(/\x00CODEBLOCK(\d+)\x00/g, function(match, index) {
        var idx = parseInt(index);
        return idx < codeBlocks.length ? codeBlocks[idx] : match;
    });

    html = html.replace(/\x00INLINECODE(\d+)\x00/g, function(match, index) {
        var idx = parseInt(index);
        return idx < inlineCode.length ? inlineCode[idx] : match;
    });

    html = html.replace(/\x00LINK(\d+)\x00/g, function(match, index) {
        var idx = parseInt(index);
        return idx < links.length ? links[idx] : match;
    });

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
