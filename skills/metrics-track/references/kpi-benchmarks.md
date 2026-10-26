# KPI Benchmarks & Templates

## Standard KPI Thresholds

| KPI | Target | Kill Threshold | Scale Threshold | Source |
|-----|--------|---------------|-----------------|--------|
| Landing → Signup | 3-5% | < 1% | > 8% | Industry avg |
| Signup → Activation | 20-40% | < 10% | > 50% | Product benchmark |
| D1 Retention | 25-40% | < 15% | > 50% | Mobile avg |
| D7 Retention | 10-20% | < 5% | > 25% | Mobile avg |
| D30 Retention | 5-10% | < 2% | > 15% | Mobile avg |
| Trial → Paid | 2-5% | < 1% | > 8% | SaaS avg |

Adjust based on product type:
- **B2B SaaS**: lower volume, higher conversion (Trial → Paid 5-15%)
- **B2C Mobile**: higher volume, lower retention (D30 > 5% is good)
- **Developer Tools**: activation is key metric (D7 retention > 20% = strong signal)
- **Marketplace**: both sides need activation (supply AND demand retention)

## Event Funnel Template

```
Awareness → Acquisition → Activation → Revenue → Retention → Referral
```

| Stage | Event Name | Trigger | Properties |
|-------|-----------|---------|------------|
| Awareness | `page_viewed` | Landing page visit (automatic) | utm source/medium/campaign (automatic) |
| Acquisition | `app_store_opened` / `signed_up` | Store click (`data-sda-event`) / signup | `placement` |
| Install | (store) | App Store `ct` token / Play `referrer` UTM | counted by the store, not by us |
| Activation | `app_launched`, then `core_action_completed` | First launch, first key action | `feature`; metric `duration_ms` |
| Revenue | `purchase_completed` | First payment | `plan`; metric `price_usd` |
| Retention | `app_launched` on later days | Return (D1/D7/D30), from the install-scoped id | read with `seo retention` |
| Referral | `invite_sent` | Shared or referred | `channel` |

Install and purchase attribution per campaign comes from App Store Connect (Acquisition → Campaigns) and Play Console. Nothing links one visitor to one install, and nothing should: that would take a cross-site identifier.

## Code Snippets (superduper-analytics)

### Web
```html
<!-- in <head>; the host is your deployment of superduper-analytics -->
<script defer src="https://analytics.example.com/sda.js" data-source="<registered-id>"></script>

<!-- a click goal with no code -->
<a href="https://apps.apple.com/app/id000000000?ct=site-hero&mt=8"
   data-sda-event="app_store_opened" data-sda-placement="hero">Get the app</a>
```
```typescript
// props are strings, metrics are numbers; batched and sent when the page is hidden
sda('signed_up', { plan: 'free' })
```
`page_viewed`, `page_engaged`, utm tags and `file_downloaded` arrive with no code.

### iOS / macOS (Swift, SPM `github.com/fortunto2/superduperai-analytics-swift`)
```swift
import SuperDuperAnalytics

// in App.init()
Analytics.configure(source: "<registered-id>")
Analytics.track("app_launched")

// later
Analytics.track("core_action_completed", props: ["feature": "scan_receipt"],
                metrics: ["duration_ms": elapsed])

// .onChange(of: scenePhase): the buffer dies with the process
if phase == .background { Analytics.flush() }
```
App Privacy: Usage Data → Product Interaction and Identifiers → Device ID, both Not Linked, not Tracking. No ATT prompt.

### Android, KMP, Python, server (no client)
POST the batch to the ingest endpoint. The contract is in the repo README and `src/schema.ts`:
```json
{"events": [{"source": "<registered-id>", "platform": "android", "name": "app_launched",
             "anon": "<install-scoped UUID>", "version": "1.2.0"}]}
```
Generate the UUID on first launch, keep it in app storage, let it die with the app. Not a device id, not an account id.

## A/B Test Analysis Template

```markdown
## A/B Test: {experiment name}

**Hypothesis:** If we {change}, then {metric} will {improve/decrease} because {reason}.
**Primary metric:** {metric name}
**Sample size needed:** {calculated from baseline rate + minimum detectable effect}
**Duration:** {days} (based on current traffic)

| Variant | Users | Conversions | Rate | vs Control |
|---------|-------|-------------|------|------------|
| Control | — | — | —% | — |
| Test | — | — | —% | +/- X% |

**Statistical significance:** {p-value or confidence interval}
**Decision:** SHIP variant / KEEP control / EXTEND test / INCONCLUSIVE
```

### Decision Rules
- p < 0.05 AND positive effect > minimum detectable → SHIP
- p < 0.05 AND negative effect → KEEP control, investigate why
- p > 0.05 after full duration → INCONCLUSIVE, check if sample size was sufficient
- Never peek and decide early — commit to sample size upfront

## Kill/Iterate/Scale Decision Framework

**Review cadence:** Weekly (Fridays)

### KILL signals (any 2 = kill)
- Activation rate < kill_threshold after 2 weeks
- D7 retention < kill_threshold after 1 month
- Zero organic signups after 2 weeks of distribution
- CAC > 3x LTV estimate

### ITERATE signals
- Metrics between kill and scale thresholds
- Qualitative feedback suggests product-market fit issues
- One stage of funnel is dramatically worse than others

### SCALE signals (all 3 = scale)
- Activation rate > scale_threshold
- D7 retention > scale_threshold
- Organic growth > 10% week-over-week
