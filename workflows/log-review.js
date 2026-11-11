export const meta = {
  name: 'log-review',
  description: 'A service log read from several angles: its health against the previous window, then improvements, each re-measured and checked against what was already fixed, ranked by value for the effort',
  whenToUse: 'Before choosing what to fix in a service that logs its calls (an MCP server, a search door). args: {surface: "<name>", log: "<tables and what a row is>", sources: "<how to query, where the code is>", known: "<files that record what was already fixed, decided or proposed>", days?: 7, top?: 5, angles?: ["failures","unanswered","time","callers"], per_angle?: 4, model?, effort?}. Read-only: it proposes, the caller fixes.',
  phases: [
    { title: 'Health', detail: 'this window against the one before, in numbers' },
    { title: 'Find', detail: 'one analyst per angle' },
    { title: 'Check', detail: 'each candidate measured again and tested against what was already fixed' },
  ],
}

// AI-NOTE: written after a hand-made Pareto read listed two problems fixed on 10-23 and
// one cluster at 48 that measured 12: every candidate is re-measured and dated here before it is ranked.
const input = typeof args === 'string' ? (() => { try { return JSON.parse(args) } catch { return {} } })() : (args || {})
if (!input.surface || !input.log || !input.sources) return { error: 'surface, log and sources are required', usage: meta.whenToUse }
const days = input.days || 7
const top = input.top || 5
const perAngleMax = input.per_angle || 4
const tier = {}
if (input.model) tier.model = input.model
if (input.effort) tier.effort = input.effort
const ctx = `Service: ${input.surface}. Its log: ${input.log}\nHow to read it: ${input.sources}\nWindow: the last ${days} days, compared with the ${days} days before. Read-only: SELECT and file reads only, change nothing, post nowhere, never print a credential.`
const known = input.known ? `What was already fixed, decided or proposed is recorded in: ${input.known}` : 'Find what was already fixed in the git log of the code and in any journal or proposals file beside it.'

phase('Health')
const health = await agent(
  `${ctx}\n\nMeasure the health of this service. Report: calls and distinct callers; the failure rate counting only real errors (if the log separates kinds such as not_found, pending, refused or timeout from errors, say which you counted and why); p50 and p95 latency; the share of answers the service itself marked weak (low confidence, abstained, empty) if it records that; and the three largest changes against the previous window. Exclude our own test traffic and say how you recognised it. One verdict: ok, watch or red, with the number behind it.`,
  { label: 'health', phase: 'Health', ...tier, schema: { type: 'object', required: ['verdict', 'headline', 'numbers'], properties: {
    verdict: { type: 'string', enum: ['ok', 'watch', 'red'] }, headline: { type: 'string', description: 'one line under 160 characters with the numbers' },
    numbers: { type: 'array', items: { type: 'string' } }, excluded: { type: 'string' } } } },
)

const ANGLES = [
  { key: 'failures', ask: 'Real failures: group them by tool or route and by message. For each group say whether the caller recovered on the next call. A failure the caller fixes by itself in one retry is cheap; one that ends the task is not.' },
  { key: 'unanswered', ask: 'Questions the service could not answer or answered weakly: cluster them by subject. Separate a missing-content gap (someone must write it) from a routing or wording problem in our code (the content exists and was not found, or the question was sent to the wrong place).' },
  { key: 'time', ask: 'Where the time goes: total minutes per tool or route, waits that end in a timeout just before the answer would have come, callers doing one at a time what a batch call does.' },
  { key: 'callers', ask: 'How callers actually use it: a tool called in a way its description invites but its code refuses, a parameter nobody passes, a caller that retries the same thing, a person blocked by a permission, small talk sent as a query.' },
]
const CAND = { type: 'object', required: ['candidates'], properties: { candidates: { type: 'array', items: { type: 'object',
  required: ['title', 'claim', 'per_week', 'fix', 'owner', 'effort'], properties: {
    title: { type: 'string' }, claim: { type: 'string', description: 'the measured problem as one sentence with its number and date range' },
    per_week: { type: 'number', description: 'occurrences per week in the window' },
    fix: { type: 'string', description: 'the smallest change that removes it, naming the file or the person' },
    owner: { type: 'string', enum: ['our_code', 'content_owner', 'caller', 'decision'] },
    effort: { type: 'string', enum: ['small', 'medium', 'large'] }, query: { type: 'string' } } } } } }
