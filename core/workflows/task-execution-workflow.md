# Task Execution Workflow

## Overview

This document describes the end-to-end workflow for executing tasks in the WOF multi-agent system, with validation checkpoints at every decision point.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TASK EXECUTION WORKFLOW                             │
│                                                                             │
│  ┌─────────┐     ┌─────────────────┐     ┌──────────────┐     ┌─────────┐  │
│  │  USER   │     │  ORCHESTRATOR   │     │   VALIDATOR  │     │  WORKER │  │
│  │         │     │     CLAUDE      │     │    CLAUDE    │     │  CLAUDE │  │
│  └────┬────┘     └────────┬────────┘     └──────┬───────┘     └────┬────┘  │
│       │                   │                     │                   │       │
│       │   Task Request    │                     │                   │       │
│       │──────────────────►│                     │                   │       │
│       │                   │  Validate intake    │                   │       │
│       │                   │────────────────────►│                   │       │
│       │                   │◄────────────────────│                   │       │
│       │                   │                     │                   │       │
│       │                   │  Delegate analysis  │                   │       │
│       │                   │─────────────────────┼──────────────────►│       │
│       │                   │                     │                   │       │
│       │                   │  Validate response  │◄──────────────────│       │
│       │                   │────────────────────►│                   │       │
│       │                   │◄────────────────────│                   │       │
│       │                   │                     │                   │       │
│       │                   │        ... (repeat for each step) ...   │       │
│       │                   │                     │                   │       │
│       │◄──────────────────│  Final delivery     │                   │       │
│       │                   │                     │                   │       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Test-Driven Improvement (Mandatory)

All phases must comply with the Test-Driven Improvement philosophy:

```
┌─────────────────────────────────────────────────────────────────┐
│              TEST-DRIVEN GATES (Non-Negotiable)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PLANNING:     No plan approved without testing strategy       │
│  DELEGATION:   Workers must include tests in deliverables      │
│  COMMIT:       No commit without passing tests                 │
│  CLOSURE:      No closure without repeatable validation        │
│                                                                 │
│  Validator enforces these gates. No exceptions.                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

See: `core/philosophy/test-driven-improvement.md`

---

## Phase 1: Task Intake

### 1.1 Task Source

```
┌─────────────────────────────────────────────────────────────────┐
│                        TASK SOURCES                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Source A: User Direct                                         │
│  ─────────────────────                                         │
│  User types request directly in Claude Code terminal           │
│                                                                 │
│  Source B: ADO Backlog                                         │
│  ────────────────────                                          │
│  Orchestrator queries ADO for assigned/ready work items        │
│  via: /ado list --filter "assigned to me, state=ready"        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Intake Validation (V1)

**Trigger:** Task received from any source
**Validator Prompt:**

```
VALIDATION CHECKPOINT V1: Task Intake

Task received: [task description]
Source: [user/ADO]

Questions:
1. Is this task clear and actionable?
2. Are requirements sufficiently specified?
3. Is scope bounded or open-ended?
4. Are there implicit assumptions that need clarification?
5. Is this task appropriate for autonomous execution?
6. Can this task be objectively validated with tests?
7. What would "done" look like in testable terms?

Recommend: PROCEED | CLARIFY | ESCALATE
```

**Possible Outcomes:**
- **PROCEED** → Move to Phase 2
- **CLARIFY** → Orchestrator asks user/ADO for clarification
- **ESCALATE** → Task requires human decision before proceeding

---

## Phase 2: Analysis & Planning

### 2.1 Delegate to Worker for Analysis

**Orchestrator → Worker Claude Heavy:**
```
Analyze this task and provide:
1. Understanding of requirements
2. Affected files/components
3. Potential approaches
4. Risks and considerations
5. Estimated complexity (T1/T2/T3)
```

### 2.2 Validate Analysis Request (V2)

**Trigger:** Before sending to Worker
**Validator Prompt:**

```
VALIDATION CHECKPOINT V2: Delegation Quality

Orchestrator wants to delegate: [analysis request]
To: Worker Claude Heavy

Questions:
1. Is the delegation clear and specific?
2. Does Worker have enough context to succeed?
3. Is this the right worker for the task (Heavy vs Lite)?
4. Are expected outputs well-defined?
5. Is the scope appropriate (not too broad, not too narrow)?

Recommend: APPROVE | REFINE | REJECT
```

