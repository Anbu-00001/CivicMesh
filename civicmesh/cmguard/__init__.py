"""CivicMesh abuse protection.

The public Space is hostile Internet-facing infrastructure. These modules keep
the deterministic answer available while bounding what any one client, or
all clients together, can make the server (and the model provider) do:

  config     every threshold, from the environment, with conservative defaults
  clientip   the caller's address behind Hugging Face's proxy, not spoofable
  limits     bounded token buckets and in-flight counters
  tokens     short-lived, user-bound, replay-limited signed tokens for the
             expensive walkers (narration, translation)
  budget     a process-wide model budget and circuit breaker around every
             litellm call, so retries, fallbacks and parallel segments all count
  redact     keeps credentials out of anything returned or logged
  telemetry  aggregate counters only: no addresses, ids or message text
  gateway    the ASGI front door (allowlist, size caps, rate limits,
             concurrency, duplicate collapse) in front of jac-scale
  serve      the container entry point: secrets, the jac-scale child, uvicorn

Plain Python on purpose: framework-independent, unit-tested without Jac
(tests/test_cmguard.py), and unaffected by a future jac-scale upgrade.
"""
