"""Offline checks of the Devpost parser against markup copied from real pages (2026-10-26)."""

import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "devpost", Path(__file__).resolve().parent.parent / "scripts" / "devpost.py"
)
assert _spec and _spec.loader
devpost = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(devpost)


def card(slug: str, winner: bool) -> str:
    ribbon = (
        '<img alt="Winner" class="winner" src="ribbon.png" /> Winner' if winner else ""
    )
    return (
        '<div class="large-4 small-12 columns gallery-item" data-software-id="1">'
        f'<a class="block-wrapper-link" href="https://devpost.com/software/{slug}">'
        f"<h5>{slug}</h5></a>{ribbon}</div>"
    )


PROJECT = """<html><head><title>FaceTimeOS: AI Mac Agent | Devpost</title></head><body>
<div id="app-details-left"> <div id="gallery"><iframe
 src="https://www.youtube.com/embed/zN96RdE0OSg?enablejsapi=1"></iframe></div>
 <h2>Inspiration</h2><p>Have you ever gone to the gym?</p>
<div id="built-with" class=""> <h2>Built With</h2> <ul>
 <li><span class="cp-tag">claude</span></li>
 <li><span class="cp-tag recognized-tag"><a href="https://devpost.com/software/built-with/electron">electron</a></span></li>
</ul></div>
<nav class="app-links section"><h2>Try it out</h2><ul data-role="software-urls" class="no-bullet">
 <li><a href="https://github.com/example/calhacks-25"><span>github.com</span></a></li></ul></nav>
<aside id="app-details-right"><div id="submissions" class="section"><ul><li>
 <p><a href="https://cal-hacks-12-0.devpost.com/">Cal Hacks 12.0</a></p>
 <ul class="no-bullet"><li> <span class="winner label radius small all-caps">Winner</span> Cal Hacks: 1st Overall </li></ul>
</li></ul></div>
<section id="app-team"><a class="user-profile-link" href="https://devpost.com/member-one">M</a></section>
<div id="likers"><a class="user-profile-link" href="https://devpost.com/someone-who-liked">L</a></div>
</aside></body></html>"""


def test_winners_only_picks_ribboned_cards():
    html = card("a", True) + card("b", False) + card("c", True)
    assert devpost.gallery_page(html, everything=False) == (
        3,
        ["https://devpost.com/software/a", "https://devpost.com/software/c"],
    )


def test_all_mode_picks_every_card():
    cards, picked = devpost.gallery_page(
        card("a", False) + card("b", False), everything=True
    )
    assert (cards, len(picked)) == (2, 2)


def test_page_without_winners_picks_nothing():
    # The walk stops on this: winners are listed first once announced.
    assert devpost.gallery_page(card("a", False), everything=False) == (1, [])


def test_project_page_fields():
    p = devpost.parse_project("https://devpost.com/software/x", PROJECT)
    assert p["name"] == "FaceTimeOS: AI Mac Agent"
    assert p["prizes"] == ["Cal Hacks: 1st Overall"]
    assert p["built_with"] == ["claude", "electron"]
    assert p["links"] == ["https://github.com/example/calhacks-25"]
    assert p["video"] == ["https://www.youtube.com/embed/zN96RdE0OSg"]
    assert p["story"].startswith("Inspiration Have you ever gone to the gym?")


def test_team_excludes_people_outside_the_team_section():
    p = devpost.parse_project("https://devpost.com/software/x", PROJECT)
    assert p["team"] == ["https://devpost.com/member-one"]


def test_no_winner_label_means_no_prize():
    p = devpost.parse_project(
        "u", PROJECT.replace('<span class="winner label', '<span class="x')
    )
    assert p["prizes"] == []
