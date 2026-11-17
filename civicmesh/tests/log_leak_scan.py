"""Do the server logs hold any of the words the tests typed? (audit list J3)

The old scan grepped five fixed strings. This one reads every message the HTTP
and browser end-to-end tests send (string literals of four words or more,
except check names and docstrings) and fails if any run of five words from one
of them appears in the logs, ignoring case and spacing.

    docker logs cm 2>&1 | python3 civicmesh/tests/log_leak_scan.py
"""

import ast
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCES = ["e2e_http.py", "browser_e2e.py"]
N = 5


def words(s: str) -> list:
    return re.findall(r"[^\W_]+(?:'[^\W_]+)?", s.lower())


def sent_messages() -> list:
    out = []
    for name in SOURCES:
        tree = ast.parse(open(os.path.join(HERE, name), encoding="utf-8").read())
        skip = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and getattr(node.func, "id", "") == "check" and node.args:
                skip.add(id(node.args[0]))
            if isinstance(node, (ast.Module, ast.FunctionDef)) and node.body and isinstance(node.body[0], ast.Expr) and isinstance(getattr(node.body[0], "value", None), ast.Constant):
                skip.add(id(node.body[0].value))
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in skip:
                if len(words(node.value)) >= 4 and not node.value.startswith(("http", "/", "!!", "document.", "localStorage", "sessionStorage")):
                    out.append(node.value)
    return out


def shingles(ws: list) -> set:
    return {" ".join(ws[i:i + N]) for i in range(len(ws) - N + 1)}


def main() -> int:
    msgs = sent_messages()
    want = {}
    for m in msgs:
        for sh in shingles(words(m)):
            if any(len(w) >= 4 for w in sh.split()):
                want.setdefault(sh, m)
    log_text = " ".join(words(sys.stdin.read()))
    leaks = sorted({want[sh] for sh in want if sh in log_text})
    for m in leaks[:20]:
        print("  LEAK " + m[:100])
    print(f"log leak scan: {len(msgs)} test messages, {len(want)} five-word runs, {len(leaks)} found in the logs")
    return 1 if leaks else 0


if __name__ == "__main__":
    sys.exit(main())
