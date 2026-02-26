export class RateLimiter {
  private lastSent = new Map<string, number>();

  isAllowed(
    type: string,
    cooldownSeconds: number
  ): { allowed: boolean; remainingSeconds?: number } {
    if (cooldownSeconds <= 0) return { allowed: true };

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

  record(type: string): void {
    this.lastSent.set(type, Date.now());
  }

  getState(): Record<string, { lastSent: string; elapsedSeconds: number }> {
    const state: Record<string, { lastSent: string; elapsedSeconds: number }> = {};
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
