"""Crawl two Basic PAYE Tools servers and compare every page and static file.

Follows only local GET links, and never links that could send, delete,
restore or back up data. Exits with status 1 if a page differs.

Usage: compare_crawl.py --native-port N --hmrc-port N --native-home DIR --hmrc-home DIR --out DIR
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import http.cookiejar
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

SKIP = re.compile(
    r"(submit|send|delete|remove|restore|backup|logout|exit|shutdown|quit|updatecheck|clear|reset|gdpr|export)",
    re.IGNORECASE,
)
ASSET = re.compile(r"\.(css|js|png|gif|jpg|ico|svg|woff2?|ttf|eot|map)(\?|$)", re.IGNORECASE)
LINK = re.compile(r"""(?:href|action|src)\s*=\s*["']([^"'#]+)""")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # noqa: ANN002, ANN003, ANN201
        return None


class Server:
    def __init__(self, port: int, home: str) -> None:
        self.port = port
        self.home = home
        jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(jar), NoRedirect, urllib.request.ProxyHandler({})
        )

    def fetch(self, path: str) -> tuple[int, str, bytes]:
        try:
            with self.opener.open(f"http://127.0.0.1:{self.port}{path}", timeout=60) as response:
                return response.status, response.headers.get("Location", ""), response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.headers.get("Location", ""), error.read()

    def normalise(self, body: bytes) -> str:
        text = body.decode("utf-8", "replace")
        text = text.replace(f":{self.port}", ":PORT").replace(self.home, "HOME")
        text = re.sub(r"(name=['\"]csrfmiddlewaretoken['\"][^>]*value=['\"])[^'\"]+", r"\1X", text)
        text = re.sub(r"csrftoken=[A-Za-z0-9]+", "csrftoken=X", text)
        return re.sub(r"'time':\s+'[0-9.]+'", "'time': 'T'", text)  # page creation time

    def location(self, value: str) -> str:
        return value.replace(f":{self.port}", ":PORT")


def links(text: str) -> set[str]:
    found = set()
    for match in LINK.finditer(text):
        url = match.group(1).strip()
        if url.startswith("http://127.0.0.1:PORT"):
            url = url[len("http://127.0.0.1:PORT") :]
        if url.startswith("/") and not url.startswith("//"):
            found.add(url)
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-port", type=int, required=True)
    parser.add_argument("--hmrc-port", type=int, required=True)
    parser.add_argument("--native-home", required=True)
    parser.add_argument("--hmrc-home", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--max-pages", type=int, default=400)
    parser.add_argument("--min-pages", type=int, default=20)
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    native, hmrc = Server(args.native_port, args.native_home), Server(args.hmrc_port, args.hmrc_home)

    queue, seen, assets, different = ["/"], set(), set(), []
    while queue and len(seen) < args.max_pages:
        path = queue.pop(0)
        if path in seen:
            continue
        seen.add(path)
        n_status, n_loc, n_body = native.fetch(path)
        h_status, h_loc, h_body = hmrc.fetch(path)
        n_text, h_text = native.normalise(n_body), hmrc.normalise(h_body)
        if (n_status, native.location(n_loc), n_text) != (h_status, hmrc.location(h_loc), h_text):
            different.append(path)
            name = hashlib.sha256(path.encode()).hexdigest()[:12]
            diff = difflib.unified_diff(h_text.splitlines(True), n_text.splitlines(True), "hmrc", "native", n=2)
            (out / f"{name}.diff").write_text(
                f"PATH {path}\nSTATUS native={n_status} hmrc={h_status}\n" + "".join(diff)
            )
        nexts = links(n_text)
        location = native.location(n_loc)
        if location.startswith("http://127.0.0.1:PORT"):
            nexts.add(location[len("http://127.0.0.1:PORT") :])
        for url in sorted(nexts):
            if ASSET.search(url):
                assets.add(url)
            elif not SKIP.search(url) and url not in seen:
                queue.append(url)

    asset_diff = [a for a in sorted(assets) if native.fetch(a)[::2] != hmrc.fetch(a)[::2]]
    print(f"Pages compared: {len(seen)}, different: {len(different)}")
    print(f"Static files compared: {len(assets)}, different: {len(asset_diff)}")
    for path in different + asset_diff:
        print(f"DIFFERENT: {path}")
    if len(seen) < args.min_pages:
        print(f"FAIL: only {len(seen)} pages found (expected at least {args.min_pages})")
        return 1
    return 1 if different or asset_diff else 0


if __name__ == "__main__":
    sys.exit(main())
