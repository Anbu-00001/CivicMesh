"""Say at boot when the data files are broken.

The app keeps running without them, because the crisis lines don't depend on
them, so nothing else would tell an operator (blind audit, 2026-11: with
data/resources.json gone it booted healthy and every visitor got "no direct
match").
"""

import glob
import json
import os


def data_problems(root: str = ".") -> list:
    problems = []
    path = os.path.join(root, "data", "resources.json")
    try:
        with open(path, encoding="utf-8") as f:
            if not json.load(f).get("resources"):
                problems.append(path + " lists no programs")
    except Exception as ex:
        problems.append(path + " can't be read (" + type(ex).__name__ + ")")
    catalogs = glob.glob(os.path.join(root, "data", "i18n", "*.json"))
    if not catalogs:
        problems.append(os.path.join(root, "data", "i18n") + " has no message catalogs")
    for catalog in sorted(catalogs):
        try:
            with open(catalog, encoding="utf-8") as f:
                if not json.load(f):
                    problems.append(catalog + " is empty")
        except Exception as ex:
            problems.append(catalog + " can't be read (" + type(ex).__name__ + ")")
    return problems
