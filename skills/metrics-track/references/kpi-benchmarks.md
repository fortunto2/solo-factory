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

## PostHog Event Funnel Template

```
Awareness → Acquisition → Activation → Revenue → Retention → Referral
```

| Stage | Event Name | Trigger | Properties |
|-------|-----------|---------|------------|
| Awareness | `page_viewed` | Landing page visit | `source`, `utm_*` |
| Acquisition | `app_installed` or `signed_up` | First install/signup | `platform`, `source` |
| Activation | `core_action_completed` | First key action | `feature`, `duration_ms` |
| Revenue | `purchase_completed` | First payment | `plan`, `amount`, `currency` |
| Retention | `session_started` | Return visit (D1/D7/D30) | `session_number`, `days_since_install` |
| Referral | `invite_sent` | Shared or referred | `channel`, `referral_code` |

## PostHog Code Snippets

### iOS (Swift)
```swift
PostHogSDK.shared.capture("core_action_completed", properties: [
    "feature": "scan_receipt",
    "duration_ms": elapsed
])

// Identity
PostHogSDK.shared.identify(userId, userProperties: [
    "plan": "free",
    "signup_source": source
])
```

### Web (TypeScript)
```typescript
posthog.capture('signed_up', {
    source: searchParams.get('utm_source') ?? 'direct',
    plan: 'free'
})

// Identity
posthog.identify(userId, {
    plan: 'free',
    signup_source: source
})
```

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
