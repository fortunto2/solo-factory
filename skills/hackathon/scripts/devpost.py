#!/usr/bin/env python3
"""Devpost gallery -> projects.json. Stdlib only, fetches through curl.

    python3 devpost.py https://<slug>.devpost.com/project-gallery           # winners only
    python3 devpost.py https://<slug>.devpost.com/project-gallery --all     # every project
    python3 devpost.py https://devpost.com/software/<slug>                  # one project page

Prints a JSON list to stdout: url, name, prizes (verbatim, from the page's "Winner"
labels), built_with, links (Try it out: repo, demo), team (Devpost profiles), video,
story (page text, first 6000 chars). One request per second.

Checked 2026-10-26: WebFetch and Python's urllib get HTTP 403 from Devpost even with a
browser User-Agent; curl with the same User-Agent gets 200. The gallery is 24 projects
per page and, once winners are announced, lists them first.
"""

import json
import re
import subprocess
import sys
import time

UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
)
ITEM = 'class="large-4 small-12 columns gallery-item"'
SOFTWARE = re.compile(r'href="(https://devpost\.com/software/[^"]+)"')
PRIZE = re.compile(r'<span class="winner[^"]*">Winner</span>(.*?)</li>', re.S)
TAG = re.compile(r'<span class="cp-tag[^"]*">(.*?)</span>', re.S)
HREF = re.compile(r'href="(https?://[^"]+)"')
MEMBER = re.compile(r'class="user-profile-link" href="(https://devpost\.com/[^"]+)"')
VIDEO = re.compile(r'src="(https://www\.youtube\.com/embed/[^"?]+)')


def get(url: str) -> str:
    return subprocess.run(
        ["curl", "-sfL", "--max-time", "30", "-A", UA, url],
        capture_output=True,
        text=True,
        check=True,
    ).stdout


def text(html: str) -> str:
    # A section cut at its end marker leaves a half-open tag behind; drop it too.
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*(?:>|$)", " ", html)).strip()


def between(html: str, start: str, end: str) -> str:
    i = html.find(start)
    if i < 0:
        return ""
    j = html.find(end, i)
    return html[i : j if j > 0 else len(html)]


def gallery_page(html: str, everything: bool) -> tuple[int, list[str]]:
    """(cards on the page, project URLs picked): winners, or all with `everything`."""
    items = html.split(ITEM)[1:]
    picked = [
        m.group(1)
        for item in items
        if (m := SOFTWARE.search(item)) and (everything or 'class="winner"' in item)
    ]
    return len(items), picked


def gallery(url: str, everything: bool) -> list[str]:
    urls: list[str] = []
    page = 1
    while True:
        cards, picked = gallery_page(get(f"{url}?page={page}"), everything)
        urls += picked
        # Winners come first, so a page without one ends a winners-only walk.
        if not cards or not picked:
            return urls
        page += 1
        time.sleep(1)


def parse_project(url: str, h: str) -> dict:
    title = re.search(r"<title>(.*?)</title>", h, re.S)
    submitted = between(h, 'id="submissions"', 'id="app-team"')
    links = between(h, 'data-role="software-urls"', 'id="app-details-right"')
    team = between(h, 'id="app-team"', "</section>")
    story = between(h, 'id="app-details-left"', 'id="built-with"')
    return {
        "url": url,
        "name": text(title.group(1)).split(" | ")[0] if title else "",
        "prizes": [text(p) for p in PRIZE.findall(submitted)],
        "built_with": [text(t) for t in TAG.findall(h)],
        "links": sorted(set(HREF.findall(links))),
        "team": sorted(set(MEMBER.findall(team))),
        "video": VIDEO.findall(story)[:1],
        "story": text(story.split(">", 1)[-1])[:6000],
    }


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    url = args[0].rstrip("/")
    if "/software/" in url:
        urls = [url]
    else:
        urls = gallery(url, everything="--all" in sys.argv)
    out = []
    for u in urls:
        out.append(parse_project(u, get(u)))
        time.sleep(1)
    json.dump(out, sys.stdout, indent=1, ensure_ascii=False)
    print()
    print(f"{len(out)} project(s) from {url}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