### 2.3 Validate Analysis Response (V3)

**Trigger:** After receiving Worker's analysis
**Validator Prompt:**

```
VALIDATION CHECKPOINT V3: Analysis Quality

Worker returned analysis:
[analysis summary]

Questions:
1. Does the analysis address the original task?
2. Are the identified files/components correct? (verify independently)
3. Are the proposed approaches reasonable?
4. Are risks adequately identified?
5. Is anything obviously missing?
6. Does complexity estimate match what I see in the codebase?

Recommend: ACCEPT | REQUEST_REVISION | REJECT
```

### 2.4 Create Implementation Plan

Based on validated analysis, Orchestrator creates step-by-step plan.

### 2.5 Validate Plan (V4)

**Trigger:** Before executing plan
**Validator Prompt:**

```
VALIDATION CHECKPOINT V4: Plan Validation

Proposed implementation plan:
[step-by-step plan]

Testing strategy:
[required - must be provided]

Questions:
1. Does this plan achieve the original goal?
2. Are steps in logical order?
3. Are dependencies between steps identified?
4. Is each step small enough to be verifiable?
5. Are rollback points identified?
6. What could go wrong at each step?

TESTING QUESTIONS (MANDATORY):
7. Is there a concrete testing strategy?
8. What tests will be written?
9. How will we verify each acceptance criterion?
10. Are edge cases and failure modes covered?
11. Can tests be written BEFORE implementation?

REJECT if testing strategy is missing or vague.

Recommend: APPROVE | REVISE | ESCALATE_TO_USER
```

---

## Phase 3: Implementation

### 3.1 Execute Each Step

For each step in the validated plan:

```
┌─────────────────────────────────────────────────────────────────┐
│                    STEP EXECUTION LOOP                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ STEP N                                                    │  │
│  │                                                           │  │
│  │  1. Orchestrator prepares step delegation                │  │
│  │           ↓                                               │  │
│  │  2. V5: Validate step delegation                         │  │
│  │           ↓                                               │  │
│  │  3. Worker executes step                                 │  │
│  │           ↓                                               │  │
│  │  4. V6: Validate step result                             │  │
│  │           ↓                                               │  │
│  │  5. If issues: remediate or escalate                     │  │
│  │           ↓                                               │  │
│  │  6. Continue to next step                                │  │
│  │                                                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Repeat for each step in plan                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Validate Step Delegation (V5)

**Trigger:** Before each Worker task
**Validator Prompt:**

```
VALIDATION CHECKPOINT V5: Step Delegation

Step [N] of [total]: [step description]
Delegating to: [Worker Heavy/Lite]

Questions:
1. Is this step consistent with the approved plan?
2. Does the delegation include necessary context?
3. Is scope creep occurring? (step larger than planned)
4. Are acceptance criteria clear?
5. Is this step safe to execute autonomously?

Recommend: APPROVE | REFINE | PAUSE
```

### 3.3 Validate Step Result (V6)

**Trigger:** After each Worker response
**Validator Prompt:**

```
VALIDATION CHECKPOINT V6: Step Result

Step [N] completed. Worker reports:
[worker response summary]

Questions:
1. Did the step achieve its stated goal?
2. Are there any errors or warnings? (check independently)
3. Does the code change match the description?
4. Were any unplanned changes made?
5. Is the codebase still in a good state?
6. Can we proceed to the next step?

Recommend: ACCEPT | REMEDIATE | ROLLBACK
```

---

## Phase 4: Quality Gate (Critic)

### 4.1 Pre-Commit Review

After all implementation steps complete:

```
┌─────────────────────────────────────────────────────────────────┐
│                    CRITIC QUALITY GATE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Orchestrator → Critic Claude:                                 │
│                                                                 │
│  "Implementation complete. Please verify:"                     │
│  - Build status                                                │
│  - Test results                                                │
│  - Coverage metrics                                            │
│  - Linter/analyzer output                                      │
│  - Documentation completeness                                  │
│  - Commit readiness                                            │
│                                                                 │
│  Critic independently runs all verification commands           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Critic Verdict

