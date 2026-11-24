.pragma library

function computeDelay(attempt, baseDelayMs, maxDelayMs) {
    var base = baseDelayMs || 2000;
    var max = maxDelayMs || 30000;
    var exp = Math.min(max, base * Math.pow(2, attempt || 0));
    var floor = base * 0.5;
    return floor + Math.random() * (exp - floor);
}

function computeCooldownUntil(consecutiveErrors, baseDelayMs, maxDelayMs) {
    if (consecutiveErrors <= 0) return 0;
    var delay = computeDelay(consecutiveErrors - 1, baseDelayMs, maxDelayMs);
    return Date.now() + delay;
}

function isInCooldown(cooldownUntil) {
    if (cooldownUntil <= 0) return false;
    return Date.now() < cooldownUntil;
}
