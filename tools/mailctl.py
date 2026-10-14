#!/usr/bin/env python3
"""mailctl — read mail from a named account, configured per account, never hardcoded.

Why this exists: the HackerOne email alias (``<handle>@wearehackerone.com``) only
RECEIVES — it forwards to whatever address registered the HackerOne account. To
close a registration/verification loop on an authorized target we must be able to
READ that mailbox. The barbarossa ``mail.read`` capability is bound to a single
account (the configured one), so this tool adds named accounts without touching the
worker or the deploy path.

Credentials live OUTSIDE the repository, one file per account::

    /opt/data/credentials/mail-<account>.env     (mode 600)
        MAIL_USER=<account>@<domain>
        MAIL_APP_PASSWORD=xxxxxxxxxxxxxxxx        # Gmail app password, not the account password
        MAIL_HOST=imap.gmail.com                  # optional
        MAIL_PORT=993                             # optional

Usage::

    mailctl.py accounts
    mailctl.py read   --account h1 [--limit 10] [--mailbox INBOX] [--query ALL]
    mailctl.py search --account h1 [--from X] [--subject Y] [--since 2026-09-01]
    mailctl.py wait   --account h1 --subject "verify" --timeout 300

Output is JSON on stdout. The password is never printed, logged or echoed.
"""

from __future__ import annotations

import argparse
import email
import email.utils
import imaplib
import json
import os
import re
import sys
import time
from email.header import decode_header

CRED_DIR = os.environ.get("MAIL_CRED_DIR", "/opt/data/credentials")
DEFAULT_HOST = os.environ.get("MAIL_HOST", "imap.gmail.com")
DEFAULT_PORT = int(os.environ.get("MAIL_PORT", "993"))
BODY_LIMIT = int(os.environ.get("MAIL_BODY_LIMIT", "6000"))

# An account name becomes part of a filename — keep it strictly boring.
ACCOUNT_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,30}$")


def redact(text: str) -> str:
    """Never let a credential-shaped string reach stdout."""
    text = re.sub(
        r"(?i)(password|passwd|app[_-]?password|token|secret|api[_-]?key)"
        r"(\s*[:=]\s*)\S+",
        r"\1\2<redacted>",
        str(text or ""),
    )
    return text


def cred_path(account: str) -> str:
    if not ACCOUNT_RE.match(account):
        raise SystemExit(
            "invalid account name %r: use lowercase letters, digits, _ or -" % account
        )
    return os.path.join(CRED_DIR, "mail-%s.env" % account)


def load_account(account: str) -> dict:
    path = cred_path(account)
    if not os.path.isfile(path):
        raise SystemExit(
            "no credentials for account %r — expected %s (mode 600)" % (account, path)
        )
    mode = os.stat(path).st_mode & 0o777
    if mode & 0o077:
        print(
            "warning: %s is mode %o — tighten it to 600" % (path, mode),
            file=sys.stderr,
        )
    cfg: dict = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            cfg[key.strip().upper()] = val.strip().strip("'\"")
    user = cfg.get("MAIL_USER")
    password = cfg.get("MAIL_APP_PASSWORD") or cfg.get("MAIL_PASSWORD")
    if not user or not password:
        raise SystemExit(
            "account %r is missing MAIL_USER and/or MAIL_APP_PASSWORD in %s"
            % (account, path)
        )
    return {
        "user": user,
        "password": password,
        "host": cfg.get("MAIL_HOST", DEFAULT_HOST),
        "port": int(cfg.get("MAIL_PORT", DEFAULT_PORT)),
    }


def decode(value: str | None) -> str:
    if not value:
        return ""
    parts = []
    for chunk, charset in decode_header(value):
        if isinstance(chunk, bytes):
            try:
                parts.append(chunk.decode(charset or "utf-8", errors="replace"))
            except (LookupError, TypeError):
                parts.append(chunk.decode("utf-8", errors="replace"))
        else:
            parts.append(chunk)
    return "".join(parts)


def body_of(msg: email.message.Message) -> str:
    """Plain-text body, or a crude tag-stripped HTML fallback."""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain" and not part.get_filename():
                try:
                    return part.get_payload(decode=True).decode(
                        part.get_content_charset() or "utf-8", errors="replace"
                    )
                except Exception:
                    continue
        for part in msg.walk():
            if part.get_content_type() == "text/html" and not part.get_filename():
                try:
                    html = part.get_payload(decode=True).decode(
                        part.get_content_charset() or "utf-8", errors="replace"
                    )
                    return re.sub(r"<[^>]+>", " ", re.sub(r"(?is)<(script|style).*?</\1>", " ", html))
                except Exception:
                    continue
        return ""
    try:
        return msg.get_payload(decode=True).decode(
            msg.get_content_charset() or "utf-8", errors="replace"
        )
    except Exception:
        return str(msg.get_payload())


def connect(cfg: dict) -> imaplib.IMAP4_SSL:
    conn = imaplib.IMAP4_SSL(cfg["host"], cfg["port"], timeout=45)
    conn.login(cfg["user"], cfg["password"])
    return conn