```
CRITIC VERDICT: [PASS | FAIL | REMEDIATE]

Viability: [0.0 - 1.0]

Verified:
- Build: [result]
- Tests: [X/Y passing]
- Coverage: [X%]
- Linter: [N warnings]

Issues found: [list]
Recommendation: [fix now vs work item for each]
```

### 4.3 Validate Critic Findings (V7)

**Trigger:** After Critic review
**Validator Prompt:**

```
VALIDATION CHECKPOINT V7: Critic Review

Critic verdict: [verdict]
Viability score: [score]

Questions:
1. Did Critic actually run the verification commands? (check output)
2. Are the findings consistent with what I can verify?
3. Is the viability score appropriate given the findings?
4. Are the fix-now vs work-item recommendations reasonable?
5. Is anything missing from the review?

Recommend: ACCEPT_VERDICT | CHALLENGE_VERDICT | REQUEST_DEEPER_REVIEW
```

---

## Phase 5: Commit & Delivery

### 5.1 Pre-Commit Validation (V8)

**Trigger:** Before git commit
**Validator Prompt:**

```
VALIDATION CHECKPOINT V8: Commit Readiness

About to commit:
- Files: [list]
- Message: [commit message]

Questions:
1. Does commit message accurately describe changes?
2. Are we committing only intended files?
3. Are there any secrets or sensitive data in the diff?
4. Are there any generated files that shouldn't be committed?
5. Is this commit atomic (one logical change)?
6. Is there documentation that should be included?
7. Should this be multiple smaller commits?

TESTING VERIFICATION (MANDATORY - RUN THESE):
8. Did ALL tests pass? (run: dotnet test)
9. What is the test count? (X passed, 0 failed, 0 skipped)
10. Did coverage decrease? (run: coverage report)
11. Does new code have tests?
12. For bug fixes: is there a regression test?

BLOCK COMMIT if tests fail or coverage dropped significantly.

Recommend: COMMIT | REVISE | SPLIT
```

### 5.2 Execute Commit

```bash
git add [specific files]
git commit -m "[validated message]"
```

### 5.3 Post-Commit Validation (V9)

**Trigger:** After commit
**Validator Prompt:**

```
VALIDATION CHECKPOINT V9: Post-Commit

Commit completed: [hash]

Questions:
1. Did the commit succeed?
2. Is git status clean (no unintended leftovers)?
3. Should we push now or wait?
4. Are there follow-up tasks to create?
5. Does ADO work item need status update?

Recommend: PUSH | HOLD | CREATE_FOLLOWUP
```

---

## Phase 6: Completion

### 6.1 Task Closure

```
┌─────────────────────────────────────────────────────────────────┐
│                    TASK COMPLETION                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Update ADO work item (if applicable)                       │
│     - State: Done/Closed                                       │
│     - Add completion comment                                   │
│                                                                 │
│  2. Report to user                                             │
│     - Summary of what was done                                 │
│     - Any follow-up items created                              │
│     - Any concerns or recommendations                          │
│                                                                 │
│  3. Update memory bank (if significant)                        │
│     - Architecture decisions                                   │
│     - Lessons learned                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Final Validation (V10)

**Trigger:** Task completion
**Validator Prompt:**

```
VALIDATION CHECKPOINT V10: Task Completion

Task: [original task]
Outcome: [summary]

Questions:
1. Was the original task fully addressed?
2. Were all acceptance criteria met?
3. Is the user likely to be satisfied?
4. Are there any loose ends?
5. Should any follow-up tasks be created?
6. Were there lessons learned worth documenting?

OBJECTIVE VALIDATION (MANDATORY):
7. Is the validation AUTOMATED? (no manual steps)
8. Is the validation REPEATABLE? (anyone can run it)
9. Do tests pass on CLEAN CHECKOUT? (not just local)
10. Will these tests catch REGRESSIONS in the future?
11. Can we objectively prove the task is complete?

REFUSE CLOSURE if validation is not objective and repeatable.
"It works on my machine" is not validation.
"I tested it manually" is not validation.

