"""Check every program's link and phone number against the program's own page.

    python3 tools/check_contacts.py            # from civicmesh/; writes data/verification.json
    python3 tools/check_contacts.py --dry-run  # print only

For each program in data/resources.json this fetches `online_url` (and the
form URL when there is one) and records the HTTP status and whether the
listed phone number appears on the page. It records what was checked and
when, nothing more: a page that answers and shows the number is evidence the
contact is current, not a review of the eligibility rules. Rule checks are
recorded by hand in the same file ("rules"), with their source.

Many government sites refuse scripted requests (403 from a bot shield) or
render the number with JavaScript. Those come out as "unconfirmed", which
means a person has to look, not that the contact is wrong.
tests/check_verification.py fails CI when any record is older than a year.
"""

import datetime
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(HERE, "data", "resources.json")
OUT = os.path.join(HERE, "data", "verification.json")
ABOUT = ("What was checked for each program, and when. contact_*: written by tools/check_contacts.py "
         "(the program page answers 200 and shows the listed phone; 'unconfirmed' = a bot shield, a page that "
         "renders the number with JavaScript, or a real problem: a person must look). rules: written by hand "
         "when a program's eligibility rules were compared with an independent source; null = never checked. "
         "tests/check_verification.py fails when a record is over a year old.")
UA = "Mozilla/5.0 (X11; Linux x86_64) CivicMesh-contact-check/1.0 (+https://github.com/Anbu-00001/CivicMesh)"


def fetch(url):
    """(status, text) for a URL; status 0 when the request itself failed."""
    if not url:
        return None, ""
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html,*/*"})
    try:
        with urllib.request.urlopen(req, timeout=25, context=ssl.create_default_context()) as r:
            return r.status, r.read(2_000_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception as e:  # DNS, TLS, timeout
        return 0, type(e).__name__


def digits(s):
    return re.sub(r"\D", "", s or "")


def phone_on_page(phone, text):
    """Is the phone number on the page? Short codes (988, 211) count only as a whole word."""
    d = digits(phone)
    if not d or not text:
        return False
    if len(d) <= 3:
        return re.search(r"(?<!\d)" + d + r"(?!\d)", text) is not None
    page = digits(text)
    return d in page or (d.startswith("1") and d[1:] in page)


def main():
    dry = "--dry-run" in sys.argv
    today = datetime.date.today().isoformat()
    progs = json.load(open(CATALOG, encoding="utf-8"))["resources"]
    old = json.load(open(OUT, encoding="utf-8")) if os.path.exists(OUT) else {"programs": {}}
    out = {"_about": ABOUT, "programs": {}}
    for p in progs:
        rid = p["eligibility"]["rule_id"]
        status, text = fetch(p.get("online_url", ""))
        fstatus = None
        furl = p.get("form", {}).get("url", "")
        if furl and furl != p.get("online_url"):
            fstatus, _ = fetch(furl)
        found = phone_on_page(p.get("contact_phone", ""), text)
        # 2-1-1 is the national referral line, not the program's own number.
        own_phone = digits(p.get("contact_phone", "")) not in ["", "211"]
        ok = status == 200 and (found or not own_phone)
        rec = dict(old["programs"].get(rid, {}))
        rec.update({
            "program": p["agency_name"],
            "contact_checked": today,
            "contact_result": "confirmed" if ok else "unconfirmed",
            "url_status": status,
            "phone_on_page": found,
        })
        if fstatus is not None:
            rec["form_url_status"] = fstatus
        rec.setdefault("rules", {"checked": None, "how": "", "source": ""})
        out["programs"][rid] = rec
        print(f"{rid:<26} {str(status):>4} phone={'yes' if found else 'no ':<3} form={str(fstatus or '-'):>4}  {rec['contact_result']}")
    if not dry:
        with open(OUT, "w", encoding="utf-8") as f:
            json.dump(out, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print("wrote", os.path.relpath(OUT, HERE))


if __name__ == "__main__":
    main()
