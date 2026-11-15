"""Numbers in the README that drifted from the code before (blind audit, section 8)."""
import glob
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
read = open(os.path.join(ROOT, "README.md"), encoding="utf-8").read()
langs = len(glob.glob(os.path.join(ROOT, "civicmesh", "data", "i18n", "*.json")))
progs = len(json.load(open(os.path.join(ROOT, "civicmesh", "data", "resources.json"), encoding="utf-8"))["resources"])
fails = []
MENU = 111
for n in set(re.findall(r"\b(\d+) menu languages without a catalog\b", read)):
    if int(n) != MENU - langs:
        fails.append(f"README says {n} menu languages have no catalog; there are {MENU - langs}")
for n in set(re.findall(r"\b(\d+) (?:machine-drafted )?languages\b", read)) - {"75", "111"}:
    if int(n) != langs:
        fails.append(f"README says {n} languages; there are {langs} catalogs")
for n in set(re.findall(r"\b(\d+) (?:national |federal |federal and national )?(?:programs|services)\b", read)):
    if int(n) != progs:
        fails.append(f"README says {n} programs; the catalog has {progs}")
print(f"docs: {langs} catalogs, {progs} programs")
for f in fails:
    print("  FAIL " + f)
print("  " + ("PASS" if not fails else f"FAIL ({len(fails)})"))
sys.exit(1 if fails else 0)
