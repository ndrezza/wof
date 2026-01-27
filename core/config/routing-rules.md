# Workload Routing Rules

> Comprehensive guidelines for routing tasks between Worker-Heavy and Worker-Lite

## Overview

This document defines when tasks should be routed to Worker-Lite (local, fast, free) versus Worker-Heavy (Azure, powerful, cost).

| Worker | Typical Use | Characteristics |
|--------|-------------|-----------------|
| **Worker-Lite** | Simple tasks | Fast, lower cost, smaller context |
| **Worker-Heavy** | Complex tasks | Powerful, larger context, higher capability |

---

## 1. Task Classification Criteria

### T1 - Lightweight (-> Worker-Lite)

**Complexity Indicators:**
- Single-step operations
- No cross-file dependencies
- Pattern matching without semantic understanding
- Deterministic transformations
- Estimated completion < 10 seconds

**Context Requirements:**
- Input + expected output < 16K tokens
- No need for full codebase understanding
- Self-contained queries

**Quality Requirements:**
- Acceptable to have occasional minor errors
- Human will review output
- Not production-critical

**Examples:**
- "Find all files containing `IJobService`"
- "Format this JSON"
- "What's the namespace for this class?"
- "List all controller endpoints"

### T2+ - Complex (-> Worker-Heavy)

**Complexity Indicators:**
- Multi-step reasoning required
- Cross-file understanding needed
- Architectural awareness required
- Code generation > 50 lines
- Test writing
- Refactoring with semantic preservation

**Context Requirements:**
- Needs understanding of patterns, conventions
- May require reading multiple related files
- Benefits from larger context window (200K)

**Quality Requirements:**
- Must be production-ready
- Needs to compile/pass linting
- Must follow project conventions
- Security-conscious

**Examples:**
- "Implement the IJobExecutor interface"
- "Write unit tests for JobService"
- "Refactor this service to use dependency injection"
- "Debug why jobs aren't being scheduled"

---

## 2. Routing Decision Tree

```
                    +---------------------+
                    |   Incoming Task     |
                    +----------+----------+
                               |
                    +----------v----------+
                    | Is Worker-Lite      |
                    | available?          |
                    +----------+----------+
                               |
                   +-----------+-----------+
                   | NO                YES |
                   v                       v
          +----------------+    +------------------+
          | Route ALL to   |    | Check Task Type  |
          | Worker-Heavy   |    +--------+---------+
          +----------------+             |
                              +----------+----------+
                              |                     |
                    +---------v---------+ +--------v--------+
                    | Code Generation?  | | Search/Format?  |
                    | Testing?          | | Navigation?     |
                    | File Write/Edit?  | | Simple Q&A?     |
                    | Research?         | | Validation?     |
                    +---------+---------+ +--------+--------+
                              |                    |
                              v                    v
                    +-----------------+  +-----------------+
                    |  Worker-Heavy   |  |  Worker-Lite    |
                    |  (T2+ tasks)    |  |  (T1 tasks)     |
                    +-----------------+  +--------+--------+
                                                  |
                                        +---------v---------+
                                        | Quality Check     |
                                        | (on completion)   |
                                        +---------+---------+
                                                  |
                                    +-------------+-------------+
                                    |                           |
                              +-----v-----+               +-----v-----+
                              | PASS      |               | FAIL      |
                              | (Accept)  |               | (Escalate)|
                              +-----------+               +-----+-----+
                                                                |
                                                                v
                                                      +-----------------+
                                                      |  Worker-Heavy   |
                                                      |  (Retry)        |
                                                      +-----------------+
```

---

## 3. Task Type Mapping

| Task Type | Worker | Tier | Rationale |
|-----------|--------|------|-----------|
| **Code Generation** | | | |
| New file/class | Heavy | T3 | Needs conventions, patterns |
| New function (< 20 lines) | Lite | T1 | Simple, contained |
| New function (> 20 lines) | Heavy | T2 | Complexity threshold |
| Boilerplate generation | Lite | T1 | Templated, predictable |
| **Code Modification** | | | |
| Single-line fix | Lite | T1 | Minimal context needed |
| Multi-line edit (2-10 lines) | Lite | T1 | Still contained |
| Multi-line edit (> 10 lines) | Heavy | T2 | Needs surrounding context |
| Refactoring | Heavy | T3 | Semantic preservation |
| Rename/replace (simple) | Lite | T1 | Deterministic |
| **Search/Navigation** | | | |
| Find files by pattern | Lite | T1 | Glob operation |
| Find by content (grep) | Lite | T1 | Grep operation |
| Understand code flow | Heavy | T2 | Semantic analysis |
| Find all usages | Lite | T1 | Pattern matching |
| **Documentation** | | | |
| Inline comments | Lite | T1 | Local context |
| Function docs | Lite | T1 | Single function |
| Architecture docs | Heavy | T3 | Cross-cutting |
| API documentation | Heavy | T2 | Multiple endpoints |
| **Testing** | | | |
| Run existing tests | Heavy | T2 | Execution + analysis |
| Write unit tests | Heavy | T2 | Needs code understanding |
| Write integration tests | Heavy | T3 | Cross-component |
| Validate syntax | Lite | T1 | Simple check |
| **Research/Exploration** | | | |
| Find implementation | Lite | T1 | Search operation |
| Understand architecture | Heavy | T3 | Deep analysis |
| Compare approaches | Heavy | T2 | Reasoning required |

