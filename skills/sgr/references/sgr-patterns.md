# SGR Patterns by Domain

## 1. Agent Tool Dispatch (NextStep)

The canonical SGR pattern. Agent reasons, plans, acts in one structured call.

```python
class NextStep(BaseModel):
    current_state: str
    plan_remaining_steps_brief: Annotated[list[str], MinLen(1), MaxLen(5)]
    task_completed: bool
    function: Union[Tool1, Tool2, ..., ReportCompletion] = Field(
        ..., description="execute first remaining step"
    )
```

**Use when:** building an agent loop with tool calling.
**Key:** `function` is a discriminated Union. Dispatch via `isinstance()`.

## 2. Compliance Analysis Cascade

Translate auditor's mental checklist into structured steps.

```python
class ComplianceCheck(BaseModel):
    preliminary_analysis: str
    applicability: Literal["applicable", "not_applicable", "partially"]
    applicability_reason: str
    gaps: list[GapItem]  # structured gap findings
    verdict: Literal["compliant", "partial", "non_compliant"]
    reasoning_for_verdict: str
    evidence_references: list[str]  # cite clause IDs
```

**Use when:** regulated domains (FinTech, healthcare, legal).
**Key:** verdict enum BEFORE reasoning. Evidence at the end.

## 3. Code Review / Quality Assessment

```python
class CodeReview(BaseModel):
    file_summary: str
    complexity_assessment: Literal["low", "medium", "high"]
    issues: list[Issue]  # severity + description + line
    security_concerns: list[str]
    suggested_improvements: Annotated[list[str], MaxLen(5)]
    overall_verdict: Literal["approve", "request_changes", "block"]
    verdict_reasoning: str
```

**Use when:** automated code review, PR analysis.

## 4. Mutation Planning (Evolutionary Code)

```python
class CodeAnalysis(BaseModel):
    complexity_score: Annotated[int, Le(10)]
    algorithmic_approach: str
    bottlenecks: list[str]
    optimization_opportunities: list[str]

class MutationStrategy(BaseModel):
    strategy: Literal["refactor", "optimize", "rewrite", "specialize"]
    confidence: Annotated[float, Le(1.0)]
    reasoning: str
    target_area: str
    expected_improvement: str
```

**Use when:** AI-driven code evolution, genetic programming.
**Key:** two schemas = two calls. Analysis first, strategy second.

## 5. Startup Idea Validation (STREAM-style)

```python
class IdeaEvaluation(BaseModel):
    problem_clarity: Annotated[int, Le(10)]
    evidence_strength: Annotated[int, Le(10)]
    market_signals: list[str]
    competitor_landscape: Literal["empty", "sparse", "crowded", "dominated"]
    technical_feasibility: Literal["trivial", "moderate", "hard", "research"]
    verdict: Literal["go", "iterate", "kill"]
    key_risk: str
    next_action: str
```

**Use when:** quick idea scoring, research synthesis.

## 6. Content Classification / Routing

```python
class ContentRoute(BaseModel):
    intent: Literal["question", "request", "complaint", "feedback", "spam"]
    urgency: Literal["low", "medium", "high", "critical"]
    requires_human: bool
    suggested_handler: Literal["faq_bot", "support_agent", "escalation", "archive"]
    confidence: Annotated[float, Le(1.0)]
```

**Use when:** customer support routing, email triage, ticket classification.
**Key:** all fields are enums or bounded — zero ambiguity in output.
