# Amazon Send to Kindle: limits and rules

Read 2026-11-14 from Amazon's help pages (not from memory):

- https://www.amazon.com/gp/help/customer/display.html?nodeId=G7NECT4B4ZWHQ8WV
  - up to 25 attachments per mail, total 50 MB or less (ZIP to go beyond; Amazon unzips and converts)
  - up to 15 approved sender addresses per Send-to-Kindle address
  - sender must be on the **Approved Personal Document Email List** (Manage Your Content and Devices)
  - delivery is attempted for up to 60 days
- https://www.amazon.com/gp/help/customer/display.html?nodeId=G5WYD9SAF7PGXRNA
  - supported: HTML/HTM, RTF, TXT, JPEG, GIF, PNG, BMP, PDF, EPUB (web upload: up to 200 MB)
- https://www.amazon.com/sendtokindle/email
  - adds DOC, DOCX to the list; menu path: Manage Your Content & Devices > Preferences > Personal Document Settings; "You don't need to include a subject line."

MOBI and AZW3 are not on the lists: convert to EPUB first.

Not verified: the old "subject: convert" trick for PDFs is on none of these pages, so the script sends an empty subject.
The script keeps one file per mail on purpose (clean audit, no all-or-nothing failures).
Gmail caps a message at 25 MB, so the gws sender is limited to 18 MB of file (base64 overhead); SMTP senders use 50 MB.
