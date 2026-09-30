"""Browser end-to-end checks: headless Chrome against the running app.

    pip install websocket-client
    python3 civicmesh/tests/browser_e2e.py http://localhost:7860

0. A message sent while the anonymous sign-in is still running waits for it
   and is answered. It used to go out without a token; the 401 made the
   client runtime reload the page and the message was lost.

Quick exit is the survivor-safety control (GOV.UK's "Exit this page"
pattern):

1. The button sends the tab to the neutral site, and the app is gone from the
   tab's history, so Back can't return to it.
2. Pressing Shift three times does the same.
3. In a private session (a crisis turn switches it on), Quick exit also
   erases the case on the server, and the next visit gets a new identity.
4. Inside a sandboxed frame like the huggingface.co Space page, which doesn't
   let the frame navigate the tab, the click opens the neutral site in a new
   tab and blanks the frame. The neutral site must not load in the frame,
   where it breaks: that was the bug.

The neutral site's page may not load on an offline runner, so the checks look
at where the browser was sent, not at the weather. Stdlib + websocket-client;
uses the Chrome that GitHub's ubuntu runners ship.
"""

import http.server
import json
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request

import websocket

PORT = 9334
EXIT_HOST = "weather.com"
# The attributes huggingface.co puts on a Space's iframe (read 2026-09-30).
HF_SANDBOX = ("allow-downloads allow-forms allow-modals allow-pointer-lock allow-popups "
              "allow-popups-to-escape-sandbox allow-same-origin allow-scripts allow-storage-access-by-user-activation")
DV_MESSAGE = "My partner hits me and I'm scared to go home tonight"
RESULTS = []


def check(name, cond, detail: object = ""):
    RESULTS.append(bool(cond))
    print(("  PASS " if cond else "  FAIL ") + name + ((" — " + str(detail)) if detail else ""))


def targets():
    return json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json", timeout=10))


def new_tab():
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/json/new?about:blank", method="PUT")
    return Tab(json.load(urllib.request.urlopen(req, timeout=10)))


class Tab:
    def __init__(self, target):
        self.id = target["id"]
        self.ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=60)
        self.seq = 0
        self.events = []

    def call(self, method, **params):
        self.seq += 1
        self.ws.send(json.dumps({"id": self.seq, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("id") == self.seq:
                return r.get("result", {})
            self.events.append(r)

    def js(self, expr, wait=False):
        r = self.call("Runtime.evaluate", expression=expr, awaitPromise=wait, returnByValue=True)
        return r.get("result", {}).get("value")

    def until(self, expr, timeout=45.0):
        end = time.time() + timeout
        while time.time() < end:
            try:
                if self.js(expr):
                    return True
            except Exception:
                pass
            time.sleep(0.4)
        return False

    def history(self):
        return [e["url"] for e in self.call("Page.getNavigationHistory").get("entries", [])]

    def current_url(self):
        h = self.call("Page.getNavigationHistory")
        return h["entries"][h["currentIndex"]]["url"] if h.get("entries") else ""

    def click_at(self, x, y):
        # A real mouse click, so the page gets user activation (window.open
        # needs it), unlike element.click().
        for kind in ("mousePressed", "mouseReleased"):
            self.call("Input.dispatchMouseEvent", type=kind, x=x, y=y, button="left", clickCount=1)

    def close(self):
        try:
            self.ws.close()
            urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/close/{self.id}", timeout=10)
        except Exception:
            pass


def center_of(tab, selector):
    # Wait for the chat's entrance animation to finish and the element to stop
    # moving, or the click lands where the button was a moment ago.
    tab.until("document.getAnimations().every(a => a.playState !== 'running')", 8.0)
    expr = f"""(()=>{{const e=document.querySelector({json.dumps(selector)}); if(!e) return null;
        e.scrollIntoView({{block:'center'}}); const r=e.getBoundingClientRect(); return [r.x+r.width/2, r.y+r.height/2]}})()"""
    last = None
    for _ in range(20):
        now = tab.js(expr)
        if now and now == last:
            return now
        last = now
        time.sleep(0.25)
    return last


def open_chat(tab, url):
    if url:
        tab.call("Page.enable")
        tab.call("Page.navigate", url=url)
    tab.until("!!document.querySelector('button')")
    tab.js("(()=>{const b=[...document.querySelectorAll('button,a')].find(e=>/Enter the Navigator/i.test(e.textContent)); b&&b.click()})()")
    return tab.until("!!document.querySelector('.cm-quick-exit') && !!document.querySelector('.cm-input')")


def send(tab, text):
    tab.js("""(()=>{const i=document.querySelector('.cm-input');const s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
           s.call(i,%s);i.dispatchEvent(new Event('input',{bubbles:true}));setTimeout(()=>document.querySelector('.cm-send').click(),200)})()""" % json.dumps(text))


def shift_three_times(tab):
    # Once the page navigates away, Chrome may never acknowledge the last key
    # event: don't wait long for it.
    tab.ws.settimeout(5)
    for _ in range(3):
        for kind in ("rawKeyDown", "keyUp"):
            try:
                tab.call("Input.dispatchKeyEvent", type=kind, key="Shift", code="ShiftLeft", windowsVirtualKeyCode=16,
                         modifiers=8 if kind == "rawKeyDown" else 0)
            except websocket.WebSocketTimeoutException:
                pass
        time.sleep(0.15)


def wait_for(fn, timeout=20.0):
    end = time.time() + timeout
    while time.time() < end:
        try:
            v = fn()
            if v:
                return v
        except Exception:
            pass
        time.sleep(0.4)
    return None


def left_for_exit(tab):
    return wait_for(lambda: EXIT_HOST in urllib.parse.urlsplit(tab.current_url()).netloc)


def post(app, path, body, tok=None):
    req = urllib.request.Request(app + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + tok} if tok else {})})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def parent_server(app):
    # Serve a stand-in for the Space page from the other loopback name, so the
    # app is a cross-site frame, as it is on huggingface.co.
    page = (f'<!doctype html><meta charset="utf-8"><title>Parent page</title><body style="margin:0">'
            f'<iframe src="{app}/" sandbox="{HF_SANDBOX}" style="width:1380px;height:860px;border:0"></iframe>').encode()

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(page)

        def log_message(self, format, *args):  # noqa: A002 — quiet
            pass

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    host = "127.0.0.1" if "localhost" in app else "localhost"
    return srv, f"http://{host}:{srv.server_address[1]}/"