def fetch(conn: imaplib.IMAP4_SSL, mailbox: str, query: str, limit: int) -> list[dict]:
    conn.select(mailbox, readonly=True)
    typ, data = conn.search(None, query)
    if typ != "OK":
        return []
    uids = (data[0] or b"").split()
    out = []
    for uid in reversed(uids[-limit:]):
        typ, raw = conn.fetch(uid, "(RFC822)")
        if typ != "OK" or not raw or not isinstance(raw[0], tuple):
            continue
        msg = email.message_from_bytes(raw[0][1])
        out.append(
            {
                "uid": uid.decode(),
                "from": decode(msg.get("From")),
                "to": decode(msg.get("To")),
                "subject": decode(msg.get("Subject")),
                "date": decode(msg.get("Date")),
                "body": redact(body_of(msg))[:BODY_LIMIT],
                "links": re.findall(r"https?://[^\s\"'<>)\]]+", body_of(msg))[:25],
            }
        )
    return out


def cmd_accounts(_args) -> int:
    out = []
    try:
        names = sorted(os.listdir(CRED_DIR))
    except FileNotFoundError:
        names = []
    for name in names:
        m = re.fullmatch(r"mail-(.+)\.env", name)
        if not m:
            continue
        path = os.path.join(CRED_DIR, name)
        cfg = {}
        try:
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    if "=" in line and not line.strip().startswith("#"):
                        k, _, v = line.partition("=")
                        cfg[k.strip().upper()] = v.strip().strip("'\"")
        except OSError:
            continue
        out.append(
            {
                "account": m.group(1),
                "user": cfg.get("MAIL_USER", "?"),
                "host": cfg.get("MAIL_HOST", DEFAULT_HOST),
                "mode": "%o" % (os.stat(path).st_mode & 0o777),
                "has_password": bool(
                    cfg.get("MAIL_APP_PASSWORD") or cfg.get("MAIL_PASSWORD")
                ),
            }
        )
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


def build_query(args) -> str:
    if getattr(args, "query", None):
        return args.query
    terms = []
    if getattr(args, "sender", None):
        terms.append('FROM "%s"' % args.sender)
    if getattr(args, "subject", None):
        terms.append('SUBJECT "%s"' % args.subject)
    if getattr(args, "since", None):
        parts = re.split(r"[-/]", args.since)
        if len(parts) == 3:
            y, m, d = parts
            months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
            terms.append("SINCE %s-%s-%s" % (d, months[int(m) - 1], y))
    return " ".join(terms) if terms else "ALL"


def cmd_read(args) -> int:
    cfg = load_account(args.account)
    query = build_query(args)
    conn = connect(cfg)
    try:
        rows = fetch(conn, args.mailbox, query, args.limit)
    finally:
        try:
            conn.logout()
        except Exception:
            pass
    print(json.dumps({"account": args.account, "query": query, "count": len(rows), "messages": rows},
                     indent=2, ensure_ascii=False))
    return 0


def cmd_wait(args) -> int:
    """Poll until a matching message shows up — for registration confirmations."""
    cfg = load_account(args.account)
    deadline = time.time() + args.timeout
    seen: set[str] = set()
    while time.time() < deadline:
        try:
            conn = connect(cfg)
            try:
                rows = fetch(conn, args.mailbox, build_query(args), args.limit)
            finally:
                try:
                    conn.logout()
                except Exception:
                    pass
            for row in rows:
                if row["uid"] not in seen:
                    seen.add(row["uid"])
                    print(json.dumps({"found": True, "message": row}, indent=2, ensure_ascii=False))
                    return 0
        except Exception as exc:
            print("poll error: %s" % redact(str(exc))[:200], file=sys.stderr)
        time.sleep(args.interval)
    print(json.dumps({"found": False, "waited_seconds": args.timeout}, indent=2))
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Read mail from a named, configurable account.")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("accounts", help="list the configured accounts").set_defaults(func=cmd_accounts)

    for name, fn in (("read", cmd_read), ("search", cmd_read)):
        p = sub.add_parser(name, help="fetch recent messages")
        p.add_argument("--account", required=True)
        p.add_argument("--mailbox", default="INBOX")
        p.add_argument("--limit", type=int, default=10)
        p.add_argument("--query", default=None, help="raw IMAP search expression")
        p.add_argument("--from", dest="sender", default=None)
        p.add_argument("--subject", default=None)
        p.add_argument("--since", default=None, help="YYYY-MM-DD")
        p.set_defaults(func=fn)

    p = sub.add_parser("wait", help="poll until a matching message arrives")
    p.add_argument("--account", required=True)
    p.add_argument("--mailbox", default="INBOX")
    p.add_argument("--limit", type=int, default=5)
    p.add_argument("--query", default=None)
    p.add_argument("--from", dest="sender", default=None)
    p.add_argument("--subject", default=None)
    p.add_argument("--since", default=None)
    p.add_argument("--timeout", type=int, default=300)
    p.add_argument("--interval", type=int, default=15)
    p.set_defaults(func=cmd_wait)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
