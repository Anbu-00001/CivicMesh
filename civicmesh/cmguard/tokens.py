"""Signed, short-lived, visitor-bound tokens for the expensive walkers.

IntakeWalker issues one token per optional model call (narration, the two
translation calls) over exactly the content that call may send to a model.
NarrateWalker and LocalizeWalker only run with a token that

  * carries a valid HMAC-SHA256 signature (key: CIVICMESH_SIGNING_KEY, else
    random per process, so tokens never outlive a restart),
  * is for this call kind and this visitor's graph root (a token lifted from
    another visitor is useless),
  * covers byte-for-byte the content being sent (no free relay),
  * hasn't expired (default 15 minutes), and
  * hasn't been used more than its allowance (narration once; a translation
    three times, for the "Try again" button).

Tokens are opaque to the client: base64url(JSON claims) "." hex signature.
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import time

from cmguard.limits import ExpiringSet

KEY = (os.environ.get("CIVICMESH_SIGNING_KEY", "").strip() or secrets.token_hex(32)).encode()
TTL_S = float(os.environ.get("CIVICMESH_TOKEN_TTL_S", "") or 900)
MAX_USES = {"narrate": 1, "loc_text": 3, "loc_strings": 3}
_USED = ExpiringSet(max_keys=200000)


def content_hash(*parts) -> str:
    """Stable hash of the content a token covers."""
    blob = json.dumps(parts, ensure_ascii=False, separators=(",", ":"), default=str)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def _sign(payload: bytes) -> str:
    return hmac.new(KEY, payload, hashlib.sha256).hexdigest()


def issue(kind: str, subject: str, digest: str, ttl_s: "float | None" = None, now: "float | None" = None) -> str:
    now = time.time() if now is None else now
    claims = {"k": kind, "s": str(subject), "h": digest, "e": round(now + (ttl_s or TTL_S), 1),
              "n": secrets.token_hex(12)}
    payload = base64.urlsafe_b64encode(json.dumps(claims, separators=(",", ":")).encode()).rstrip(b"=")
    return payload.decode() + "." + _sign(payload)


def verify(token: str, kind: str, subject: str, digest: str, now: "float | None" = None) -> str:
    """'' when valid (and counts one use), else the reason it was refused."""
    now = time.time() if now is None else now
    try:
        payload_s, sig = str(token).split(".", 1)
        payload = payload_s.encode()
        if not hmac.compare_digest(sig, _sign(payload)):
            return "bad signature"
        claims = json.loads(base64.urlsafe_b64decode(payload + b"=" * (-len(payload) % 4)))
    except Exception:
        return "malformed token"
    if claims.get("k") != kind:
        return "wrong token kind"
    if claims.get("s") != str(subject):
        return "token belongs to another visitor"
    if not hmac.compare_digest(str(claims.get("h", "")), digest):
        return "content does not match the token"
    expires = float(claims.get("e", 0))
    if now > expires:
        return "token expired"
    uses = _USED.bump(kind + ":" + str(claims.get("n", "")), expires, now)
    if uses > MAX_USES.get(kind, 1):
        return "token already used"
    return ""
