# AI SDK 6 — Migration Pitfalls

When working with Vercel AI SDK 6 (`ai` package), avoid deprecated patterns:

- `maxSteps` → `stopWhen: stepCountIs(N)`
- `generateObject`/`streamObject` → `Output.object()` with `generateText`/`streamText`
- `CoreMessage` → `ModelMessage`
- `toDataStreamResponse` → `toUIMessageStreamResponse`
- `api` prop in useChat → `DefaultChatTransport`
- `input`/`setInput`/`handleSubmit`/`append` → `sendMessage`
- `isLoading` → `status === "streaming"`
- `textDelta` → `text-delta` (fullStream chunk types use kebab-case)
- `args` → `input` (tool-call chunks)
- `result` → `output` (tool-result chunks)

Tool parts type format: `tool-{toolName}`. States: `input-streaming` | `input-available` | `output-streaming` | `output-available`.

Helpers: `import { isToolUIPart, getToolName } from 'ai';`
