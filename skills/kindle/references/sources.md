# find: sources and how each was checked (2026-11-14)

| Source | Endpoint | Notes |
|---|---|---|
| Project Gutenberg | `https://gutendex.com/books/?search=Q&languages=ru` (redirects, follow) | JSON; epub or text link per book; US public domain; occasional 503 |
| Standard Ebooks | `https://standardebooks.org/feeds/opds/all?query=Q` | OPDS/Atom; English only; "Recommended compatible epub" link picked; `rights` field is the licence note |
| Internet Archive | `advancedsearch.php?q=(Q) AND mediatype:texts AND licenseurl:*publicdomain*&output=json` | only items carrying a public-domain licence URL; the file (epub, else djvu txt, else pdf) is picked from `/metadata/<id>` at `--get` time; PDF scans are large and Kindle reflow is poor |
| Wikisource | `https://<lang>.wikisource.org/w/api.php?action=query&list=search` + `https://ws-export.wmcloud.org/?format=epub&lang=<lang>&page=<title>` | ru when the query is Cyrillic; subpages ("A/B") filtered out; licence is per page, the note says to verify |
| lib.ru "Классика" | not queried | no API, koi8-r pages, rights mixed; Wikisource ru covers the same classics |

Politeness: one request per second, a plain User-Agent, no parallelism. A burst gets engines suspended.