const CHECK = { type: 'object', required: ['holds', 'per_week_now', 'already_fixed', 'why'], properties: {
  holds: { type: 'boolean' }, per_week_now: { type: 'number', description: 'occurrences per week counted only AFTER the newest related fix, or over the window if there is none' },
  already_fixed: { type: 'boolean' }, fixed_on: { type: 'string' }, already_proposed: { type: 'boolean' },
  why: { type: 'string' }, fix_is_right: { type: 'string', description: 'yes, or the better fix in one line' } } }

const angles = Array.isArray(input.angles) && input.angles.length ? ANGLES.filter((a) => input.angles.includes(a.key)) : ANGLES
if (angles.length < ANGLES.length) log(`angles limited to ${angles.map((a) => a.key).join(', ')} by the caller`)
const perAngle = await pipeline(
  angles,
  (a) => agent(
    `${ctx}\n\nAngle: ${a.ask}\n\nReturn at most ${perAngleMax} candidates, the largest first, each a problem you measured (give the query) with how often it happens per week and the smallest fix. Say who owns the fix: our_code, content_owner (the person who owns the knowledge), caller (the client's prompt or habit), or decision (a person must choose). No ideas without a count.`,
    { label: `find: ${a.key}`, phase: 'Find', schema: CAND, ...tier },
  ),
  (found, a) => parallel(found.candidates.slice(0, perAngleMax).map((c) => () => agent(
    `${ctx}\n${known}\n\nA reviewer claims: "${c.claim}" and proposes: "${c.fix}".\n\nDo three things. (1) Measure it yourself with your own query; do not reuse theirs. (2) Find out whether it was already fixed: search the git log of the code and the recorded files for this tool, route or message, and if a fix exists count the occurrences only AFTER its date. A problem that stopped on the day of a fix is fixed, however large the window total looks. (3) Check that the thing counted is a problem at all and not a correct answer logged under an alarming label, or a deliberate decision. Default to holds=false when you cannot reproduce the number within a factor of two.`,
    { label: `check: ${c.title.slice(0, 40)}`, phase: 'Check', schema: CHECK, ...tier },
  ).then((v) => ({ ...c, angle: a.key, check: v })))),
)

const all = perAngle.filter(Boolean).flat().filter(Boolean)
const WEIGHT = { small: 1, medium: 3, large: 8 }
const live = all.filter((c) => c.check && c.check.holds && !c.check.already_fixed)
  .map((c) => ({ ...c, score: (c.check.per_week_now || 0) / WEIGHT[c.effort] }))
  .sort((x, y) => y.score - x.score)
if (live.length > top) log(`${live.length} improvements hold, returning the top ${top}; the rest are listed by title`)
const brief = (c) => ({ title: c.title, angle: c.angle, per_week: c.check.per_week_now, effort: c.effort, owner: c.owner,
  claim: c.claim, fix: c.check.fix_is_right && c.check.fix_is_right !== 'yes' ? c.check.fix_is_right : c.fix,
  already_proposed: !!c.check.already_proposed, evidence: c.check.why })
return {
  surface: input.surface, days,
  health: health || { verdict: 'unknown', headline: 'health agent failed' },
  improvements: live.slice(0, top).map(brief),
  also_hold: live.slice(top).map((c) => c.title),
  // live holds copies (with a score), so membership is by title, not by object identity
  dropped: all.filter((c) => !live.some((l) => l.title === c.title)).map((c) => ({ title: c.title,
    why: !c.check ? 'not checked (agent failed)' : c.check.already_fixed ? `already fixed ${c.check.fixed_on || ''}`.trim() : c.check.why })),
}
