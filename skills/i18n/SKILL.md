---
name: solo-i18n
description: Use when "add languages", "translate the app", "localization", "i18n", "make it multilingual", or when UI strings are hardcoded and a second language is coming.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🌍"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
argument-hint: "[platform: ios | web | android] [languages]"
---

# /i18n

Take an app from one language to many, and keep it there. Written after
shipping 36 languages in an iOS app; the traps below each cost real time and
none of them announce themselves — a missed string looks perfect in English.

## The order of work

1. **Humanize the source language first.** Translating is per-language cost:
   fixing an English sentence after the fact means re-translating it in every
   language. `/humanize` on the long copy, then translate.
2. **Extract, don't hunt.** Get the platform's extractor to produce the key
   list. A grep for quoted strings finds prose and misses everything typed
   wrong (see the type rule below).
3. **Translate in batches**, machine-first, with a validator that refuses a
   batch dropping a format specifier or a plural category.
4. **Look at it running**, in a right-to-left language and in a long-word
   language (German, Finnish). A language that is merely declared is not a
   language that works.

## The type rule — the one that decides everything

**Anything a person reads must be typed as the platform's localizable type,
not as a plain string.**

| Platform | Right | Wrong, and silent |
|---|---|---|
| SwiftUI | `LocalizedStringKey`, `LocalizedStringResource` | `let title: String` |
| React / Next | `t("key")` from the i18n hook | a bare JSX literal in a prop |
| Android Compose | `stringResource(R.string.x)` | a `String` constant |

The extractor only sees literals in positions typed as localizable. A view
property declared `let title: String` takes its literal from the call site,
where nothing is looking — the control is never translated and English still
looks perfect. One pass found the whole bottom tab bar, four gallery filters,
four calendar chips, the settings list and every icon button's screen-reader
name, all invisible until somebody switched language.

Put it in the pre-commit hook. A lint rule on the naming that means "this is
shown" (`title`, `label`, `note`, `blurb`, `caption`, `placeholder`) typed as
a plain string catches it while it is one line, not one release.

## Three ways strings escape the extractor

- **An enum's `rawValue.capitalized` is not a label.** The raw value is the
  switch's identity; drawing chips from it makes them untranslatable.
- **Never compare against a shown word.** `if label == "Auto"` matches one
  language in thirty-six. Compare by case or by index.
- **An accessibility *identifier* is not a title.** Test scripts find rows by
  `settings.film`; if that string follows the language, the whole automation
  suite breaks in every language but one. Pass the id separately.

## Counts, dates and money

- **Counted nouns go through the plural system, never a `== 1` ternary.**
  CLDR categories differ: Japanese 1, English 2, Romanian and Hebrew 3,
  Russian and Polish 4, **Arabic 6** (zero/one/two/few/many/other). Only
  `other` is universally required; write the table from CLDR, not memory.
- **Dates are built from a template, never glued.** Order, separators and
  month case all move: `setLocalizedDateFormatFromTemplate` (Apple),
  `Intl.DateTimeFormat` (web), `DateTimeFormatter.ofLocalizedDate` (JVM).
  "March 5" and "5 марта" come from one call.
- **A fixed format needs a fixed locale.** A formatter with
  `dateFormat = "yyyy-MM-dd"` for a filename or an id follows the phone's
  calendar and digits — 2569 under Buddhist, ٢٠٢٦ under Arabic-Indic. Apple:
  `en_US_POSIX`. Anywhere: an explicit invariant locale.
- **Durations and numbers have a formatter too.** `Duration.UnitsFormatStyle`,
  `Intl.NumberFormat`, `NumberFormat` — hand-written `\(m)m \(s)s` is a bug
  in every language including English.
- **Never interpolate a year into a translatable string**: it gets grouped
  ("2 026"). Wrap it as a plain string first.
- **A cached formatter keeps the language it was born in.** A
  `static let` formatter built once served German durations inside an Arabic
  UI. Formatters that a person reads get built per use, or rebuilt on change.

## Runtime language switching

If the app offers its own language picker rather than deferring to the OS,
three things are true and each has bitten:

- **The system resolves the bundle before your code runs.** Writing the
  language into the OS's own key (`AppleLanguages`, `LANG`, the cookie) is what
  makes it survive a relaunch, but on its own it is a change you see *next*
  launch. A picker that says "restart to apply" is a picker people press twice.
- **The override must cover every lookup path.** Measured on iOS: swapping the
  main bundle's class fixed SwiftUI's `Text("key")` and did nothing for
  `String(localized:)`, which resolves the bundle by identity. Half the app
  translated and half did not. Whatever mechanism you pick, prove it on
  *both* paths before believing it.
- **"System" must mean the system.** Once the app writes its own language key,
  every "what does this phone speak" API answers with that choice — so going
  back to System does nothing. Read the platform's language list only after
  clearing your own key, and negotiate it against the locales you actually
  ship.

Log one line at launch naming what was chosen and what it resolved to. From
outside the app there is no other way to tell "the phone is German" from "the
picker is stuck on German".

## Machine translation, honestly

Machine translation is the right default for shipping: it is far better than
English-only, and a native pass can follow per language as users arrive. Two
rules keep it from embarrassing you:

- **Never machine-translate a legal or a money string.** Refunds, consent,
  subscription terms and permission prompts get a human, or stay in English.
- **Say which languages had a native reader.** Keep it in the doc, so nobody
  later assumes all of them did.

Validate every batch before it lands:

- every format specifier in the source appears in the translation;
- plural categories belong to that language;
- brand names, units and code identifiers are untouched;
- nothing got "helpfully" expanded past the space it has.

## Testing

- **The suite runs in one fixed language.** If the test host is the app, a
  language somebody picked by hand on that machine becomes the language the
  suite compares against — nineteen tests once failed that way, on a green
  build.
- **Assert against the built bundle, not the source catalogue.** A complete
  catalogue that fell out of the build config produces exactly the same
  English screen as a missing translation, and only the bundle tells them
  apart.
- **Check pluralization for one language with more forms than English** — it
  catches a whole class of "translated the singular only".
- **Screenshot the longest language and an RTL one.** German and Finnish find
  the truncation; Arabic and Hebrew find the layout that never mirrored.

## Deliverables

A finished localization pass leaves behind:

- the catalogue, complete, with a script that reports what is missing;
- a merge tool that validates batches, so a bad one cannot land quietly;
- a lint or hook rule for the type mistake;
- a doc naming the language set, why those, which had native readers, and how
  to add the next one;
- screenshots of at least one RTL and one long-word language.
