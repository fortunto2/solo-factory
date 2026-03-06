---
name: solo-legal
description: Generate privacy policy and terms of service from PRD and stack config. Privacy-first by default — minimal data collection, local processing, user data ownership. Use when user says "privacy policy", "terms of service", "legal pages", "GDPR", "CCPA", or "app store legal". Do NOT use for NDA or contracts.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "📜"
allowed-tools: Read, Grep, Glob, Write, AskUserQuestion
argument-hint: "[project-name]"
---

# /legal

Generate privacy policy and terms of service tailored to the project's stack, features, and data handling. Aligned with manifesto privacy-first principles (`templates/principles/manifest.md`): on-device processing, local storage, no accounts when possible, user owns their data.

**Disclaimer:** Generated documents are templates, not legal advice. Review with a lawyer before publishing, especially for regulated industries (health, finance, children).

## Steps

1. **Parse project** from `$ARGUMENTS`.
   - Read `docs/prd.md` — features, ICP, data handling
   - Read `CLAUDE.md` — stack, services used
   - Read stack YAML from `templates/stacks/{stack}.yaml` if available
   - If empty: ask via AskUserQuestion

2. **Data audit** — determine what data the product collects:

   Scan PRD and codebase config for:

   | Data Type | Collected? | Stored Where | Purpose |
   |-----------|-----------|-------------|---------|
   | Email/name | — | Local / Supabase | Account |
   | Usage analytics | — | PostHog (EU) | Product improvement |
   | Payment info | — | Stripe (not stored locally) | Billing |
   | User content | — | On-device / local DB | Core feature |
   | Location | — | — | — |
   | Device info | — | — | — |
   | Cookies | — | — | — |
   | Third-party SDKs | — | — | — |

   For each "yes": note the legal basis (consent, legitimate interest, contract).

   **Manifest alignment check:**
   - Data stored locally? (offline-first principle)
   - Can user export all their data?
   - Can user delete all their data?
   - Any data sent to third parties without explicit consent?
   - Does the app work without an account?

3. **Detect applicable regulations:**

   | Regulation | Applies When | Key Requirements |
   |-----------|-------------|-----------------|
   | **GDPR** | EU users or EU-based business | Consent, right to access/delete/port, DPA with processors |
   | **CCPA/CPRA** | California users, >$25M revenue or >100K consumers | Right to know/delete/opt-out, "Do Not Sell" |
   | **App Store** | iOS app | Privacy nutrition labels, ATT framework |
   | **Play Store** | Android app | Data safety section, deletion policy |
   | **COPPA** | Users under 13 | Parental consent (flag if ICP includes children) |

   Most solo projects: GDPR + App Store/Play Store is sufficient.

4. **Generate Privacy Policy:**

   Structure (adapt to product):

   ```markdown
   # Privacy Policy

   **Last updated:** {YYYY-MM-DD}
   **Effective date:** {YYYY-MM-DD}

   ## What we collect

   {table from step 2 — only "yes" rows, in plain language}

   ## How we use it

   {purpose for each data type — be specific, not "to improve our services"}

   ## Where data is stored

   {local device / specific cloud service + region}
   {for offline-first apps: "Your data stays on your device. We cannot access it."}

   ## Third-party services

   {list each service: PostHog (EU), Stripe, Supabase — with links to their privacy policies}

   ## Your rights

   - **Access:** request a copy of your data
   - **Delete:** delete your account and all associated data
   - **Export:** download your data in {format}
   - **Opt-out:** disable analytics in app settings

   ## Data retention

   {how long data is kept, what triggers deletion}

   ## Children

   {if product is not for children under 13: "This product is not intended for children under 13."}

   ## Changes

   We may update this policy. Changes will be posted here with an updated date.

   ## Contact

   {email address for privacy questions}
   ```

   Rules:
   - Plain language, no legalese — users should understand what they're agreeing to
   - Be honest about what you collect — don't hide tracking behind vague language
   - Offline-first products get a simpler policy (less data = less to explain)
   - If the app collects nothing: say so explicitly ("We collect no personal data")

5. **Generate Terms of Service:**

   Structure:

   ```markdown
   # Terms of Service

   **Last updated:** {YYYY-MM-DD}

   ## What this is

   {product name} is {one-line description}. By using it, you agree to these terms.

   ## Your account

   {if accounts exist: account rules. If no accounts: "No account is required."}

   ## Your data

   You own your data. We do not claim any rights to content you create.
   {for offline-first: "Your data is stored on your device. We have no access to it."}

   ## Acceptable use

   Do not use {product} to: {short list of prohibited uses relevant to the product}

   ## Payments

   {if paid: pricing, refund policy, billing terms}
   {manifest alignment: "No hidden fees. What you see is what you pay."}
   {if one-time purchase: "One-time purchase. No recurring charges."}
   {if subscription: explain what justifies the recurring cost}

   ## Availability

   We aim to keep {product} available but cannot guarantee 100% uptime.
   {for offline-first: "Core features work without internet connection."}

   ## Limitation of liability

   {standard limitation clause — product provided "as is"}

   ## Changes

   We may update these terms. Continued use after changes means acceptance.

   ## Contact

   {email}
   ```

6. **Generate App Store privacy labels** (if iOS or Android):

   **iOS (App Store Connect):**
   - Privacy nutrition label categories based on data audit
   - Tracking: yes/no (ATT required if yes)
   - Data linked to identity: list
   - Data not linked to identity: list

   **Android (Play Store):**
   - Data safety form responses based on data audit
   - Data shared with third parties: list
   - Data collection purposes: list
   - Security practices: encryption, deletion available

7. **Write legal documents:**
   - `legal/privacy-policy.md` — privacy policy
   - `legal/terms-of-service.md` — terms of service
   - `legal/app-store-privacy.md` — app store labels (if mobile)
   - Create `legal/` directory in project root if needed

8. **Output summary:**
   - Data types collected (count)
   - Regulations applicable
   - Manifest alignment (all principles met or violations flagged)
   - Files generated
   - Reminder: "Review with a lawyer before publishing"

## Notes

- Documents are templates — always review before publishing
- Offline-first apps need simpler policies (this is a feature, not a limitation)
- Update legal docs when adding new data collection, third-party services, or features
- For EU-based products using PostHog: confirm EU hosting (eu.posthog.com)
- Stripe handles PCI compliance — never store card data yourself

## Common Issues

### Product collects more data than expected
**Cause:** Third-party SDKs (analytics, crash reporting) collect data automatically.
**Fix:** Audit all SDKs in package.json/Podfile/build.gradle. List each one in the privacy policy.

### Offline-first but still needs some cloud
**Cause:** Sync, backup, or auth requires cloud.
**Fix:** Be explicit: "Core features work offline. Optional sync requires {service}." List exactly what syncs.

### App Store rejection for missing privacy policy
**Cause:** No privacy policy URL in app metadata.
**Fix:** Host privacy-policy.md as a web page (GitHub Pages, project website, or static hosting). Add URL to App Store Connect / Play Console.
