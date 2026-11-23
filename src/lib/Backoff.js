.pragma library

// Exponential backoff with full jitter for error cooldown.
// Replaces the flat 2-second cooldown with progressive delays that spread
// retries and avoid thundering-herd synchronization.

/**
 * Compute the next backoff delay using exponential backoff with full jitter.
 *
 * Formula: delay = random(floor, min(maxDelayMs, baseDelayMs * 2^attempt))
 * where floor = baseDelayMs * 0.5 ensures a minimum wait even at low jitter.
 *
 * @param {number} attempt - Zero-based attempt counter (0 = first error).
 * @param {number} [baseDelayMs=2000] - Base delay in milliseconds.
 * @param {number} [maxDelayMs=30000] - Maximum delay cap in milliseconds.
 * @returns {number} Delay in milliseconds (always >= baseDelayMs * 0.5).
 */
function computeDelay(attempt, baseDelayMs, maxDelayMs) {
    var base = baseDelayMs || 2000;
    var max = maxDelayMs || 30000;
    var exp = Math.min(max, base * Math.pow(2, attempt || 0));
    var floor = base * 0.5;
    return floor + Math.random() * (exp - floor);
}

/**
 * Compute the absolute timestamp at which cooldown expires for the current error.
 *
 * Call this once when an error occurs and store the result. Subsequent cooldown
 * checks compare Date.now() against the stored value — no re-randomization.
 *
 * @param {number} consecutiveErrors - Number of consecutive errors so far (after incrementing).
 * @param {number} [baseDelayMs=2000] - Base delay for backoff calculation.
 * @param {number} [maxDelayMs=30000] - Maximum delay cap.
 * @returns {number} Absolute timestamp (ms) when cooldown ends.
 */
function computeCooldownUntil(consecutiveErrors, baseDelayMs, maxDelayMs) {
    if (consecutiveErrors <= 0) return 0;
    var delay = computeDelay(consecutiveErrors - 1, baseDelayMs, maxDelayMs);
    return Date.now() + delay;
}

/**
 * Determine whether a retry is still in the cooldown period.
 *
 * @param {number} cooldownUntil - Absolute timestamp (ms) when cooldown expires, 0 if no cooldown.
 * @returns {boolean} true if the cooldown period has NOT elapsed and retry should be blocked.
 */
function isInCooldown(cooldownUntil) {
    if (cooldownUntil <= 0) return false;
    return Date.now() < cooldownUntil;
}
