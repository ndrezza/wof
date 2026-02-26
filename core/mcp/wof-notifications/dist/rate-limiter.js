export class RateLimiter {
    lastSent = new Map();
    isAllowed(type, cooldownSeconds) {
        if (cooldownSeconds <= 0)
            return { allowed: true };
        const now = Date.now();
        const last = this.lastSent.get(type);
        if (last) {
            const elapsedMs = now - last;
            const cooldownMs = cooldownSeconds * 1000;
            if (elapsedMs < cooldownMs) {
                return {
                    allowed: false,
                    remainingSeconds: Math.ceil((cooldownMs - elapsedMs) / 1000),
                };
            }
        }
        return { allowed: true };
    }
    record(type) {
        this.lastSent.set(type, Date.now());
    }
    getState() {
        const state = {};
        const now = Date.now();
        for (const [type, ts] of this.lastSent) {
            state[type] = {
                lastSent: new Date(ts).toISOString(),
                elapsedSeconds: Math.round((now - ts) / 1000),
            };
        }
        return state;
    }
}
