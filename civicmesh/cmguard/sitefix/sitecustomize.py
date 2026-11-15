"""Wait for a busy database instead of failing at once.

jaclang opens SQLite with the default 5 second wait, and under write load the
blind audit saw "database is locked": a Delete my data call failed and left the
visitor's income in the database (F26). jaclang has no setting for this, and the
connection opens before the app's code runs, so cmguard/serve.py puts this file
on the child process's path.
"""

import sqlite3

_connect = sqlite3.connect


def connect(*args, **kwargs):
    if len(args) < 2:
        kwargs.setdefault("timeout", 30.0)
    return _connect(*args, **kwargs)


sqlite3.connect = connect
