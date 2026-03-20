# Platform-Specific Deploy & Log Commands

## Vercel (Next.js)

### Deploy
```bash
vercel link          # first time: link to project
vercel               # deploy preview
vercel --prod        # deploy production (after verifying preview)
```

### Environment Variables
```bash
vercel env ls                                    # show current env vars
vercel env add VARIABLE_NAME                     # add new var (interactive)
vercel env rm VARIABLE_NAME production           # remove var
vercel env add NAME production <<< "value"       # non-interactive add
```

### Logs
```bash
vercel logs --output=short 2>&1 | tail -50
```
Look for: `Error`, `FUNCTION_INVOCATION_FAILED`, `EDGE_FUNCTION_INVOCATION_FAILED`, `504 GATEWAY_TIMEOUT`, unhandled rejections.

### Common Runtime Errors
- "Supabase URL/Key required" → add `NEXT_PUBLIC_SUPABASE_URL` + `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- "DATABASE_URL not set" → add `DATABASE_URL`
- "STRIPE_SECRET_KEY missing" → add Stripe keys or remove Stripe code if not ready
- Blank page / hydration error → check build logs, may need `vercel --prod` redeploy

---

## Cloudflare Workers

### Deploy
```bash
wrangler deploy              # Workers
```

### Environment Variables
```bash
wrangler secret put VARIABLE_NAME  # interactive prompt for value
# Or in wrangler.toml [vars] section for non-secret values
```

### Logs
```bash
wrangler tail --format=pretty 2>&1 | head -100
```
Look for: `Error`, uncaught exceptions, D1 query failures, R2 access errors.

---

## Cloudflare Pages (Astro)

### Deploy
```bash
wrangler pages deploy ./out  # Pages (check build output dir)
```

### Logs
```bash
wrangler pages deployment tail --project-name={name} 2>&1 | head -100
```

---

---

## SST (Infrastructure as Code)

### Deploy
```bash
sst deploy --stage prod    # production
sst deploy --stage dev     # staging
```

---

## Supabase Edge Functions

### Logs
```bash
supabase functions logs --scroll 2>&1 | tail -30
```

---

## Database Setup

### Supabase
```bash
supabase db push          # apply migrations
supabase gen types --lang=typescript --local > db/types.ts  # regenerate types
```

### Drizzle ORM
```bash
npx drizzle-kit push      # push schema to database
npx drizzle-kit generate  # generate migration files
```

### D1 (Cloudflare)
```bash
wrangler d1 migrations apply {db-name}
```

---

## Rust / Crates.io

### Deploy
```bash
cargo publish --dry-run       # verify everything passes
cargo publish                 # publish to crates.io
```

### Binary Release
```bash
cargo build --release
gh release create "v${VERSION}" --title "v${VERSION}" --generate-notes \
  "target/release/${BINARY}#${BINARY}-$(uname -s)-$(uname -m)"
```

### Verify
```bash
# Check crate is live
curl -s "https://crates.io/api/v1/crates/${CRATE}" | grep '"newest_version"'

# Test install from crates.io
cargo install ${CRATE} --version ${VERSION}
```

### Common Publish Errors
- "crate version already uploaded" → bump version in Cargo.toml
- "not logged in" → `cargo login` with API token from https://crates.io/settings/tokens
- "missing field: description/license" → add to `[package]` in Cargo.toml
- "path dependency not on crates.io" → replace `path = "..."` with crates.io version

---

## Verification

```bash
# HTTP status check
STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://{url})

# Check page content
BODY=$(curl -s https://{url} | head -200)

# Test API health
curl -s https://{url}/api/health
```
