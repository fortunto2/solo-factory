---
name: solo-paper
description: Turn a research result (math, algorithms, video/audio, systems, datasets) into a solid preprint or conference paper — LaTeX (amsart/article) built locally with tectonic, written from the project's research journal, references verified against databases, reviewed for errors and overclaims, code and data with a DOI, then submitted to arXiv (endorsement, category, license, AI-use disclosure). Use when the user says "напиши статью", "препринт", "на архив", "arXiv", "оформи результат", "статья на конференцию", "куда подать статью", "paper draft", "write this up", or a result is ready to be published. Do NOT use for publishing datasets alone (use /open-dataset), for printable PDFs from markdown (use /pdf-print), or for blog posts (use /content-gen).
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📄"
---

# paper — from a verified result to an arXiv preprint

A preprint is judged in the first page: a precise claim, its scope, and how a reader can
check it. Write it from what was recorded while the work happened (journals, logs, code),
not from memory, and publish nothing a reviewer has not tried to break.

## Before writing: is there a paper?

Yes if there is a **new, checkable statement** (theorem/lemma, classification, bound,
construction, reproducible measurement) that survived a literature check. No for a
leaderboard position, a polish of someone else's construction, or a negative result too
thin to stand alone (an appendix at most). Say which, in one line, before drafting.

## Choose the venue (any field, not only mathematics)

| Result | First stop | Peer-reviewed target |
|---|---|---|
| Mathematics (lemma, classification, construction) | arXiv math.* | combinatorics journals (e.g. Electron. J. Combin., Discrete Math.) |
| Algorithms, systems, video/audio/vision | arXiv cs.* / eess.* (cs.CV, cs.MM, eess.IV, eess.AS) | conference **workshops** first (CVPR/ICCV/ECCV, ACM MM, ICASSP, ICIP, NeurIPS): shorter, faster, higher acceptance; then main tracks or journals |
| Astronomy, sky/sensor measurements | arXiv astro-ph.IM / astro-ph.EP; Research Notes of the AAS (short, fast) | PASP, MNRAS instrumentation papers, citizen-science journals |
| Biology, bioinformatics | bioRxiv / arXiv q-bio | field journals; method papers in Bioinformatics, PLOS Comput Biol |
| Tools, datasets, benchmarks | arXiv + DOI'd repo | dataset/benchmark tracks (NeurIPS D&B), JOSS for research software |

- A preprint establishes priority within days. Peer review is what counts as a
  publication in most evaluations, including talent/extraordinary-ability visas, grant
  panels and hiring. Plan both: the arXiv version and one reviewed venue.
- Check the venue's AI-use policy and anonymity rules before uploading the preprint;
  most allow arXiv, some restrict publicity during review.
- **Reviewing** for a conference or journal is a separate, citable professional activity
  (program-committee member, workshop reviewer). Volunteer for workshops in your area once
  you have one paper there; keep the invitation and confirmation emails.
- Conference papers usually need a registered author to present, which means travel or
  visa logistics and a fee. Check this before submitting.

## Workflow

1. **Literature check first.** Search for newer work on the exact question: OpenAlex API
   (`api.openalex.org/works?search=…&sort=publication_date:desc`, no key), arXiv listing,
   zbMATH Open, the community site of the problem (e.g. erdosproblems.com), a web search.
   Feed each source a query with a known answer first: a silent zero is not "nothing new".
   Put what you found in the related-work paragraph, including results that make yours
   smaller.
2. **Skeleton from the journal.** Map research-journal entries to sections:
   goal → abstract/introduction; *what* lines in order → method (keep the dead ends that
   justify the final method); *result* lines → results, numbers verbatim; controls →
   their own subsection; *artifacts* → reproducibility.
3. **LaTeX.** `docs/paper-<slug>/main.tex`; `amsart` for mathematics, `article` otherwise.
   Theorem environments, one table per numeric claim, `\url` for code. Build:
   `brew install tectonic` once, then `tectonic main.tex` (fetches packages itself).
   Fix every Overfull/undefined warning.
4. **References from databases only.** Every `\bibitem`/BibTeX entry is copied from
   OpenAlex/Crossref/arXiv/zbMATH metadata (DOI or arXiv id), never typed from memory.
5. **Code and data with a DOI** (/open-dataset): public repo, CITATION.cff, release,
   Zenodo DOI; cite it in the paper. arXiv also accepts small ancillary files (`anc/`).
6. **Adversarial review.** A separate reviewer (strongest model available, briefed to
   refute) checks: is every claim implied by the evidence, scope stated (computer-assisted,
   what it depends on), numbers match the artifacts, overclaims. Fix, then a light
   /humanize pass on prose only, and diff every number before and after: identical.
7. **Submit** (outward-facing: the author decides). See below.

## arXiv submission

- **Author**: the human(s) who direct the work and take responsibility. AI systems are
  not authors; disclose their use in the text (method or acknowledgements), e.g. "The
  search was designed and run with AI agents (…) under the author's direction".
- **Endorsement**: a first submission to a category usually needs an endorser, someone who
  has published in that category recently. Start the submission, get the endorsement code
  from arXiv, and email it to a suitable person: the authors of the paper you build on are
  the natural choice. Send a short note with the result and the PDF, and attach no code
  unless they ask. Draft the email; the author sends it.
- **Category**: the narrowest fitting primary (e.g. math.CO), at most one or two
  cross-lists.
- **License**: CC BY 4.0 matches open data and code.
- **Metadata**: title and abstract as plain text with TeX math; comments field gives the
  page count and "code: <DOI>".
- **Identity**: an ORCID linked to the arXiv account, and the same name form in the paper,
  CITATION.cff and Zenodo.

## Verification

- `tectonic main.tex` builds with zero warnings.
- Every reference resolves (DOI/arXiv id opens the right work).
- Every number in the PDF appears in the journal or artifacts.
- The reviewer's blocking list is empty and their changes are applied.