def main(app: str) -> int:
    app = app.rstrip("/")
    chrome = shutil.which("google-chrome") or shutil.which("chromium") or shutil.which("chromium-browser")
    if not chrome:
        print("  FAIL no Chrome or Chromium on PATH")
        return 1
    proc = subprocess.Popen([chrome, "--headless=new", "--disable-gpu", "--no-sandbox", f"--remote-debugging-port={PORT}",
                             f"--remote-allow-origins=http://127.0.0.1:{PORT}", "--window-size=1400,900",
                             f"--user-data-dir={tempfile.mkdtemp()}", "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    srv = None
    try:
        if not wait_for(lambda: targets() is not None, 20):
            print("  FAIL Chrome's debugging port never answered")
            return 1

        # 0. The first message, sent while the sign-in is held back.
        tab = new_tab()
        tab.call("Page.enable")
        tab.call("Page.navigate", url=app)
        tab.until("!!document.querySelector('button')")
        tab.js("localStorage.clear(); sessionStorage.clear()")  # a first-time visitor
        tab.call("Fetch.enable", patterns=[{"urlPattern": "*/user/login*", "requestStage": "Request"}])
        tab.call("Page.reload")
        chat = open_chat(tab, None)
        rows = tab.js("document.querySelectorAll('.cm-thread .cm-row').length") or 0
        mark = len(tab.events)
        send(tab, "I need food for my kids tonight")
        # (events arrive while a command runs, hence the no-op evaluate)
        held = wait_for(lambda: tab.js("1") and [e for e in tab.events if e.get("method") == "Fetch.requestPaused"], 20)
        time.sleep(3)
        for e in held or []:
            tab.call("Fetch.continueRequest", requestId=e["params"]["requestId"])
        tab.call("Fetch.disable")
        answered = tab.until(f"document.querySelectorAll('.cm-thread .cm-row').length>={rows + 2} && !document.querySelector('.cm-typing')", 45)
        reloads = [e for e in tab.events[mark:] if e.get("method") == "Page.frameNavigated" and not e["params"]["frame"].get("parentId")]
        check("0a the sign-in was held while the message went out", chat and held)
        check("0b the page did not reload", not reloads, len(reloads))
        check("0c the message was answered once the sign-in finished", answered and "I need food" in (tab.js("document.querySelector('.cm-thread').textContent") or ""))
        tab.close()

        # 1. The button, in the app's own tab.
        tab = new_tab()
        if not open_chat(tab, app):
            check("the chat opened", False)
            return report()
        xy = center_of(tab, ".cm-quick-exit")
        tab.click_at(*xy)
        check("1a the button sends the tab to the neutral site", left_for_exit(tab), tab.current_url()[:80])
        hist = tab.history()
        check("1b the app is not in the tab's history (Back can't return)", not any(u.startswith(app) for u in hist), hist)
        tab.close()

        # 2. Shift three times.
        tab = new_tab()
        open_chat(tab, app)
        tab.call("Page.bringToFront")
        shift_three_times(tab)
        check("2 Shift pressed three times leaves too", left_for_exit(tab), tab.current_url()[:80])
        tab.close()

        # 3. A private session: a crisis turn switches it on.
        tab = new_tab()
        open_chat(tab, app)
        tab.call("Network.enable")
        send(tab, DV_MESSAGE)
        private = tab.until("!!document.querySelector('.cm-private-note') && sessionStorage.getItem('cm_private')==='1'", 45)
        check("3a a crisis turn switches the private session on", private)
        creds = tab.js("JSON.stringify([sessionStorage.getItem('cm_uid'), sessionStorage.getItem('cm_pw')])")
        uid, pw = json.loads(creds) if creds else (None, None)
        tok = post(app, "/user/login", {"identity": {"type": "username", "value": uid},
                                        "credential": {"type": "password", "password": pw}})["data"]["token"] if uid else None
        before = post(app, "/walker/GraphSnapshotWalker", {"user_id": uid}, tok)["data"]["reports"][-1] if tok else {}
        check("3b the case exists before the exit", before.get("counts", {}).get("PersonNode") == 1, before.get("counts"))
        tab.click_at(*center_of(tab, ".cm-quick-exit"))
        check("3c the private exit leaves", left_for_exit(tab), tab.current_url()[:80])
        sent = [e for e in tab.events if e.get("method") == "Network.requestWillBeSent"
                and e["params"]["request"]["url"].endswith("/walker/ForgetWalker")]
        check("3d it asked the server to erase the case", len(sent) == 1)

        def erased():
            after = post(app, "/walker/GraphSnapshotWalker", {"user_id": uid}, tok)["data"]["reports"][-1]
            return after.get("empty") is True and after.get("counts", {}).get("PersonNode") == 0
        check("3e the server erased the case", tok and wait_for(erased, 15))
        tab.close()
        tab = new_tab()
        open_chat(tab, app)
        fresh = tab.js("localStorage.getItem('cm_uid') || sessionStorage.getItem('cm_uid')")
        check("3f the next visit gets a new identity", fresh and fresh != uid)
        tab.close()

        # 4. Inside a sandboxed cross-site frame, like the huggingface.co page.
        srv, parent = parent_server(app)
        tab = new_tab()
        tab.call("Page.enable")
        tab.call("Page.navigate", url=parent)
        frame = wait_for(lambda: next((t for t in targets() if t["type"] == "iframe" and t["url"].startswith(app)), None), 30)
        if not frame:
            check("4 the app loaded in the frame", False)
            return report()
        inner = Tab(frame)
        if not open_chat_in_frame(inner):
            check("4 the chat opened in the frame", False)
            return report()
        x, y = center_of(inner, ".cm-quick-exit")
        before_pages = {t["id"] for t in targets() if t["type"] == "page"}
        tab.click_at(x, y)  # the frame is at the parent page's top left
        popup = wait_for(lambda: next((t for t in targets() if t["type"] == "page" and t["id"] not in before_pages
                                       and EXIT_HOST in t["url"]), None))
        check("4a the click opens the neutral site in a new tab", popup, [t["url"][:60] for t in targets() if t["type"] == "page"])
        def children():
            return [t["url"] for t in targets() if t["type"] == "iframe" and t.get("parentId") == tab.id]
        framed_exit = wait_for(lambda: any(EXIT_HOST in urllib.parse.urlsplit(u).netloc for u in children()), 3)
        check("4b the neutral site does not load inside the frame (it breaks there)", not framed_exit, children())
        check("4c the frame is blanked, so the conversation is off the screen",
              wait_for(lambda: children() == ["about:blank"], 10) and inner.js("document.body.innerHTML.length") == 0, children())
        tab.close()

        # 5. Shift three times in the frame: a key press can't open a tab,
        # so the frame is blanked and nothing else is tried.
        tab = new_tab()
        tab.call("Page.enable")
        tab.call("Page.navigate", url=parent)
        frame = wait_for(lambda: next((t for t in targets() if t["type"] == "iframe" and t.get("parentId") == tab.id
                                       and t["url"].startswith(app)), None), 30)
        inner = Tab(frame)
        open_chat_in_frame(inner)
        tab.click_at(*center_of(inner, ".cm-input"))  # focus the frame
        time.sleep(5.5)  # let the click's user activation lapse
        before_pages = {t["id"] for t in targets() if t["type"] == "page"}
        shift_three_times(tab)
        check("5a Shift three times in the frame blanks it", wait_for(lambda: children() == ["about:blank"], 10), children())
        time.sleep(1.0)
        check("5b and opens no tab", not [t for t in targets() if t["type"] == "page" and t["id"] not in before_pages])
        tab.close()
    finally:
        proc.terminate()
        if srv:
            srv.shutdown()
    return report()


def open_chat_in_frame(inner):
    inner.until("!!document.querySelector('button')")
    inner.js("(()=>{const b=[...document.querySelectorAll('button,a')].find(e=>/Enter the Navigator/i.test(e.textContent)); b&&b.click()})()")
    return inner.until("!!document.querySelector('.cm-quick-exit')")


def report():
    ok = all(RESULTS) and RESULTS
    print("  " + ("PASS" if ok else f"FAIL ({RESULTS.count(False)} of {len(RESULTS)})"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "http://localhost:7860"))
