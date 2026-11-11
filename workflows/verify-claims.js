export const meta = {
  name: 'verify-claims',
  description: 'Each claim is recomputed blind and attacked by a second agent; only claims that survive both come back',
  whenToUse: 'Before a finding with a number reaches a person or a journal: a critic job, a KPI loop, a log review. args: {claims: [{claim, where}], sources?: how to reach the data and which files hold decisions and past findings, context?} or a plain-text list of claims followed by the sources.',
  phases: [
    { title: 'Recompute', detail: 'one agent per claim measures the number again without seeing how it was first measured' },
    { title: 'Attack', detail: 'one agent per claim looks for the reading that makes it false or already known' },
  ],
}

// AI-NOTE: exists because numbers went out wrong twice: a weekly spend quoted at half its real value, and a
// "has not happened since" claim that was true for one table and false for the system it spoke about.
const input = typeof args === 'string' ? (() => { try { return JSON.parse(args) } catch { return { claims: args } } })() : (args || {})
let claims = input.claims
if (typeof claims === 'string') {
  const split = await agent(
    `Split this text into separate factual claims, one per item, each self-contained (name the campaign, table, date range and number it states). Do not add or drop anything.\n\n${claims}`,
    { label: 'split', effort: 'low', schema: { type: 'object', required: ['claims'], properties: { claims: { type: 'array', items: { type: 'object', required: ['claim'], properties: { claim: { type: 'string' }, where: { type: 'string' } } } } } } },
  )
  claims = split ? split.claims : []
}
if (!Array.isArray(claims) || claims.length === 0) return { error: 'no claims given', usage: meta.whenToUse }
const MAX = 8
if (claims.length > MAX) { log(`${claims.length} claims given, checking the first ${MAX}; the rest are returned as unchecked`) }
const checked = claims.slice(0, MAX)
const context = input.context || ''

// Nothing about one domain is written here: the caller names where the truth lives (args.sources).
const sources = input.sources || 'Find the source yourself: the database or files the claim is about, and the project\'s own decision log and journal if it keeps them.'
const DATA = `Sources: ${sources} Everything is read-only: never write, post or change anything.`

const RECOMPUTE = {
  type: 'object', required: ['measured', 'matches', 'how'],
  properties: {
    measured: { type: 'string', description: 'the number or fact you measured yourself, with unit and date range' },
    matches: { type: 'string', enum: ['yes', 'no', 'cannot_measure'] },
    how: { type: 'string', description: 'the query or file you used, one line' },
    scope_gap: { type: 'string', description: 'what the claim covers that your source does not, or empty' },
  },
}
const ATTACK = {
  type: 'object', required: ['refuted', 'reason'],
  properties: {
    refuted: { type: 'boolean' },
    reason: { type: 'string', description: 'the reading that makes the claim false, too broad or already known; or why none holds' },
    narrower_true_claim: { type: 'string', description: 'if the claim is too broad, the version that is true' },
  },
}

const results = await pipeline(
  checked,
  (c) => agent(
    `Measure this yourself, from the data, without trusting it:\n\n"${c.claim}"\n${c.where ? `It is said to come from: ${c.where}\n` : ''}${context ? `Context: ${context}\n` : ''}\nWrite your own query. Check the date range, the currency, the grain (campaign vs account, contact vs deal) and whether rows are double counted by a join. Report what you measured and whether it matches. ${DATA}`,
    { label: `recompute: ${c.claim.slice(0, 50)}`, phase: 'Recompute', schema: RECOMPUTE },
  ),
  (r, c) => agent(
    `Try to refute this claim. Default to refuted=true when you cannot rule a failure out.\n\n"${c.claim}"\n\nAn independent recomputation got: ${r.measured} (matches: ${r.matches}; ${r.how}).\n${context ? `Context: ${context}\n` : ''}\nLook for: a source that covers only part of the system the claim speaks about (one table, one mailbox, one campaign); a recorded decision that already settles or contradicts it; a change in tracking or a form swap inside the date range; a sample too small to say anything (state n); the same finding already logged. ${DATA}`,
    { label: `attack: ${c.claim.slice(0, 50)}`, phase: 'Attack', schema: ATTACK },
  ).then((a) => ({ claim: c.claim, recompute: r, attack: a })),
)

const out = results.map((r, i) => {
  if (!r || !r.attack) return { claim: checked[i].claim, verdict: 'unchecked', why: 'an agent failed' }
  const verdict = r.recompute.matches === 'yes' && !r.attack.refuted ? 'holds'
    : r.recompute.matches === 'cannot_measure' ? 'unverified' : 'rejected'
  return { claim: r.claim, verdict, measured: r.recompute.measured, how: r.recompute.how,
    scope_gap: r.recompute.scope_gap || '', attack: r.attack.reason, narrower: r.attack.narrower_true_claim || '' }
})
claims.slice(MAX).forEach((c) => out.push({ claim: c.claim, verdict: 'unchecked', why: `over the limit of ${MAX}` }))
return { holds: out.filter((o) => o.verdict === 'holds').length, total: out.length, claims: out }