---

## 4. Keyword-Based Routing

Quick routing based on task keywords:

### Route to Worker-Lite (T1)
```
search, find, glob, grep, list, format, lint,
navigate, locate, show, what, where, count
```

### Route to Worker-Heavy (T2+)
```
implement, create, write, fix, test, refactor,
architect, design, debug, optimize, security,
analyze, review, generate, build
```

### Always Worker-Heavy
```
deploy, production, critical, security,
comprehensive, thorough, all, entire
```

---

## 5. Fallback & Escalation Rules

### Automatic Escalation to Worker-Heavy

Worker-Lite should escalate when:

1. **Context Overflow**
   - Input exceeds 16K tokens
   - Task requires reading > 5 files
   - Response would exceed 4K tokens

2. **Capability Mismatch**
   - Task requires code execution
   - Task requires build/test verification
   - Task requires external API calls
   - Task requires file write operations

3. **Quality Failure**
   - Output doesn't compile/lint
   - Output missing required patterns
   - Confidence score < 0.6
   - Incomplete response

4. **Explicit Complexity**
   - Keywords: "architect", "design", "security", "debug", "optimize"
   - User requests "thorough" or "comprehensive"
   - Task involves multiple components

### Escalation Protocol

```yaml
escalation:
  max_lite_attempts: 1
  escalation_triggers:
    - error_response
    - quality_below_threshold
    - context_overflow
    - capability_mismatch
    - explicit_user_request
  on_escalate:
    - log_reason
    - preserve_lite_context  # Include what Lite attempted
    - route_to_heavy
    - note_escalation_reason
```

---

## 6. Quality Thresholds

### Accept Worker-Lite Output When:

| Criterion | Threshold | Measurement |
|-----------|-----------|-------------|
| Syntax validity | 100% | Linter pass |
| Response completeness | > 80% | All parts addressed |
| Formatting correctness | > 90% | Matches conventions |
| Confidence (self-reported) | > 0.7 | Model confidence |

### Retry with Worker-Heavy When:

| Criterion | Threshold | Action |
|-----------|-----------|--------|
| Syntax errors | Any | Immediate escalation |
| Incomplete response | < 60% complete | Escalate |
| Low confidence | < 0.5 | Escalate |
| User rejection | Any | Escalate |
| Timeout | > 30s | Escalate |

---

## 7. Cost/Performance Optimization

### Optimization Guidelines

1. **Speculative Execution (Default Strategy)**
   - For uncertain T1/T2 boundary tasks, try Lite first
   - Only 0.5-2s cost if it works
   - Escalate quickly if it fails (no retry on Lite)

2. **Batch Similar Tasks**
   - Group T1 tasks for Worker-Lite
   - Reduces context switching overhead

3. **Parallel When Appropriate**
   - Independent searches -> Lite in parallel
   - Code + tests -> Heavy (sequential, related)

4. **Skip Lite for Known Heavy Tasks**
   - Don't waste time on Lite for obvious T2+ tasks
   - Keywords trigger direct Heavy routing

### Performance Targets

| Metric | Lite Target | Heavy Target |
|--------|-------------|--------------|
| Response time | < 2s | < 10s |
| Success rate | > 85% | > 98% |
| Escalation rate | < 15% | N/A |
| Cost per task | $0 | ~$0.05-0.50 |

---

## 8. Quick Reference Card

```
+-------------------------------------------------------------+
|                    ROUTING QUICK REFERENCE                   |
+-------------------------------------------------------------+
|                                                             |
|  WORKER-LITE (Local)              WORKER-HEAVY (Azure)      |
|  -----------------------          ----------------------    |
|  * Find/Search/Grep               * Code generation         |
|  * List files/endpoints           * Write tests             |
|  * Format/Lint                    * Refactoring             |
|  * Simple Q&A                     * Debug/Fix bugs          |
|  * Navigate code                  * Architecture            |
|  * Syntax validation              * Security analysis       |
|  * Single-line edits              * Multi-file changes      |
|  * Boilerplate                    * Research/explore        |
|                                                             |
|  Context: < 16K tokens            Context: < 200K           |
|  Latency: 0.5-2s                  Latency: 2-8s             |
|  Cost: $0                         Cost: ~$0.015/1K          |
|                                                             |
+-------------------------------------------------------------+
|  ESCALATION TRIGGERS                                        |
|  * Context overflow (> 16K)                                 |
|  * Quality failure                                          |
|  * Capability mismatch                                      |
|  * Keywords: architect, design, security, debug, optimize   |
+-------------------------------------------------------------+
```

---

*Document provides routing guidelines for dual-worker architecture.*
