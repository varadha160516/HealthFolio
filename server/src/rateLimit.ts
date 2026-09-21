// A small fixed-window limiter for the few endpoints reachable without a login (sign-up and the invite
// check). In-memory like the session store: fine for one process, and it resets on restart. Keyed by the
// caller's address, which is the real client because nothing sits in front of this server yet — once a
// proxy or load balancer does, `trust proxy` has to be configured or every caller shares one address.
const hits = new Map<string, { count: number; resetAt: number }>();

/** Counts this attempt and returns true once the caller has gone over [max] in the current window. */
export function overLimit(key: string, max: number, windowMs: number): boolean {
  const t = Date.now();
  const entry = hits.get(key);
  if (!entry || entry.resetAt <= t) {
    hits.set(key, { count: 1, resetAt: t + windowMs });
    return false;
  }
  entry.count++;
  return entry.count > max;
}

export function resetRateLimits() {
  hits.clear();
}
