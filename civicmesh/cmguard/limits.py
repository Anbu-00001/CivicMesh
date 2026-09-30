"""Bounded rate limiters and in-flight counters.

Token buckets keyed by client address, visitor or a single global key. Every
table is capped (least recently used keys are dropped), so rotating keys can't
grow memory without bound; the global bucket still limits the total.
Thread-safe: the jac-scale process calls these from worker threads.
"""

import threading
import time
from collections import OrderedDict


class TokenBuckets:
    """capacity tokens, refilled at capacity/window per second, per key."""

    def __init__(self, capacity: float, window_s: float, max_keys: int = 50000):
        self.capacity = float(capacity)
        self.window = float(window_s)
        self.rate = float(capacity) / float(window_s) if window_s > 0 else float("inf")
        self.max_keys = max_keys
        self._state = OrderedDict()  # key -> (tokens, last)
        self._lock = threading.Lock()

    def take(self, key: str, cost: float = 1.0, now: "float | None" = None):
        """(allowed, retry_after_seconds)."""
        now = time.monotonic() if now is None else now
        with self._lock:
            tokens, last = self._state.get(key, (self.capacity, now))
            tokens = min(self.capacity, tokens + (now - last) * self.rate)
            if tokens >= cost:
                self._state[key] = (tokens - cost, now)
                self._state.move_to_end(key)
                self._trim(now)
                return True, 0.0
            self._state[key] = (tokens, now)
            self._state.move_to_end(key)
            self._trim(now)
            wait = (cost - tokens) / self.rate if self.rate > 0 else 60.0
            return False, max(0.1, wait)

    def _trim(self, now: "float | None" = None):
        while len(self._state) > self.max_keys:
            self._state.popitem(last=False)
        # A key idle for a whole window has a full bucket again: it carries no
        # information, so it's forgotten (least recently used keys are first).
        if now is not None:
            while self._state:
                key, (_, last) = next(iter(self._state.items()))
                if now - last <= self.window:
                    break
                self._state.popitem(last=False)

    def __len__(self):
        return len(self._state)


class InflightCounter:
    """At most `limit` concurrent holders per key."""

    def __init__(self, limit: int, max_keys: int = 50000):
        self.limit = int(limit)
        self.max_keys = max_keys
        self._count = {}
        self._lock = threading.Lock()

    def acquire(self, key: str) -> bool:
        with self._lock:
            n = self._count.get(key, 0)
            if n >= self.limit or (n == 0 and len(self._count) >= self.max_keys):
                return False
            self._count[key] = n + 1
            return True

    def release(self, key: str) -> None:
        with self._lock:
            n = self._count.get(key, 0) - 1
            if n <= 0:
                self._count.pop(key, None)
            else:
                self._count[key] = n

    def current(self, key: str) -> int:
        with self._lock:
            return self._count.get(key, 0)


class ExpiringSet:
    """Remembers keys until they expire, bounded (used for replay counts)."""

    def __init__(self, max_keys: int = 100000):
        self.max_keys = max_keys
        self._items = OrderedDict()  # key -> (count, expires_at)
        self._lock = threading.Lock()

    def bump(self, key: str, expires_at: float, now: "float | None" = None) -> int:
        """Count one more use of `key`; returns the new count."""
        now = time.time() if now is None else now
        with self._lock:
            self._expire(now)
            count, _ = self._items.get(key, (0, expires_at))
            count += 1
            self._items[key] = (count, expires_at)
            self._items.move_to_end(key)
            while len(self._items) > self.max_keys:
                self._items.popitem(last=False)
            return count

    def _expire(self, now: float) -> None:
        stale = [k for k, (_, exp) in list(self._items.items())[:256] if exp < now]
        for k in stale:
            self._items.pop(k, None)
