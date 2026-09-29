"""Accessibility check on the running app: axe-core in headless Chrome.

    pip install websocket-client
    python3 civicmesh/tests/a11y_axe.py http://localhost:7860

Opens the chat, runs axe-core (pinned version, from jsDelivr), sends one
message, waits for the answer, and runs it again. Fails on any "serious" or
"critical" violation, if the transcript isn't a live region (so a screen
reader wouldn't announce replies), or if keyboard focus doesn't return to
the message box after the answer. Stdlib + websocket-client; uses the Chrome
that GitHub's ubuntu runners ship.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

import websocket

AXE_URL = "https://cdn.jsdelivr.net/npm/axe-core@4.10.2/axe.min.js"
PORT = 9333


def main(url: str) -> int:
    axe = urllib.request.urlopen(AXE_URL, timeout=60).read().decode("utf-8")
    chrome = shutil.which("google-chrome") or shutil.which("chromium") or shutil.which("chromium-browser")
    if not chrome:
        print("  FAIL no Chrome or Chromium on PATH")
        return 1
    profile = tempfile.mkdtemp()
    proc = subprocess.Popen([chrome, "--headless=new", "--disable-gpu", "--no-sandbox", f"--remote-debugging-port={PORT}",
                             f"--remote-allow-origins=http://127.0.0.1:{PORT}", "--window-size=1400,900",
                             f"--user-data-dir={profile}", "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    fails = []
    tabs = []
    try:
        for _ in range(100):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json"))
                break
            except Exception:
                time.sleep(0.2)
        ws = websocket.create_connection([t for t in tabs if t["type"] == "page"][0]["webSocketDebuggerUrl"])
        seq = [0]

        def js(expr, wait=False):
            seq[0] += 1
            ws.send(json.dumps({"id": seq[0], "method": "Runtime.evaluate",
                                "params": {"expression": expr, "awaitPromise": wait, "returnByValue": True}}))
            while True:
                r = json.loads(ws.recv())
                if r.get("id") == seq[0]:
                    return r.get("result", {}).get("result", {}).get("value")

        def until(expr, timeout=45.0):
            end = time.time() + timeout
            while time.time() < end:
                if js(expr):
                    return True
                time.sleep(0.5)
            return False

        def audit(label):
            # Measure the settled page: an element caught mid-fade reads as
            # low contrast.
            until("document.getAnimations().every(a => a.playState !== 'running')", 8.0)
            time.sleep(0.3)
            js(axe)
            out = json.loads(js("axe.run(document,{resultTypes:['violations']}).then(r=>JSON.stringify(r.violations.map(v=>({id:v.id,impact:v.impact,n:v.nodes.length}))))", True))
            bad = [v for v in out if v["impact"] in ("serious", "critical")]
            print(f"  {label}: {len(out)} violations, {len(bad)} serious or critical")
            for v in out:
                print(f"    {v['impact']:<9} {v['id']} ({v['n']})")
            for v in bad:
                fails.append(f"{label}: {v['impact']} {v['id']}")

        seq[0] += 1
        ws.send(json.dumps({"id": seq[0], "method": "Page.navigate", "params": {"url": url}}))
        until("!!document.querySelector('button')")
        js("(()=>{const b=[...document.querySelectorAll('button,a')].find(e=>/Enter the Navigator/i.test(e.textContent)); b&&b.click()})()")
        if not until("!!document.querySelector('.cm-input')"):
            fails.append("chat never appeared")
            return report(fails)
        audit("empty chat")
        if not js("(document.querySelector('.cm-thread')||{}).getAttribute&&document.querySelector('.cm-thread').getAttribute('aria-live')==='polite'"):
            fails.append("the transcript is not a polite live region")
        before = js("document.querySelectorAll('.cm-thread .cm-row').length")
        js("""(()=>{const i=document.querySelector('.cm-input');const s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
               s.call(i,"I'm 72, on $1200/month Social Security, my landlord is trying to evict me illegally. I live in Illinois.");
               i.dispatchEvent(new Event('input',{bubbles:true}));i.focus();setTimeout(()=>document.querySelector('.cm-send').click(),200)})()""")
        if not until(f"document.querySelectorAll('.cm-thread .cm-row').length>={before + 2} && !document.querySelector('.cm-typing')"):
            fails.append("no answer within 45 s")
            return report(fails)
        time.sleep(1.0)
        if not js("document.activeElement===document.querySelector('.cm-input')"):
            fails.append("focus did not return to the message box after the answer")
        audit("after an answer")
    finally:
        proc.terminate()
    return report(fails)


def report(fails):
    for f in fails:
        print("  FAIL " + f)
    print("  " + ("PASS" if not fails else f"FAIL ({len(fails)})"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "http://localhost:7860"))