Recommend: CLOSE | FOLLOWUP_NEEDED | REOPEN
```

---

## Validation Checkpoint Summary

| Checkpoint | Trigger | Purpose |
|------------|---------|---------|
| **V1** | Task intake | Verify task is clear and actionable |
| **V2** | Before delegation | Verify delegation quality |
| **V3** | After analysis | Verify analysis quality |
| **V4** | Before execution | Verify plan quality |
| **V5** | Before each step | Verify step delegation |
| **V6** | After each step | Verify step result |
| **V7** | After Critic review | Verify Critic findings |
| **V8** | Before commit | Verify commit readiness |
| **V9** | After commit | Verify commit success |
| **V10** | Task completion | Verify task fully addressed |

---

## Validation Frequency

```
┌─────────────────────────────────────────────────────────────────┐
│                 VALIDATION FREQUENCY                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  For a typical 5-step implementation task:                     │
│                                                                 │
│  Phase 1 (Intake):        1 validation   (V1)                  │
│  Phase 2 (Planning):      3 validations  (V2, V3, V4)          │
│  Phase 3 (Implementation): 10 validations (V5, V6 × 5 steps)   │
│  Phase 4 (Quality Gate):  1 validation   (V7)                  │
│  Phase 5 (Commit):        2 validations  (V8, V9)              │
│  Phase 6 (Completion):    1 validation   (V10)                 │
│  ─────────────────────────────────────────                     │
│  Total:                   18 validations                       │
│                                                                 │
│  Ratio: ~3 validations per Orchestrator action                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Error Handling & Recovery

### Validation Failures

```
┌─────────────────────────────────────────────────────────────────┐
│              VALIDATION FAILURE RESPONSES                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  CLARIFY / REFINE:                                             │
│  → Orchestrator revises and resubmits for validation           │
│  → Maximum 2 revision attempts before escalation               │
│                                                                 │
│  REJECT / ROLLBACK:                                            │
│  → Orchestrator undoes recent changes                          │
│  → Returns to last known good state                            │
│  → Re-plans from that point                                    │
│                                                                 │
│  ESCALATE:                                                     │
│  → Orchestrator pauses autonomous execution                    │
│  → Presents situation to user with Validator's concerns        │
│  → Waits for user decision                                     │
│                                                                 │
│  PAUSE:                                                        │
│  → Execution halted                                            │
│  → State preserved                                             │
│  → Awaiting input                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Continuous Failure Detection

If Validator rejects 3+ consecutive actions:

```
CIRCUIT BREAKER TRIGGERED

Multiple consecutive validation failures detected.
This may indicate:
- Fundamental misunderstanding of requirements
- Systemic issue with approach
- Need for human intervention

Action: FULL STOP - Escalate to user with complete context
```

---

## Workflow Diagram (Complete)

```
                                    START
                                      │
                                      ▼
                            ┌─────────────────┐
                            │  Task Received  │
                            │  (User or ADO)  │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                         ┌──│ V1: Intake      │──┐
                         │  │    Validation   │  │
                    CLARIFY └────────┬────────┘  ESCALATE
                         │           │           │
                         │       PROCEED         │
                         │           │           │
                         │           ▼           │
                         │  ┌─────────────────┐  │
                         │  │ Delegate to     │  │
                         │  │ Worker: Analyze │  │
                         │  └────────┬────────┘  │
                         │           │           │
                         │           ▼           │
                         │  ┌─────────────────┐  │
                         └──│ V2: Delegation  │  │
                            │    Validation   │──┘
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ Worker Analyzes │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                         ┌──│ V3: Analysis    │──┐
                         │  │    Validation   │  │
                    REVISE  └────────┬────────┘  REJECT
                         │           │           │
                         │        ACCEPT         │
                         │           │           │
                         │           ▼           │
                         │  ┌─────────────────┐  │
                         │  │ Create Plan     │  │
                         │  └────────┬────────┘  │
                         │           │           │
                         │           ▼           │
                         │  ┌─────────────────┐  │
                         └──│ V4: Plan        │──┘
                            │    Validation   │
                            └────────┬────────┘
                                     │
                                     ▼
                    ┌────────────────────────────────┐
                    │     IMPLEMENTATION LOOP        │
                    │  ┌──────────────────────────┐  │
                    │  │ For each step:           │  │
                    │  │  ├─ V5: Validate delega- │  │
                    │  │  │      tion             │  │
                    │  │  ├─ Worker executes      │  │
                    │  │  └─ V6: Validate result  │  │
                    │  └──────────────────────────┘  │
                    └───────────────┬────────────────┘
                                    │
                                    ▼
                            ┌─────────────────┐
                            │ Critic Reviews  │
                            │ (Quality Gate)  │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                         ┌──│ V7: Critic      │──┐
                         │  │    Validation   │  │
                   CHALLENGE └────────┬────────┘ DEEPER
                         │           │           REVIEW
                         │       ACCEPT          │
                         │           │           │
                         │           ▼           │
                         │  ┌─────────────────┐  │
                         │  │ Prepare Commit  │  │
                         │  └────────┬────────┘  │
                         │           │           │
                         │           ▼           │
                         │  ┌─────────────────┐  │
                         └──│ V8: Commit      │──┘
                            │    Validation   │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ Execute Commit  │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ V9: Post-Commit │
                            │    Validation   │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ Close Task      │
                            │ Update ADO      │
                            └────────┬────────┘
                                     │
                                     ▼
                            ┌─────────────────┐
                            │ V10: Completion │
                            │    Validation   │
                            └────────┬────────┘
                                     │
                                     ▼
                                    END
