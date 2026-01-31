# Test-Driven Improvement Philosophy

## Core Principle

> "If you can't test it, you can't ship it."

No code reaches main without tests. No plan gets approved without a testing strategy. No work item closes without objective, repeatable validation. This is not optional - it's the foundation of trustworthy autonomous operation.

---

## The Three Laws

### Law 1: No Plan Without Test Strategy

Before any implementation begins, the testing approach must be defined:

```
┌─────────────────────────────────────────────────────────────────┐
│                    PLANNING GATE                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  BEFORE writing any code, answer:                              │
│                                                                 │
│  □ How will we know this works?                                │
│  □ What tests will prove correctness?                          │
│  □ What are the acceptance criteria?                           │
│  □ How do we test edge cases?                                  │
│  □ How do we test failure modes?                               │
│                                                                 │
│  If you cannot answer these questions, you are not ready       │
│  to implement. Go back and clarify requirements.               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Validator enforcement:** Reject any plan that lacks a concrete testing strategy.

### Law 2: No Commit Without Tests

Every commit to main must include tests that validate the changes:

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMMIT GATE                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  BEFORE committing, verify:                                    │
│                                                                 │
│  □ New code has corresponding tests                            │
│  □ Bug fixes include regression tests                          │
│  □ All existing tests still pass                               │
│  □ Coverage has not decreased                                  │
│  □ Tests are deterministic (not flaky)                         │
│                                                                 │
│  If tests don't exist, write them first.                       │
│  If tests can't be written, question the design.               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Validator enforcement:** Block any commit that lacks test coverage for changed code.

### Law 3: No Closure Without Repeatable Validation

Work items only close when they can be objectively, repeatedly validated:

```
┌─────────────────────────────────────────────────────────────────┐
│                    CLOSURE GATE                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  BEFORE closing a work item:                                   │
│                                                                 │
│  □ Acceptance criteria are met (objectively verifiable)        │
│  □ Tests pass on clean checkout                                │
│  □ Tests pass after rebuild                                    │
│  □ Tests can be run by anyone, anytime                         │
│  □ No manual verification required                             │
│                                                                 │
│  "It works on my machine" is not validation.                   │
│  "I tested it manually" is not validation.                     │
│  Automated, repeatable tests are validation.                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Validator enforcement:** Refuse to approve closure without passing automated tests.

---

## Test-First Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                 TEST-DRIVEN IMPROVEMENT CYCLE                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   1. UNDERSTAND                                                │
│      │  What are we trying to achieve?                         │
│      │  What does "done" look like?                            │
│      ▼                                                         │
│   2. DEFINE TESTS                                              │
│      │  Write failing tests first                              │
│      │  Tests define the acceptance criteria                   │
│      ▼                                                         │
│   3. IMPLEMENT                                                 │
│      │  Write minimal code to pass tests                       │
│      │  No gold-plating, no over-engineering                   │
│      ▼                                                         │
│   4. VERIFY                                                    │
│      │  All tests pass?                                        │
│      │  Coverage adequate?                                     │
│      │  No regressions?                                        │
│      ▼                                                         │
│   5. REFACTOR (if needed)                                      │
│      │  Improve code quality                                   │
│      │  Tests still pass?                                      │
│      ▼                                                         │
│   6. COMMIT                                                    │
│      │  Tests pass on clean build                              │
│      │  Ready for main                                         │
│      ▼                                                         │
│   7. VALIDATE CLOSURE                                          │
│         Can anyone reproduce the validation?                   │
│         → Yes: Close work item                                 │
│         → No: Back to step 2                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Pre-Commit Test Protocol

Every commit to main requires this protocol:

```bash
# 1. Clean state verification
git status                    # Must be clean or intentionally staged
git stash                     # Stash any unrelated changes

# 2. Full rebuild
dotnet clean                  # Or equivalent for your stack
dotnet build                  # Must succeed with 0 errors

# 3. Full test suite
dotnet test                   # ALL tests must pass
                              # Not just the new tests
                              # Not just the tests you think are related

# 4. Coverage check
dotnet test /p:CollectCoverage=true
                              # Coverage must not decrease
                              # New code must have coverage

# 5. Only then commit
git add [specific files]
git commit -m "..."
```

**Why all tests, every time?**

Because you don't know what you don't know. A "small change" in one file can break something in another. The only way to catch regressions is to run the full suite. Every time. No exceptions.

---

## Types of Tests Required

| Change Type | Required Tests |
|-------------|----------------|
| **New feature** | Unit tests + integration tests for the feature |
| **Bug fix** | Regression test that reproduces the bug |
| **Refactoring** | Existing tests must still pass (no new tests needed if behavior unchanged) |
| **API change** | Contract tests + migration tests |
| **Config change** | Validation tests for config parsing |
| **UI change** | Component tests or E2E tests |

---

## Validator's Testing Enforcement

Validator Claude must ask these questions at every checkpoint:

