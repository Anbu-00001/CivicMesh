"""A process-wide model budget and circuit breaker.

Every model call in CivicMesh goes through litellm: byllm's ModelPool (a
litellm Router: one litellm.completion per model it falls back through) and
llm/translate.jac (litellm.completion per segment, up to eight in parallel).
`install()` wraps litellm.completion / acompletion once, so every attempt,
fallback and parallel segment draws on the same budget:

  * calls per minute, hour and day, and estimated tokens per day
  * a cap on concurrent calls (a short wait, then refuse)
  * a cap on the size of one request
  * a circuit breaker: after N consecutive failures, all calls are refused for
    a cooldown that doubles on each re-trip (up to a maximum)

A refusal raises ModelBudgetExceeded before any network request. Callers
(narration, translation, the optional routing fallback) already treat a model
failure as "no optional text": the deterministic answer is unaffected.
"""

import threading
import time
from collections import deque

from cmguard import telemetry
from cmguard.config import BudgetConfig


class ModelBudgetExceeded(RuntimeError):
    """The model budget or circuit breaker refused a call (fail closed)."""


class ModelBudget:
    def __init__(self, cfg: "BudgetConfig | None" = None):
        self.cfg = cfg or BudgetConfig()
        self._lock = threading.Lock()
        self._slots = threading.BoundedSemaphore(max(1, self.cfg.concurrent))
        self._minute = deque()
        self._hour = deque()
        self._day = deque()
        self._tokens = deque()  # (t, tokens)
        self._fails = 0
        self._open_until = 0.0
        self._cooldown = self.cfg.breaker_cooldown_s
        self._half_open = False
        self.stats = {"calls": 0, "denied": 0, "failures": 0, "breaker_trips": 0, "tokens_est": 0}

    # -- accounting --------------------------------------------------------
    def _trim(self, now: float) -> None:
        for dq, span in ((self._minute, 60), (self._hour, 3600), (self._day, 86400)):
            while dq and now - dq[0] >= span:
                dq.popleft()
        while self._tokens and now - self._tokens[0][0] >= 86400:
            self._tokens.popleft()

    def _deny(self, reason: str) -> None:
        self.stats["denied"] += 1
        telemetry.count("model_budget_denied:" + reason)
        raise ModelBudgetExceeded("model budget: " + reason)

    def acquire(self, est_tokens: int) -> float:
        """Reserve one call; returns its start time. Raises when refused."""
        if self.cfg.disabled:
            self._deny("disabled")
        if est_tokens > self.cfg.max_request_tokens:
            self._deny("request too large")
        now = time.time()
        with self._lock:
            if now < self._open_until:
                self._deny("circuit open")
            if self._half_open:
                # One trial call while half-open; others wait for its result.
                self._deny("circuit half-open")
            if self._open_until and now >= self._open_until:
                self._half_open = True
                self._open_until = 0.0
            self._trim(now)
            if len(self._minute) >= self.cfg.per_minute:
                self._half_open = False
                self._deny("per-minute limit")
            if len(self._hour) >= self.cfg.per_hour:
                self._half_open = False
                self._deny("per-hour limit")
            if len(self._day) >= self.cfg.per_day:
                self._half_open = False
                self._deny("per-day limit")
            used = sum(t for _, t in self._tokens)
            if used + est_tokens > self.cfg.tokens_per_day:
                self._half_open = False
                self._deny("daily token budget")
            for dq in (self._minute, self._hour, self._day):
                dq.append(now)
            self._tokens.append((now, est_tokens))
            self.stats["calls"] += 1
            self.stats["tokens_est"] += est_tokens
        if not self._slots.acquire(timeout=max(0.0, self.cfg.wait_s)):
            with self._lock:
                self._half_open = False
            self._deny("too many concurrent calls")
        return now

    def release(self, ok: bool, actual_tokens: int = 0, est_tokens: int = 0) -> None:
        self._slots.release()
        with self._lock:
            if actual_tokens and actual_tokens > est_tokens:
                self._tokens.append((time.time(), actual_tokens - est_tokens))
                self.stats["tokens_est"] += actual_tokens - est_tokens
            if ok:
                self._fails = 0
                self._half_open = False
                self._cooldown = self.cfg.breaker_cooldown_s
                return
            self.stats["failures"] += 1
            self._fails += 1
            if self._half_open or self._fails >= self.cfg.breaker_failures:
                self._open_until = time.time() + self._cooldown
                self._cooldown = min(self._cooldown * 2, self.cfg.breaker_max_cooldown_s)
                self._fails = 0
                self._half_open = False
                self.stats["breaker_trips"] += 1
                telemetry.count("model_breaker_open")

    def snapshot(self) -> dict:
        now = time.time()
        with self._lock:
            self._trim(now)
            return dict(self.stats, calls_last_minute=len(self._minute), calls_last_hour=len(self._hour),
                        calls_last_day=len(self._day), tokens_last_day=sum(t for _, t in self._tokens),
                        breaker_open=now < self._open_until, limits={
                            "per_minute": self.cfg.per_minute, "per_hour": self.cfg.per_hour,
                            "per_day": self.cfg.per_day, "tokens_per_day": self.cfg.tokens_per_day,
                            "concurrent": self.cfg.concurrent})


BUDGET = ModelBudget()


def estimate_tokens(kwargs: dict) -> int:
    """Prompt characters / 4 plus the requested completion size."""
    chars = 0
    for m in kwargs.get("messages") or []:
        content = m.get("content") if isinstance(m, dict) else getattr(m, "content", "")
        if isinstance(content, list):
            content = " ".join(str(part.get("text", "")) if isinstance(part, dict) else str(part) for part in content)
        chars += len(str(content or ""))
    return chars // 4 + int(kwargs.get("max_tokens") or kwargs.get("max_completion_tokens") or 512)


def _usage_tokens(resp) -> int:
    try:
        usage = resp.get("usage") if isinstance(resp, dict) else getattr(resp, "usage", None)
        return int(getattr(usage, "total_tokens", None) or (usage or {}).get("total_tokens", 0) or 0)
    except Exception:
        return 0


def install(budget: ModelBudget = BUDGET) -> bool:
    """Wrap litellm.completion and acompletion once. Idempotent."""
    import litellm

    if getattr(litellm.completion, "_civicmesh_budget", False):
        return True
    orig_sync = litellm.completion
    orig_async = litellm.acompletion

    def completion(*args, **kwargs):
        est = estimate_tokens(kwargs)
        budget.acquire(est)
        ok = False
        tokens = 0
        try:
            resp = orig_sync(*args, **kwargs)
            ok = True
            tokens = _usage_tokens(resp)
            return resp
        finally:
            budget.release(ok, tokens, est)

    async def acompletion(*args, **kwargs):
        est = estimate_tokens(kwargs)
        budget.acquire(est)
        ok = False
        tokens = 0
        try:
            resp = await orig_async(*args, **kwargs)
            ok = True
            tokens = _usage_tokens(resp)
            return resp
        finally:
            budget.release(ok, tokens, est)

    completion._civicmesh_budget = True
    acompletion._civicmesh_budget = True
    litellm.completion = completion
    litellm.acompletion = acompletion
    return True