```

---

## Validator Review & Recommendations

**Review Date:** 2026-01-31
**Validator Score:** 0.65 (Below autonomous approval threshold)
**Recommendation:** Revise workflow based on concerns

### Concerns Raised

1. **Validation Theater** - 3 validations per action may lead to rubber-stamping without substantive review
2. **Alert Fatigue** - Excessive checkpoints cause standards to drift toward approval bias
3. **Missing Rollback Checkpoint** - No validation for "should we rollback?"
4. **Escalation Pathway Gaps** - Unclear what happens at 0.65-0.69 confidence
5. **Batch vs Individual** - Unclear if validating micro-decisions or cumulative state

### Validator's Recommendations (Incorporated Below)

#### Recommendation 1: Risk-Tiered Validation

Instead of validating every task individually, batch by risk profile:

```
┌─────────────────────────────────────────────────────────────────┐
│                    RISK-TIERED VALIDATION                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  AUTO-APPROVE TIER (confidence > 0.85):                        │
│  ─────────────────────────────────────                         │
│  • Read operations                                             │
│  • Status checks                                               │
│  • Safe queries                                                │
│  • Documentation updates                                       │
│  → Skip individual validation, log only                        │
│                                                                 │
│  BATCH VALIDATION TIER (0.70 - 0.85):                         │
│  ─────────────────────────────────────                         │
│  • Related tasks validated as a group                          │
│  • Example: all analysis tasks together                        │
│  → Validate plan, not each micro-step                          │
│                                                                 │
│  INDIVIDUAL VALIDATION TIER (< 0.70):                         │
│  ─────────────────────────────────────                         │
│  • Write operations                                            │
│  • Config changes                                              │
│  • Anything irreversible                                       │
│  • Security-sensitive actions                                  │
│  → Full validation checkpoint required                         │
│                                                                 │
│  Estimated reduction: 40-60% fewer validation calls            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Recommendation 2: Pre-Flight Snapshot Checkpoint

Before ANY modifications begin:

```
┌─────────────────────────────────────────────────────────────────┐
│                PRE-FLIGHT SNAPSHOT (V0)                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  REQUIRED CAPTURES:                                            │
│  ──────────────────                                            │
│  □ Current git state (branch, commit, status)                  │
│  □ Build state (last known good)                               │
│  □ Test state (baseline pass/fail)                             │
│                                                                 │
│  ROLLBACK READINESS:                                           │
│  ──────────────────                                            │
│  □ Rollback procedure verified (not just documented)           │
│  □ Estimated rollback time calculated                          │
│  □ Abort criteria clearly defined                              │
│                                                                 │
│  GATE: Cannot proceed until all boxes checked                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Recommendation 3: Anomaly Detection over Post-Task Validation

```
┌─────────────────────────────────────────────────────────────────┐
│            ANOMALY DETECTION (Replaces Post-Task V6)           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  INSTEAD OF:                                                   │
│  Validate every task after completion (validation theater)     │
│                                                                 │
│  DO THIS:                                                      │
│  ────────                                                      │
│  1. Validate the PLAN upfront (comprehensive)                  │
│  2. Execute steps with automated monitoring                    │
│  3. Anomaly detection runs continuously:                       │
│     • Build status changes                                     │
│     • Test failures appear                                     │
│     • Error rate spikes                                        │
│     • Unexpected file changes                                  │
│  4. Alert Validator ONLY if anomalies exceed threshold         │
│                                                                 │
│  BENEFIT: ~70% reduction in alert fatigue                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Recommendation 4: Explicit Human Escalation Gates

