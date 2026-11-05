"""Delete visitors who haven't been back in a while (blind audit F26: no purge code).

A visitor is anonymous, so an old one can't be asked. After
CIVICMESH_RETENTION_DAYS without a write (default 30; 0 turns this off) their
graph and their login go. If they do come back, the app signs them in as a new
visitor, which is what a cleared browser does anyway.

    python -m cmguard.retention 30        (from civicmesh/, by hand)
"""

import datetime
import os
import sqlite3
import sys

DATA_DIR = os.path.join(".jac", "data")
KEEP = "cm-guest-"  # the gateway's service login holds nothing and must stay valid


def _hex(uuid_text: str) -> str:
    return str(uuid_text or "").replace("-", "")


def purge(days: float, data_dir: str = DATA_DIR, now=None) -> dict:
    """Removes every visitor idle for `days`. Returns what it removed."""
    out = {"visitors": 0, "records": 0}
    anchors_path = os.path.join(data_dir, "anchor_store.db")
    users_path = os.path.join(data_dir, "users.db")
    if days <= 0 or not (os.path.exists(anchors_path) and os.path.exists(users_path)):
        return out
    now = now or datetime.datetime.now(datetime.timezone.utc)
    cutoff = (now - datetime.timedelta(days=days)).isoformat()
    anchors = sqlite3.connect(anchors_path, timeout=30.0)
    users = sqlite3.connect(users_path, timeout=30.0)
    try:
        last = {}
        for owner, stamp in anchors.execute(
            "select coalesce(json_extract(data, '$.root'), id), max(updated_at) from anchors group by 1"
        ):
            last[_hex(owner)] = str(stamp or "")
        rows = users.execute("select user_id, root_id, identities, role, created_at from identity_users").fetchall()
        for user_id, root_id, identities, role, created in rows:
            if KEEP in str(identities) or str(role or "").lower() in ("admin", "system"):
                continue
            seen = max(last.get(_hex(root_id), ""), str(created or ""))
            if not seen or seen >= cutoff:
                continue
            ids = [r[0] for r in anchors.execute(
                "select id from anchors where id = ? or json_extract(data, '$.root') = ?",
                (_uuid(root_id), _uuid(root_id)))]
            anchors.executemany("delete from anchors where id = ?", [(i,) for i in ids])
            anchors.commit()
            users.execute("delete from identity_lookups where user_id = ?", (user_id,))
            users.execute("delete from sso_lookups where user_id = ?", (user_id,))
            users.execute("delete from identity_users where user_id = ?", (user_id,))
            users.commit()
            out["visitors"] += 1
            out["records"] += len(ids)
    finally:
        anchors.close()
        users.close()
    return out


def _uuid(root_id: str) -> str:
    h = _hex(root_id)
    return "-".join((h[:8], h[8:12], h[12:16], h[16:20], h[20:])) if len(h) == 32 else str(root_id)


def days_from_env() -> float:
    try:
        return float(os.environ.get("CIVICMESH_RETENTION_DAYS", "") or 30)
    except ValueError:
        return 30.0


if __name__ == "__main__":
    print(purge(float(sys.argv[1]) if len(sys.argv) > 1 else days_from_env()))
