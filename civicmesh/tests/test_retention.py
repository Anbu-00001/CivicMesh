"""cmguard/retention.py against temporary databases shaped like the real ones.

    python3 tests/test_retention.py      (from civicmesh/)
"""

import datetime
import json
import os
import sqlite3
import sys
import tempfile

sys.path.insert(0, os.getcwd())
from cmguard.retention import purge  # noqa: E402

NOW = datetime.datetime(2026, 11, 5, tzinfo=datetime.timezone.utc)


def stamp(days_ago):
    return (NOW - datetime.timedelta(days=days_ago)).isoformat()


def uuid(n):
    return "%08x-0000-0000-0000-000000000000" % n


with tempfile.TemporaryDirectory() as d:
    a = sqlite3.connect(os.path.join(d, "anchor_store.db"))
    a.execute("create table anchors (id text primary key, type text, arch_type text, data text, updated_at text)")
    u = sqlite3.connect(os.path.join(d, "users.db"))
    u.execute("create table identity_users (user_id text primary key, root_id text, identities text, role text, created_at text)")
    u.execute("create table identity_lookups (value_normalized text primary key, user_id text)")
    u.execute("create table sso_lookups (provider text, external_id text, user_id text)")

    def visitor(n, name, role, active_days_ago):
        root = uuid(n)
        a.execute("insert into anchors values (?,?,?,?,?)", (root, "NodeAnchor", "Root", json.dumps({"root": None}), stamp(90)))
        for i in range(3):
            a.execute("insert into anchors values (?,?,?,?,?)", (uuid(n * 100 + i), "NodeAnchor", "NeedNode", json.dumps({"root": root}), stamp(active_days_ago)))
        u.execute("insert into identity_users values (?,?,?,?,?)", (name, root.replace("-", ""), json.dumps([{"value": name}]), role, stamp(90)))
        u.execute("insert into identity_lookups values (?,?)", (name, name))

    visitor(1, "old", "user", 45)
    visitor(2, "recent", "user", 3)
    visitor(3, "cm-guest-abc", "user", 400)
    visitor(4, "boss", "admin", 400)
    a.commit()
    u.commit()
    a.close()
    u.close()

    done = purge(30, d, NOW)
    a = sqlite3.connect(os.path.join(d, "anchor_store.db"))
    u = sqlite3.connect(os.path.join(d, "users.db"))
    names = sorted(r[0] for r in u.execute("select user_id from identity_users"))
    results = [
        ("the idle visitor and nothing else is removed", done == {"visitors": 1, "records": 4}),
        ("the others keep their logins", names == ["boss", "cm-guest-abc", "recent"]),
        ("no record of the idle visitor is left", a.execute("select count(*) from anchors where id like '00000001-%' or data like '%00000001-%'").fetchone()[0] == 0),
        ("the others keep their records", a.execute("select count(*) from anchors").fetchone()[0] == 12),
        ("no lookup is left", u.execute("select count(*) from identity_lookups where user_id = 'old'").fetchone()[0] == 0),
        ("0 days means off", purge(0, d, NOW) == {"visitors": 0, "records": 0}),
        ("no database, no error", purge(30, os.path.join(d, "missing"), NOW) == {"visitors": 0, "records": 0}),
    ]
    a.close()
    u.close()

for name, ok in results:
    print(("  PASS " if ok else "  FAIL ") + name)
sys.exit(0 if all(ok for _, ok in results) else 1)