### At Planning (V2)
```
□ What is the testing strategy for this plan?
□ Can we write the tests before the implementation?
□ What are the acceptance criteria in testable terms?
□ How will we test edge cases and error conditions?
```

### At Implementation (during anomaly detection)
```
□ Are tests being written alongside the code?
□ Are the tests meaningful (not just for coverage)?
□ Do the tests actually test the requirements?
```

### At Quality Gate (V3 - Critic)
```
□ Did all tests pass? (run them, don't trust claims)
□ What is the actual coverage percentage?
□ Are there any skipped or ignored tests?
□ Are the tests deterministic?
```

### At Commit (V4)
```
□ Did the full test suite pass?
□ Did coverage decrease?
□ Are there any new warnings from tests?
□ Can these tests run on a clean checkout?
```

### At Closure (V5)
```
□ Can the validation be repeated by anyone?
□ Are the tests automated (no manual steps)?
□ Will these tests catch regressions in the future?
□ Is the work item objectively complete?
```

---

## What "Objectively Validatable" Means

A task is objectively validatable when:

1. **Automated** - A script or command can verify it
2. **Repeatable** - Same inputs produce same outputs, every time
3. **Independent** - Doesn't require specific environment or person
4. **Binary** - Pass or fail, no "mostly works"
5. **Documented** - Others know how to run the validation

### Examples

**Objectively validatable:**
- "All unit tests pass" ✓
- "Coverage is above 80%" ✓
- "API returns 200 for valid input" ✓
- "Build completes without errors" ✓

**NOT objectively validatable:**
- "Looks good to me" ✗
- "I tested it manually" ✗
- "Should work" ✗
- "Works on my machine" ✗

---

## The Testing Conversation

Orchestrator should proactively engage Validator on testing:

```
ORCHESTRATOR → VALIDATOR:

"I'm planning to implement [feature]. Before I proceed:
1. Here's my proposed testing strategy: [strategy]
2. These are the acceptance criteria: [criteria]
3. Am I missing any test cases?
4. Is this strategy sufficient for approval?"

VALIDATOR → ORCHESTRATOR:

"Your testing strategy is [adequate/insufficient].
- Missing: [gaps identified]
- Suggestions: [additional tests]
- Proceed when: [conditions]"
```

This conversation happens BEFORE implementation, not after.

---

## Worker Accountability

Workers are not done until tests exist and pass:

```
┌─────────────────────────────────────────────────────────────────┐
│               WORKER TASK COMPLETION CRITERIA                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  A Worker task is NOT complete when:                           │
│  ✗ "Code is written"                                           │
│  ✗ "It compiles"                                               │
│  ✗ "It seems to work"                                          │
│                                                                 │
│  A Worker task IS complete when:                               │
│  ✓ Code is written                                             │
│  ✓ Tests are written                                           │
│  ✓ Tests pass                                                  │
│  ✓ Coverage is adequate                                        │
│  ✓ Build is clean                                              │
│                                                                 │
│  Validator keeps Workers busy until ALL criteria are met.      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Continuous Validation

As the solution grows, tests must continuously pass:

```
┌─────────────────────────────────────────────────────────────────┐
│              CONTINUOUS VALIDATION PRINCIPLE                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Every change → Run ALL tests                                  │
│  Every commit → Run ALL tests                                  │
│  Every PR     → Run ALL tests                                  │
│  Every merge  → Run ALL tests                                  │
│                                                                 │
│  "But it's just a small change..."  → Run ALL tests            │
│  "But only this file changed..."    → Run ALL tests            │
│  "But I already tested it..."       → Run ALL tests            │
│                                                                 │
│  There is no exception. Tests are cheap. Bugs are expensive.   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Anti-Patterns

### "We'll add tests later"
No. Tests come first or with the code. "Later" means "never."

### "This is too simple to test"
If it's too simple to test, it's too simple to break. Add a test anyway - it's documentation.

### "Tests slow us down"
Tests slow down the first delivery. They speed up every delivery after that by catching regressions.

### "The tests are flaky, so I skipped them"
Fix the flaky tests. Don't skip them. Flaky tests are a bug in your test, not an excuse.

### "Manual testing is enough"
Manual testing doesn't scale, isn't repeatable, and gets skipped under pressure. Automate or die.

---

## Summary

```
┌─────────────────────────────────────────────────────────────────┐
│           TEST-DRIVEN IMPROVEMENT - SUMMARY                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. No plan without test strategy                              │
│  2. No implementation without tests                            │
│  3. No commit without passing tests                            │
│  4. No closure without repeatable validation                   │
│  5. Run ALL tests before EVERY commit to main                  │
│                                                                 │
│  Validator enforces these laws without exception.              │
│  Orchestrator consults Validator on testing strategy.          │
│  Workers deliver code WITH tests, not code then tests.         │
│                                                                 │
│  Trust is built through objective, repeatable validation.      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

*Philosophy Version: 1.0.0*
*Status: ACTIVE - Mandatory for all WOF operations*
