"""Keep credentials out of anything the server returns or logs.

Model-provider errors can echo request details. Every error string that
leaves the server passes through `redact`, which removes the values of the
secret environment variables and anything shaped like a provider key or a
bearer token.
"""

import os
import re

SECRET_ENV = [
    "NVIDIA_API_KEY", "NVIDIA_NIM_API_KEY", "NIM_API_KEY", "GROQ_API_KEY", "FEATHERLESS_API_KEY",
    "OPENAI_API_KEY", "HF_TOKEN", "HUGGING_FACE_HUB_TOKEN", "CIVICMESH_JWT_SECRET",
    "CIVICMESH_SIGNING_KEY", "SYSTEM_USER_PASSWORD",
]
PATTERNS = [
    re.compile(r"nvapi-[A-Za-z0-9_\-]{8,}"),
    re.compile(r"gsk_[A-Za-z0-9]{8,}"),
    re.compile(r"\bsk-[A-Za-z0-9_\-]{8,}"),
    re.compile(r"\bhf_[A-Za-z0-9]{8,}"),
    re.compile(r"(?i)bearer\s+[A-Za-z0-9._\-]{8,}"),
    re.compile(r"(?i)(api[_-]?key|authorization|token)(['\"]?\s*[:=]\s*['\"]?)[^\s'\",}]{6,}"),
]


def redact(text) -> str:
    out = str(text)
    for name in SECRET_ENV:
        value = os.environ.get(name, "")
        if len(value) >= 8:
            out = out.replace(value, "[redacted]")
    for pat in PATTERNS:
        out = pat.sub(lambda m: (m.group(1) + m.group(2) + "[redacted]") if m.lastindex and m.lastindex >= 2 else "[redacted]", out)
    return out


def safe_error(ex: BaseException, limit: int = 160) -> str:
    """Short, redacted description of an exception for a response body."""
    return redact(type(ex).__name__ + ": " + str(ex))[:limit]