```
┌─────────────────────────────────────────────────────────────────┐
│              MANDATORY HUMAN REVIEW TRIGGERS                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  AUTO-ESCALATE TO HUMAN (no Validator discretion):             │
│  ─────────────────────────────────────────────                 │
│  • Validator confidence < 0.50                                 │
│  • Any architectural change                                    │
│  • Any security-related task                                   │
│  • Cumulative risk score > threshold                           │
│  • 3+ consecutive validation rejections (circuit breaker)      │
│                                                                 │
│  VALIDATOR DISCRETION ZONE (0.50 - 0.70):                     │
│  ─────────────────────────────────────────                     │
│  • Validator decides: proceed with caution OR escalate         │
│  • Must document reasoning either way                          │
│                                                                 │
│  PRINCIPLE: Remove judgment calls about WHEN to escalate       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Recommendation 5: Progressive Autonomy Levels

```
┌─────────────────────────────────────────────────────────────────┐
│               PROGRESSIVE AUTONOMY LEVELS                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  LEVEL 1 - SUPERVISED (New task types, unfamiliar codebase)   │
│  ─────────────────────────────────────────────────────────     │
│  • Full validation at every checkpoint                         │
│  • Human confirmation at key gates                             │
│  • All decisions logged for review                             │
│                                                                 │
│  LEVEL 2 - GUIDED (Familiar patterns, moderate complexity)    │
│  ─────────────────────────────────────────────────────────     │
│  • Risk-tiered validation (auto-approve safe actions)          │
│  • Human checkpoint only at commit                             │
│  • Anomaly-based alerting                                      │
│                                                                 │
│  LEVEL 3 - AUTONOMOUS (Routine tasks, established patterns)   │
│  ─────────────────────────────────────────────────────────     │
│  • Validate plan only, not individual steps                    │
│  • Human notified at completion (not approval)                 │
│  • Circuit breaker for anomalies                               │
│                                                                 │
│  LEVEL ASSIGNMENT: Based on task type, codebase familiarity,  │
│  and historical success rate                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Revised Checkpoint Summary

Based on Validator recommendations, the original 10 checkpoints are revised:

| Original | Revised | Change |
|----------|---------|--------|
| - | **V0: Pre-Flight** | NEW - Snapshot and rollback readiness |
| V1: Intake | V1: Intake | Keep - Critical gate |
| V2: Delegation | Merged into V4 | REMOVED - Validation theater |
| V3: Analysis | Merged into V4 | REMOVED - Validation theater |
| V4: Plan | **V2: Plan** | Keep - Validate plan comprehensively |
| V5: Step Delegation | Anomaly detection | REPLACED - Alert only on anomaly |
| V6: Step Result | Anomaly detection | REPLACED - Alert only on anomaly |
| V7: Critic Review | **V3: Quality Gate** | Keep - Critical gate |
| V8: Commit | **V4: Commit** | Keep - Critical gate |
| V9: Post-Commit | Anomaly detection | REPLACED - Automated check |
| V10: Completion | **V5: Completion** | Keep - Closure validation |

**Revised total: 6 checkpoints** (down from 10)
**Estimated validation reduction: 50-60%**

---

*Workflow Version: 1.2.0*
*Author: Orchestrator Claude*
*Reviewed by: Validator Claude (Score: 0.65 → 0.85 after revisions)*
*Status: ACTIVE - Test-Driven Improvement integrated*
