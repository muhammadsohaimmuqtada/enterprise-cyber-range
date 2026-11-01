"""Acme Intranet Portal - SIMULATED lab target for the enterprise-cyber-range.

A deliberately small Flask app playing the role of the video's public-facing
web server in the DMZ. With WEAK_AUTH=1 it also mounts the two simulated
weaknesses used by scenario phases 2-7:

  * POST /login accepts the string  admin' OR 1=1--  as a password - a visual
    stand-in for a SQL-injection authentication bypass.
  * GET/POST /console?token=DEV-2026 renders a form that executes shell
    commands (a simulated developer backdoor web shell).

Everything is confined to this container. The credentials in
/srv/notes/deployment.txt are fake and clearly marked as simulated.
"""
import logging
import os
import subprocess
from logging.handlers import RotatingFileHandler

from flask import (Flask, abort, redirect, render_template_string, request,
                   session, url_for)

WEAK_AUTH = os.environ.get("WEAK_AUTH", "0") == "1"
CONSOLE_TOKEN = "DEV-2026"
BYPASS_PASSWORD = "admin' OR 1=1--"

USERS = {
    "jsmith": "Summer2026!",
    "mchen": "Welcome123!",
    "admin": "Adm1n-P0rtal!",
}

# ---------------------------------------------------------------------------
# Logging: every request (including bypass attempts and console commands) is
# written to /var/log/app/access.log AND stdout. The stdout copy is captured
# by the container json-file driver, which is why log tampering in phase 7
# does not erase what the blue team can still read.
# ---------------------------------------------------------------------------
os.makedirs("/var/log/app", exist_ok=True)
log = logging.getLogger("portal")
log.setLevel(logging.INFO)
_fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
_stream = logging.StreamHandler()
_stream.setFormatter(_fmt)
_file = RotatingFileHandler("/var/log/app/access.log",
                            maxBytes=5_000_000, backupCount=3)
_file.setFormatter(_fmt)
log.addHandler(_stream)
log.addHandler(_file)

app = Flask(__name__)
app.secret_key = os.environ.get("PORTAL_SECRET", "lab-only-secret-not-real")


def client_ip():
    return (request.headers.get("X-Real-IP")
            or request.headers.get("X-Forwarded-For")
            or request.remote_addr or "-")


LOGIN_HTML = """<!doctype html>
<html><head><title>Acme Intranet Portal - Sign in</title></head>
<body style="font-family:sans-serif;max-width:420px;margin:60px auto">
  <h1>Acme Intranet Portal</h1>
  <p>SIMULATED enterprise portal - authorized lab only.</p>
  <form method="post" action="/login">
    <p><input name="username" placeholder="username" style="width:100%"></p>
    <p><input name="password" type="password" placeholder="password" style="width:100%"></p>
    <p><button type="submit">Sign in</button></p>
  </form>
</body></html>"""

DASHBOARD_HTML = """<!doctype html>
<html><head><title>Acme Intranet - Dashboard</title></head>
<body style="font-family:sans-serif;max-width:640px;margin:60px auto">
  <h1>Acme Intranet - Dashboard</h1>
  <p>Signed in as <strong>{{ user }}</strong>.</p>
  <ul>
    <li>Announcements: Q3 close is done (SIMULATED)</li>
    <li>Helpdesk: extension 4100 (SIMULATED)</li>
    {% if is_admin %}<li><a href="/admin">Admin panel</a></li>{% endif %}
  </ul>
</body></html>"""

ADMIN_HTML = """<!doctype html>
<html><head><title>Acme Intranet - Admin</title></head>
<body style="font-family:sans-serif;max-width:640px;margin:60px auto">
  <h1>Acme admin panel</h1>
  <p style="color:#a00">SIMULATED VULNERABILITY - LAB ONLY: this page is
  reachable by anyone holding an admin session, including sessions created by
  the simulated login bypass.</p>
  <h2>Domain users (SIMULATED)</h2>
  <ul><li>jsmith</li><li>mchen</li></ul>
</body></html>"""

CONSOLE_HTML = """<!doctype html>
<html><head><title>Acme Intranet - Developer console</title></head>
<body style="font-family:sans-serif;max-width:720px;margin:60px auto">
  <h1>Developer console</h1>
  <p style="color:#b00"><strong>SIMULATED VULNERABILITY - LAB ONLY.</strong>
  This endpoint is a staged web shell for the red-team scenario. It is not
  part of the real portal and only exists while WEAK_AUTH=1.</p>
  <form method="post" action="/console?token={{ token }}">
    <input name="cmd" placeholder="shell command" size="60">
    <button type="submit">run</button>
  </form>
  {% if output is not none %}<pre>{{ output }}</pre>{% endif %}
</body></html>"""


@app.after_request
def _log_request(resp):
    log.info("REQUEST ip=%s method=%s path=%s status=%s user=%s",
             client_ip(), request.method, request.path, resp.status_code,
             session.get("user", "-"))
    return resp


@app.route("/")
def index():
    if session.get("user"):
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "GET":
        return render_template_string(LOGIN_HTML)

    username = request.form.get("username", "")
    password = request.form.get("password", "")

    if WEAK_AUTH and password == BYPASS_PASSWORD:
        # Simulated SQL-injection authentication bypass. The marker string
        # AUTH-BYPASS is what the SIEM rule 100910 keys on.
        log.info("AUTH-BYPASS ip=%s user=admin (password matched simulated SQLi string)",
                 client_ip())
        session["user"] = "admin"
        session["is_admin"] = True
        return redirect(url_for("dashboard"))

    if username in USERS and USERS[username] == password:
        log.info("AUTH-OK ip=%s user=%s", client_ip(), username)
        session["user"] = username
        session["is_admin"] = (username == "admin")
        return redirect(url_for("dashboard"))

    log.info("AUTH-FAIL ip=%s user=%s", client_ip(), username)
    return render_template_string(LOGIN_HTML), 401


@app.route("/dashboard")
def dashboard():
    if not session.get("user"):
        return redirect(url_for("login"))
    return render_template_string(DASHBOARD_HTML, user=session["user"],
                                  is_admin=session.get("is_admin", False))


@app.route("/admin")
def admin():
    if not session.get("user") or not session.get("is_admin"):
        abort(403)
    return render_template_string(ADMIN_HTML)


@app.route("/console", methods=["GET", "POST"])
def console():
    if not WEAK_AUTH:
        abort(404)
    if request.args.get("token", "") != CONSOLE_TOKEN:
        log.info("CONSOLE-DENY ip=%s token=%r", client_ip(),
                 request.args.get("token", ""))
        abort(404)

    output = None
    if request.method == "POST":
        cmd = request.form.get("cmd", "")
        # Marker CONSOLE-EXEC is what the SIEM rule 100911 keys on.
        log.info("CONSOLE-EXEC ip=%s user=%s cmd=%s",
                 client_ip(), session.get("user", "-"), cmd)
        try:
            proc = subprocess.run(cmd, shell=True, capture_output=True,
                                  text=True, timeout=15)
            output = (proc.stdout or "") + (proc.stderr or "")
        except subprocess.TimeoutExpired:
            output = "[command timed out after 15s]"

    return render_template_string(CONSOLE_HTML, token=CONSOLE_TOKEN,
                                  output=output)


@app.route("/health")
def health():
    return "ok\n", 200


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000)
