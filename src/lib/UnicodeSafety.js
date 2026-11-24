.pragma library

function isUnsafeFormattingCodePoint(codePoint) {
    return codePoint === 0x00ad || codePoint === 0x034f || codePoint === 0x061c
        || (codePoint >= 0x115f && codePoint <= 0x1160)
        || (codePoint >= 0x17b4 && codePoint <= 0x17b5)
        || (codePoint >= 0x180b && codePoint <= 0x180f)
        || (codePoint >= 0x200b && codePoint <= 0x200f)
        || (codePoint >= 0x2028 && codePoint <= 0x202e)
        || (codePoint >= 0x2060 && codePoint <= 0x206f)
        || codePoint === 0x3164
        || (codePoint >= 0xfe00 && codePoint <= 0xfe0f)
        || codePoint === 0xfeff || codePoint === 0xffa0
        || (codePoint >= 0xfff0 && codePoint <= 0xfffb)
        || (codePoint >= 0x1bca0 && codePoint <= 0x1bca3)
        || (codePoint >= 0x1d173 && codePoint <= 0x1d17a)
        || (codePoint >= 0xe0000 && codePoint <= 0xe0fff);
}
