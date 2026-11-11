export const meta = {
  name: 'dream',
  description: 'Check memory notes against what actually happened and what is true now; return proposed fixes, write nothing',
  whenToUse: 'Weekly, or after a note turned out wrong. args: {memory: "<dir of notes>", sources: "<where the truth lives: transcript search, repos, registry>", index?: "<index file>", limit?: n, only?: [file names], model?, effort?}. Read-only: the caller applies what it accepts.',
  phases: [
    { title: 'List', detail: 'the notes and the index' },
    { title: 'Check', detail: 'one agent per note tests its claims against the sources' },
    { title: 'Attack', detail: 'every proposed change is challenged; in doubt the note stays as it is' },
    { title: 'Across', detail: 'duplicates, contradictions and index drift over the whole set' },
  ],
}

// AI-NOTE: after anthropic.com/research/components-of-agent-memory (dreaming). A wrong note is read and trusted by every later session.
const input = typeof args === 'string' ? (() => { try { return JSON.parse(args) } catch { return { memory: args } } })() : (args || {})
if (!input.memory) return { error: 'no memory directory given', usage: meta.whenToUse }
const sources = input.sources || 'Find the sources yourself: past session transcripts if a search tool for them is connected, the repositories and files the note names, and any decision log the project keeps.'
// model/effort are the caller's choice (a box with a spare limit, a laptop near its cap), never fixed here.
const tier = {}
if (input.model) tier.model = input.model
if (input.effort) tier.effort = input.effort
const RO = 'Read-only. Never edit, move or delete any file; never post or send anything. Never quote a secret value.'

phase('List')
const listed = await agent(
  `List the memory notes in ${input.memory} (one fact per file, markdown with frontmatter)${input.index ? ` and read the index ${input.index}` : ' and its index file if there is one (MEMORY.md)'}. Return every note file name, and separately: index lines that point at no file, and files the index does not mention. ${RO}`,
  { label: 'list', effort: 'low', schema: { type: 'object', required: ['files'], properties: {
    files: { type: 'array', items: { type: 'string' } },
    index_without_file: { type: 'array', items: { type: 'string' } },
    file_without_index: { type: 'array', items: { type: 'string' } } } } },
)
if (!listed || listed.files.length === 0) return { error: `no notes found in ${input.memory}` }
let files = listed.files
if (Array.isArray(input.only) && input.only.length) files = files.filter((f) => input.only.some((o) => f.includes(o)))
const limit = input.limit || 40
if (files.length > limit) log(`${files.length} notes, checking ${limit}; not checked: ${files.slice(limit).join(', ')}`)
const skipped = files.slice(limit)
files = files.slice(0, limit)

const CHECK = { type: 'object', required: ['verdict', 'claims', 'reason'], properties: {
  verdict: { type: 'string', enum: ['keep', 'fix', 'delete', 'demote'], description: 'keep = true and still useful; fix = partly wrong or stale; delete = false, obsolete, or already recorded in the repo; demote = true but only matters to one finished task' },
  claims: { type: 'array', items: { type: 'object', required: ['claim', 'status', 'evidence'], properties: {
    claim: { type: 'string' }, status: { type: 'string', enum: ['confirmed', 'contradicted', 'stale', 'unverifiable'] },
    evidence: { type: 'string', description: 'file:line, command output, or session id and date; one line' } } } },
  reason: { type: 'string' },
  new_text: { type: 'string', description: 'for fix: the full corrected note body, same format, nothing invented' },
} }
const ATTACK = { type: 'object', required: ['change_stands', 'why'], properties: { change_stands: { type: 'boolean' }, why: { type: 'string' }, lost_if_applied: { type: 'string' } } }

const perNote = await pipeline(
  files,
  (f) => agent(
    `Check one memory note against reality: ${input.memory}/${f}\n\nA note is a prediction that a future session will need it and may trust it without checking. Split it into its checkable claims (a path, command, flag, table or person it names; a number; a rule and the incident given as its reason; a "since <date>" statement) and test each:\n- does the thing it names still exist, under that name? Run the command or open the file.\n- did the incident happen as described? Find the session or commit.\n- has anything later contradicted or replaced it (a newer note, a newer instruction file, a later session)?\n- is it scoped honestly, or does it state something about a whole system from one table or one case?\n- is it already written in a file that every session loads anyway (then the note is a duplicate)?\nSources: ${sources}\nPropose a change only on evidence. "Could not verify" is a reason to keep the note and say so, never to delete it. ${RO}`,
    { label: `check: ${f}`, phase: 'Check', schema: CHECK, ...tier },
  ).then((c) => ({ file: f, ...c })),
  (c) => c.verdict === 'keep' ? c : agent(
    `A reviewer proposes to ${c.verdict} the memory note ${input.memory}/${c.file}.\nReason: ${c.reason}\nEvidence per claim:\n${c.claims.map((x) => `- [${x.status}] ${x.claim} (${x.evidence})`).join('\n')}\n${c.new_text ? `Proposed new text:\n${c.new_text}\n` : ''}\nRead the note and the evidence yourself and try to show the change is wrong: the evidence does not say what is claimed, the note's rule still holds even if one detail is stale, the new text drops a caveat or invents something, or deleting loses the only record of an incident. Changing memory is lossy, so when you are unsure, change_stands=false. Sources: ${sources} ${RO}`,
    { label: `attack: ${c.file}`, phase: 'Attack', schema: ATTACK, ...tier },
  ).then((a) => ({ ...c, attack: a, verdict: a && a.change_stands ? c.verdict : 'keep', withdrawn: !(a && a.change_stands) ? c.verdict : '' })),
)

phase('Across')
const done = perNote.filter(Boolean)
const across = await agent(
  `Read all notes in ${input.memory} together (names: ${files.join(', ')}). Report only what a note-by-note check cannot see: two notes that say the same thing (name both and which should absorb the other), two that contradict each other, and a rule that three or more notes repeat and that therefore belongs one level up, in an instruction file loaded every session, as one line with links down. Keep it short; an empty list is a fine answer. ${RO}`,
  { label: 'across', schema: { type: 'object', required: ['duplicates', 'contradictions', 'promote'], properties: {
    duplicates: { type: 'array', items: { type: 'string' } }, contradictions: { type: 'array', items: { type: 'string' } }, promote: { type: 'array', items: { type: 'string' } } } } },
)
const changes = done.filter((d) => d.verdict !== 'keep')
return {
  checked: done.length, failed: files.length - done.length, not_checked: skipped,
  keep: done.filter((d) => d.verdict === 'keep' && !d.withdrawn).map((d) => d.file),
  changes: changes.map((d) => ({ file: d.file, verdict: d.verdict, reason: d.reason, new_text: d.new_text || '', evidence: d.claims.filter((x) => x.status !== 'confirmed') })),
  withdrawn_after_attack: done.filter((d) => d.withdrawn).map((d) => ({ file: d.file, was: d.withdrawn, why: d.attack ? d.attack.why : 'attacker failed' })),
  unverifiable: done.flatMap((d) => d.claims.filter((x) => x.status === 'unverifiable').map((x) => `${d.file}: ${x.claim}`)),
  index: { without_file: listed.index_without_file || [], without_index: listed.file_without_index || [] },
  across: across || { note: 'cross-note pass failed' },
}
