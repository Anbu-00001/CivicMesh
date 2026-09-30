"""The caller's address, as the proxy in front of us saw it.

Hugging Face Spaces sit behind an AWS load balancer that appends the address
it received the connection from to X-Forwarded-For. A client can put anything
in the header, so the left entries are attacker-controlled; only the entries
the trusted proxies appended (the rightmost `hops`) are real. Verified on a
public Space: a request sent with "X-Forwarded-For: 203.0.113.77" arrived as
"203.0.113.77, <real address>"; X-Real-IP and Forwarded were stripped.

The header is only honored when the direct peer is a private or loopback
address (the proxy). A request that reaches the container from a public
address is keyed by that address, whatever it claims.
"""

import ipaddress


def _parse(value: str):
    try:
        return ipaddress.ip_address(value.strip().strip("[]"))
    except ValueError:
        return None


def is_private(value: str) -> bool:
    ip = _parse(value)
    return bool(ip and (ip.is_private or ip.is_loopback or ip.is_link_local))


def client_ip(peer: str, forwarded_for: str, hops: int) -> str:
    """Address to key per-client limits on."""
    peer = (peer or "").strip() or "unknown"
    if hops <= 0 or not forwarded_for or not is_private(peer):
        return peer
    parts = [p.strip() for p in forwarded_for.split(",") if p.strip()]
    if len(parts) < hops:
        return peer
    candidate = _parse(parts[-hops])
    if candidate is None:
        return peer
    return str(candidate)
