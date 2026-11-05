"""In a real browser, with a fake model: its summary comes after the answer (blind audit F25).

    python3 civicmesh/tests/fake_llm.py 8799 0.3 &
    docker run ... (the model settings from tests/security_e2e.py) civicmesh:ci
    python3 civicmesh/tests/browser_model.py http://localhost:7862
"""

import shutil
import subprocess
import sys
import tempfile

import browser_e2e as b


def main(app: str) -> int:
    chrome = shutil.which("google-chrome") or shutil.which("chromium") or shutil.which("chromium-browser")
    if not chrome:
        print("  FAIL no Chrome or Chromium on PATH")
        return 1
    proc = subprocess.Popen([chrome, "--headless=new", "--disable-gpu", "--no-sandbox", f"--remote-debugging-port={b.PORT}",
                             f"--remote-allow-origins=http://127.0.0.1:{b.PORT}", "--window-size=1400,900",
                             f"--user-data-dir={tempfile.mkdtemp()}", "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if not b.wait_for(lambda: b.targets() is not None, 20):
            print("  FAIL Chrome's debugging port never answered")
            return 1
        tab = b.new_tab()
        tab.call("Page.enable")
        tab.call("Page.navigate", url=app.rstrip("/"))
        b.check("the app with a model opens", b.open_chat(tab, ""))
        b.send(tab, "I need food for my kids in Houston")
        b.check("a summary arrives", tab.until("!!document.querySelector('.cm-narration:not(.cm-narration-pending)')", 25.0))
        b.check("it is labelled as AI and can be wrong", "AI summary" in str(tab.js("document.querySelector('.cm-narration').innerText")))
        b.check("it sits below the answer and the programs", tab.js("""(()=>{const n=document.querySelector('.cm-narration');
            const a=[...document.querySelectorAll('.cm-result .cm-bubble')].pop();const c=document.querySelector('.cm-cards');
            return !!(a.compareDocumentPosition(n)&4)&&!!(c.compareDocumentPosition(n)&4)})()"""))
        tab.close()
    finally:
        proc.terminate()
    return b.report()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
