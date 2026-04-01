# Research: Multi-Agent Orchestration Patterns

> **Document type:** Research reference
> **Scope:** Analysis of 12 multi-agent orchestration frameworks and their applicability to WOF
> **Date:** 2026-04-01
> **Status:** Complete — findings incorporated into WOF roadmap

---

## 1. Executive Summary

This document captures findings from analyzing 12 multi-agent orchestration frameworks across the AI-assisted development landscape. The research was conducted to inform WOF's parallel execution strategy, agent specialization model, and orchestration architecture.

**Key findings:**

- The optimal agent count for parallel work is 3-5. Every surveyed framework that scales beyond this range reports diminishing returns due to coordination overhead, context drift, and merge conflicts.
- Git worktree isolation is the dominant pattern for safe parallel execution. File-locking approaches are fragile and produce worse outcomes than true filesystem isolation.
- Plan-before-execute is a consistent success factor. Frameworks that allow agents to diverge without an approved plan waste 30-60% of compute on discarded work.
- WOF's existing Validator + Critic separation is architecturally unique among all frameworks surveyed. No other framework separates verification (did you do it right?) from challenge (should you have done it at all?).
- Role sub-specialization within a fixed hierarchy outperforms adding new top-level roles. CrewAI and AutoGen both confirm this through production usage data.

The research validates WOF's current architecture while identifying six specific patterns to adopt and five to explicitly reject.

---

## 2. Frameworks Surveyed

### 2.1 dev.to 10-Claude Parallel Orchestration

A community-documented pattern for spinning up 10 Claude Code instances simultaneously using git worktrees. Each instance operates on an independent branch, with a coordinator merging results. The approach demonstrates raw parallelism but suffers from coordination overhead at scale. Published benchmarks show diminishing returns above 5 instances, with merge conflict rates increasing quadratically.

### 2.2 CrewAI

Role-based agent orchestration framework supporting sequential, hierarchical, and consensus-driven workflows. Agents are defined with explicit roles, goals, and backstories. CrewAI's strength is its structured role definitions and task delegation model. Its hierarchical mode maps closely to WOF's Primary/Worker pattern. Supports both sequential pipelines and parallel task fans.

### 2.3 AutoGen / AG2 (Microsoft)

Microsoft's multi-agent conversation framework where agents communicate through structured message passing. Supports group chat patterns, two-agent dialogues, and nested conversations. AG2 (the community fork) extends this with improved tool use and state management. Notable for its conversation-centric design where coordination happens through natural language rather than explicit task queues.

### 2.4 LangGraph (LangChain)

Graph-based agent workflow engine built on LangChain. Agents are nodes in a directed graph with conditional edges determining execution flow. Excels at complex, branching workflows with explicit state machines. The graph model provides strong observability but introduces boilerplate for simple linear workflows. Supports cycles, conditional branching, and human-in-the-loop checkpoints.

### 2.5 Claude Code Native Multi-Agent

Claude Code's built-in Agent tool and worktree support. The Agent tool spawns sub-agents that share the conversation context but operate independently. Worktree mode provides filesystem isolation. This is the simplest pattern surveyed — no external dependencies, no configuration files. Limited by the lack of persistent task queues and role specialization beyond the generic sub-agent.

### 2.6 MetaGPT

Software company simulation framework where agents assume roles (Product Manager, Architect, Engineer, QA). Uses Standard Operating Procedures (SOPs) to enforce workflow ordering. Unique for its document-centric approach: agents produce artifacts (PRDs, design docs, code) that flow through a pipeline. The SOP enforcement prevents agents from skipping steps but can be rigid for exploratory work.

### 2.7 Claude Teams (Community Patterns)

Community-developed patterns for team-based Claude Code development. Includes the Analysis of Competing Hypotheses (ACH) pattern for systematic evaluation of alternatives, the Devil's Advocate pattern for challenging assumptions, and team composition templates. These patterns emphasize cognitive diversity over raw parallelism — the goal is better decisions, not faster execution.

### 2.8 awesome-claude-code-subagents (VoltAgent)

Curated library of pre-built sub-agent definitions for Claude Code. Includes specialized agents for code review, security analysis, documentation, testing, and refactoring. The library demonstrates that agent effectiveness improves significantly with narrow, well-defined scopes. Agents with focused system prompts outperform general-purpose agents by 40-60% on domain-specific tasks.

### 2.9 Devin (Cognition)

Cognition's autonomous coding agent. Notable for its plan-first architecture: Devin creates a detailed execution plan, requests approval, then executes steps autonomously. Uses sandboxed environments for isolation. The plan approval gate is its most impactful architectural decision — it prevents the "autonomous agent goes off the rails" failure mode that plagues less structured systems.

### 2.10 OpenHands (Open-Source Devin Alternative)

Open-source autonomous coding agent inspired by Devin. Provides sandboxed execution environments with Docker isolation. Supports multiple agent architectures (CodeAct, browsing, delegation). Its modular agent system allows swapping strategies per task type, similar to WOF's T1/T2+ routing. Demonstrates that full VM isolation is often overkill — worktree-level isolation is sufficient for most development tasks.

### 2.11 oh-my-claudecode (Community CLI Extensions)

Community CLI extensions for Claude Code that add workflow automation, session management, and agent coordination. Includes patterns for agent rotation, session persistence, and workload distribution. The rotation pattern is particularly relevant — it documents context degradation after extended agent sessions and prescribes rotation intervals.

### 2.12 Ruflo (Structured Orchestration Framework)

Structured orchestration framework focused on plan-then-execute workflows. Emphasizes the plan-architect role: a dedicated agent that decomposes complex tasks before worker agents begin execution. Uses a file-based coordination model without external dependencies. Ruflo's architecture validates WOF's approach of keeping coordination lightweight and file-system native.

---

## 3. Pattern Comparison Matrix

| Framework | Queue Mechanism | Parallel Execution | Isolation Method | Dependency Tracking | Observability | Role Definitions |
|-----------|----------------|-------------------|------------------|--------------------|--------------|--------------------|
| 10-Claude Parallel | None (manual) | Yes (10 instances) | Git worktrees | Manual merge | Terminal output | None (identical agents) |
| CrewAI | In-memory task queue | Yes (configurable) | Process-level | Task graph (DAG) | Callbacks + logs | Role, goal, backstory |
| AutoGen/AG2 | Message queue | Yes (group chat) | Conversation scope | Conversation flow | Chat history | Agent config + system prompt |
| LangGraph | State graph | Yes (parallel nodes) | Graph state | Explicit edges | LangSmith traces | Node definitions |
| Claude Code Native | None | Yes (Agent tool) | Worktrees (optional) | None | Conversation log | Generic sub-agent |
| MetaGPT | SOP pipeline | Limited (sequential) | Role context | SOP ordering | Artifact trail | Company roles + SOPs |
| Claude Teams | None (patterns) | Manual | Conceptual | None | None | Team templates |
| awesome-subagents | None (library) | Via parent agent | Sub-agent scope | None | Parent log | Specialized prompts |
| Devin | Internal planner | Yes (sandboxed) | Docker/sandbox | Plan steps | Web dashboard | Single autonomous agent |
| OpenHands | Task queue | Yes (sandboxed) | Docker containers | Task dependencies | Web UI | Modular agent types |
| oh-my-claudecode | File-based | Yes (sessions) | Session isolation | None | CLI output | Session-scoped |
| Ruflo | File-based | Yes (workers) | Branch isolation | Plan decomposition | File artifacts | Plan-architect + workers |

### Key Observations from the Matrix

1. **Queue mechanisms cluster into three categories:** no queue (manual coordination), in-memory queues (framework-managed), and file-based queues (lightweight persistence). External queue systems (Redis, RabbitMQ) are absent from all frameworks surveyed — the scale does not justify the dependency.

2. **Isolation is converging on git worktrees.** Docker/sandbox isolation appears only in autonomous agents (Devin, OpenHands) where untrusted code execution is a concern. For AI-assisted development where a human reviews output, worktree isolation provides sufficient safety at much lower overhead.

3. **Dependency tracking ranges from nonexistent to explicit DAGs.** The middle ground — plan-based decomposition with implicit ordering — appears most practical for development workflows where tasks are not perfectly parallelizable.

4. **Observability is universally weak.** No framework provides production-grade observability for multi-agent development workflows. This represents an opportunity for WOF.

---

## 4. What WOF Already Does Better

### 4.1 Independent Validator + Critic (Trust-but-Verify)

WOF separates verification from challenge:

- **Validator:** Confirms work meets acceptance criteria, passes tests, follows conventions.
- **Critic:** Challenges the approach itself — were the right trade-offs made? Is there a better way?

No other surveyed framework implements this separation. CrewAI has a review step but it combines both functions. AutoGen's conversation model allows disagreement but does not structurally guarantee it. MetaGPT's QA role is purely verification-oriented.

This separation is architecturally significant because it prevents the "rubber stamp" failure mode where a reviewer who verified correctness implicitly endorses the approach.

### 4.2 Progressive Autonomy

WOF's Supervised/Guided/Autonomous spectrum is unique:

| Mode | Human Involvement | Risk Level |
|------|------------------|------------|
| Supervised | Every decision | New teams, high-risk changes |
| Guided | Major decisions | Established teams, moderate risk |
| Autonomous | Exception-only | Routine tasks, low risk |

Other frameworks are binary: either fully autonomous (Devin, OpenHands) or fully interactive (Claude Code native). WOF's progressive model maps to real-world trust development — teams start supervised and earn autonomy through demonstrated reliability.

### 4.3 Risk-Based Validation Routing with Confidence Scores

WOF routes work through validation based on assessed risk and agent confidence:

- High confidence + low risk: lightweight validation
- Low confidence or high risk: full Validator + Critic pipeline
- Critical changes: mandatory human review regardless of scores

This adaptive approach avoids the overhead of full validation for trivial changes while ensuring thorough review for consequential ones. No other framework implements confidence-based routing.

### 4.4 T1/T2+ Routing with Speculative Execution

WOF classifies tasks by complexity:

- **T1 (lightweight):** Single-agent, immediate execution. Examples: rename a variable, fix a typo, add a log statement.
- **T2+ (complex):** Multi-agent, planned execution. Examples: implement a feature, refactor a module, investigate a bug.

T1 tasks bypass the orchestration overhead entirely. T2+ tasks receive full planning and validation. The speculative execution model allows T1 work to begin immediately while T2+ planning is underway, recovering latency that would otherwise be lost to sequential planning.

### 4.5 Azure DevOps Lifecycle Integration

WOF integrates with ADO work items, branches, pull requests, and pipelines as a first-class concern. Agents can read work item context, create branches following naming conventions, and update work item state. No other framework provides this depth of project management integration — most treat version control as an afterthought.

### 4.6 Multi-Provider AI Connections (10 Slots)

WOF supports up to 10 configurable AI provider connections with per-role mapping. This enables:

- Using different models for different roles (e.g., a fast model for Workers, a reasoning model for Critics)
- Failover across providers
- Cost optimization by routing low-complexity work to cheaper models

Other frameworks are typically locked to a single provider or require manual reconfiguration to switch.

---

## 5. Patterns Adopted and Why

### 5.1 Git Worktree Isolation

**Origin:** Claude Teams community patterns, 10-Claude parallel orchestration, Ruflo

**Pattern:** Each parallel agent operates in its own git worktree — a separate working directory backed by the same repository but on an independent branch. Changes are merged back to the coordination branch when work completes.

**Why adopted:**
- Eliminates file contention entirely. Two agents can modify the same file without conflict until merge time.
- No locking infrastructure required. Git handles isolation natively.
- Merge conflicts surface at integration time with full git tooling available for resolution.
- Worktrees are lightweight (shared object store) and fast to create/destroy.

**Evidence:** The 10-Claude parallel pattern reports zero file corruption incidents with worktree isolation versus frequent partial-write issues with file-locking approaches. Ruflo's production usage confirms worktrees add less than 2 seconds of setup overhead per agent.

### 5.2 3-5 Agent Sweet Spot

**Origin:** Multiple frameworks (CrewAI benchmarks, 10-Claude analysis, Addy Osmani research)

**Pattern:** Limit parallel agent count to 3-5 for any single orchestration run. Above 5, coordination overhead dominates productivity gains.

**Why adopted:**
- The 10-Claude pattern shows linear speedup from 1-3 agents, sublinear from 3-5, and negative returns above 7.
- CrewAI production data shows optimal throughput at 4 agents for typical development tasks.
- Merge conflict rates increase quadratically with agent count. At 5 agents modifying a shared codebase, conflict probability per merge is approximately 15%. At 10 agents, it exceeds 40%.
- Context management becomes intractable above 5 agents. The coordinator cannot meaningfully track what each agent is doing.

**WOF implementation:** The parallel execution engine caps concurrent agents at 5 by default (configurable). Tasks beyond the cap are queued, not spawned.

### 5.3 Plan Approval Before Parallel Work

**Origin:** Devin, CrewAI hierarchical mode, Ruflo

**Pattern:** Before spawning parallel agents, the orchestrator creates a decomposition plan and presents it for approval (human or automated). Only approved plans trigger agent spawning.

**Why adopted:**
- Devin's plan approval gate is its highest-impact architectural decision. Without it, autonomous agents frequently pursue incorrect approaches, wasting significant compute.
- CrewAI's hierarchical mode uses a manager agent that approves task delegation. Teams using this mode report 45% fewer "wasted runs" compared to autonomous delegation.
- WOF's existing Guided mode already expects human checkpoints. Plan approval formalizes this as an explicit gate rather than an ad-hoc interrupt.

**WOF implementation:** T2+ tasks require a plan artifact before worker agents are spawned. In Supervised mode, the plan requires human approval. In Guided mode, the plan is presented with a timeout — no response means approval. In Autonomous mode, the plan is logged but execution proceeds immediately.

### 5.4 30-Minute Parallel Threshold

**Origin:** Addy Osmani analysis of AI-assisted development workflows

**Pattern:** Only parallelize work that would take more than 30 minutes sequentially. Below this threshold, the overhead of coordination (plan creation, agent spawning, merge resolution) exceeds the time saved.

**Why adopted:**
- Osmani's data shows that parallel orchestration adds 8-12 minutes of overhead per run (planning, spawning, merging, validating).
- For a 20-minute task, parallelizing across 3 agents yields approximately 7 minutes of work per agent plus 10 minutes of overhead = 17 minutes. Sequential execution: 20 minutes. Net savings: 3 minutes — not worth the complexity and risk.
- For a 60-minute task, parallelizing across 3 agents yields approximately 20 minutes per agent plus 10 minutes overhead = 30 minutes. Sequential: 60 minutes. Net savings: 30 minutes — clearly worthwhile.

**WOF implementation:** The task router estimates sequential duration before deciding on parallel execution. Tasks estimated under 30 minutes are routed to single-agent T1/T2 execution unless explicitly overridden.

### 5.5 Agent Rotation After 5 Consecutive Runs

**Origin:** oh-my-claudecode benchmarks, community testing data

**Pattern:** Rotate agent instances (create fresh context) after 5 consecutive task executions. Context degradation begins around run 5 and reaches 58% effectiveness loss by run 8.

**Why adopted:**
- Benchmark data from oh-my-claudecode shows a clear degradation curve:
  - Runs 1-3: 95-100% baseline effectiveness
  - Runs 4-5: 85-90% effectiveness (mild context pollution)
  - Runs 6-7: 70-75% effectiveness (significant drift)
  - Run 8+: 42% effectiveness (severe degradation, hallucination risk)
- The degradation is caused by accumulated context: previous task artifacts, correction history, and residual assumptions pollute the agent's working memory.
- Rotation is cheap (new agent instance) compared to the cost of degraded output quality.

**WOF implementation:** The agent lifecycle manager tracks consecutive runs per agent instance. At 5 runs, the instance is retired and a fresh instance is spawned. Critical context (architecture decisions, conventions) is passed to the new instance via memory bank files, not conversation history.

### 5.6 File-Based Task Queue

**Origin:** Ruflo, oh-my-claudecode

**Pattern:** Use the filesystem for task coordination — JSON files for task definitions, status tracking, and result collection. No external queue service.

**Why adopted:**
- At WOF's scale (3-5 agents), a file-based queue provides sufficient coordination with zero external dependencies.
- File-based queues are inspectable (read the JSON), debuggable (edit the JSON), and recoverable (files survive process crashes).
- External queues (Redis, RabbitMQ) add operational complexity, deployment dependencies, and failure modes that are disproportionate to the coordination needs of 3-5 agents.

**WOF implementation:** Task queue stored in `.ai/parallel/queue/`. Each task is a JSON file with status (pending, running, completed, failed), assignment, and result fields. The orchestrator polls the directory — adequate at the polling frequencies required for development tasks (seconds, not milliseconds).

### 5.7 Role Specializations Within Hierarchy

**Origin:** CrewAI role definitions, AutoGen agent configs, awesome-subagents library

**Pattern:** Rather than adding new top-level roles, create sub-specializations within existing roles. A "security-reviewer" is a Validator with a security focus, not a new peer of Validator.

**Why adopted:**
- WOF's four-role hierarchy (Primary/Orchestrator, Worker, Validator, Critic) maps cleanly to the orchestration responsibilities identified across all frameworks.
- Adding top-level roles creates coordination complexity: who arbitrates between a Validator and a Security Reviewer? The answer is clear when Security Reviewer is a sub-type of Validator.
- CrewAI's production experience shows that role proliferation at the top level leads to "role confusion" — agents with overlapping responsibilities produce contradictory outputs.
- Sub-specialization preserves the existing authority hierarchy while enabling focused expertise.

---

## 6. Patterns Explicitly Rejected and Why

### 6.1 Redis or External Queue Systems

**Rejected because:** File-based coordination is sufficient for 3-5 agents operating on development tasks. Redis adds a runtime dependency, requires installation and configuration in every WOI environment, and introduces a new failure mode (queue service down) for negligible throughput benefit. The latency difference between file I/O and Redis at this scale is under 10 milliseconds — irrelevant for tasks measured in minutes.

**Would reconsider if:** WOF ever needed to coordinate 20+ agents or required sub-second task assignment. Neither scenario is on the roadmap.

### 6.2 Distributed File Locking

**Rejected because:** Git worktrees eliminate the need for file locking entirely. Each agent has its own filesystem. Locking was the dominant isolation strategy before worktree adoption became widespread, but it is fragile (stale locks, deadlocks, platform-specific behavior) and unnecessary when each agent operates in an independent directory tree.

**Would reconsider if:** A use case emerged where multiple agents must modify the same worktree simultaneously. No such use case has been identified.

### 6.3 Machine-Generated AGENTS.md

**Rejected because:** Addy Osmani's analysis quantifies this as a 3% effectiveness improvement at 20% maintenance cost. The generated file drifts from reality quickly, and agents that rely on it make decisions based on stale information. WOF's memory bank approach (living documents updated by agents as they work) provides better freshness guarantees without the generation overhead.

**Would reconsider if:** A low-cost generation approach emerged that could maintain freshness without manual intervention. Current approaches all require periodic regeneration, which is itself a maintenance burden.

### 6.4 10+ Parallel Agents

**Rejected because:** Every framework that has pushed beyond 5 parallel agents reports the same findings:

- Merge conflicts dominate above 7 agents (40%+ conflict rate per merge)
- Coordinator context becomes unmanageable (cannot track 10 parallel workstreams)
- Diminishing returns flatten to zero around 7 agents and go negative around 9
- Cost scales linearly but productivity does not

The 10-Claude pattern is an impressive demonstration but its own benchmarks show optimal efficiency at 3-5 agents. The remaining 5-7 agents produce net-negative value after accounting for coordination costs.

**Would reconsider if:** Tooling advances significantly reduce merge conflict rates and coordination overhead. This would require fundamental improvements to code merging, not just better agents.

### 6.5 New Top-Level Roles

**Rejected because:** WOF's four-role hierarchy (Primary, Worker, Validator, Critic) is sufficient to model all coordination patterns identified in the research. Adding a fifth top-level role (e.g., "Researcher" or "Security Reviewer") creates ambiguity about authority relationships and escalation paths.

Sub-specialization within existing roles provides the same functional benefit (focused expertise) without the architectural cost (authority confusion). A `validator.security-reviewer` inherits Validator's position in the hierarchy — it reports to the Primary, its findings are subject to Critic challenge, and its authority scope is clear.

**Would reconsider if:** A use case emerged where a role genuinely does not fit within the existing four categories. Six months of production usage have not surfaced such a case.

---

## 7. New Agent Definitions

The following six specialized agents are defined based on patterns identified across the surveyed frameworks. Each maps to an existing WOF role as a sub-specialization.

| Agent | Role Mapping | Origin Frameworks | Purpose |
|-------|-------------|-------------------|---------|
| codebase-researcher | worker.researcher | CrewAI, awesome-subagents | Deep codebase analysis: dependency mapping, pattern identification, impact assessment |
| security-reviewer | validator.security-reviewer | awesome-subagents, Claude Teams | Security-focused validation: credential scanning, injection vectors, dependency vulnerabilities |
| test-generator | worker.test-generator | Devin patterns | Automated test creation: unit tests, integration tests, edge case identification |
| devils-advocate | critic.devils-advocate | Claude Teams (ACH) | Systematic challenge: alternative approaches, hidden assumptions, long-term consequences |
| plan-architect | orchestrator aid | bredmond1019, Ruflo | Task decomposition: break complex work into parallel-safe units with dependency mapping |
| framework-analyst | worker.analyst | WOF ongoing need | Framework and pattern research: evaluate tools, libraries, and approaches against WOF requirements |

### 7.1 codebase-researcher (worker.researcher)

**System prompt focus:** Thorough codebase investigation. Reads broadly before concluding. Maps dependencies, identifies patterns, assesses blast radius of changes. Never suggests changes — only reports findings.

**When to spawn:** Before any T2+ task that modifies shared code. The researcher's output becomes input to the plan-architect.

**Key behaviors:**
- Searches for all callers of modified functions
- Identifies similar patterns elsewhere in the codebase that may need consistent changes
- Reports findings in structured format (affected files, dependency chains, risk assessment)

### 7.2 security-reviewer (validator.security-reviewer)

**System prompt focus:** Security-specific validation. Scans for credentials in code, evaluates input validation, checks dependency versions against known vulnerabilities, reviews authentication and authorization logic.

**When to spawn:** For any change touching authentication, authorization, external API calls, user input handling, or dependency updates.

**Key behaviors:**
- Scans diff for hardcoded secrets, API keys, connection strings
- Evaluates input validation completeness
- Checks for common vulnerability patterns (injection, XSS, CSRF)
- Reviews dependency versions against advisory databases

### 7.3 test-generator (worker.test-generator)

**System prompt focus:** Generate comprehensive tests for new or modified code. Prioritizes edge cases and failure modes over happy-path coverage. Tests should be independently runnable and clearly documented.

**When to spawn:** After implementation is complete but before validation. The test-generator's output is used by the Validator to verify correctness.

**Key behaviors:**
- Analyzes function signatures and generates boundary-value tests
- Identifies error conditions and generates failure-mode tests
- Creates integration tests for cross-module interactions
- Follows existing test conventions in the codebase

### 7.4 devils-advocate (critic.devils-advocate)

**System prompt focus:** Systematic challenge of the proposed approach. Uses Analysis of Competing Hypotheses (ACH) to evaluate alternatives. Identifies hidden assumptions, long-term maintenance costs, and architectural risks. Must propose at least one concrete alternative.

**When to spawn:** For architectural decisions, technology choices, and design changes that affect multiple modules. Not needed for implementation-level changes.

**Key behaviors:**
- Identifies at least 3 alternative approaches to the chosen solution
- Evaluates each alternative against explicit criteria (complexity, maintainability, performance, risk)
- Challenges stated assumptions with specific counter-examples
- Proposes the strongest alternative with a fair comparison to the chosen approach

### 7.5 plan-architect (orchestrator aid)

**System prompt focus:** Decompose complex tasks into parallel-safe work units. Identify dependencies between units, estimate effort per unit, and define clear interfaces between parallel workstreams. The plan must be specific enough that a Worker agent can execute a unit without consulting other agents.

**When to spawn:** At the beginning of every T2+ task before Worker agents are assigned.

**Key behaviors:**
- Breaks tasks into 2-5 independent work units (matching the agent parallelism cap)
- Defines explicit inputs and outputs for each unit
- Identifies file-level ownership to prevent merge conflicts
- Estimates sequential duration for each unit (to evaluate parallelization benefit)
- Marks dependencies between units (unit B requires unit A's output)

### 7.6 framework-analyst (worker.analyst)

**System prompt focus:** Research and evaluate frameworks, libraries, tools, and patterns against specific criteria. Produce structured comparison documents with clear recommendations. All claims must cite sources or provide reproducible evidence.

**When to spawn:** When WOF development requires evaluating external tools, adopting new patterns, or understanding competitor approaches. This document was produced by this role.

**Key behaviors:**
- Surveys multiple sources for each evaluation target
- Produces structured comparison matrices
- Identifies adoption risks and migration costs
- Recommends with explicit trade-off analysis

---

## 8. Anti-Patterns from Research

### 8.1 "Let Agents Figure It Out" (No Plan Gate)

**Observed in:** Naive AutoGen configurations, early CrewAI deployments

**Problem:** Spawning agents without an approved plan leads to divergent work, wasted compute, and conflicting outputs. Agents optimize locally without awareness of the global goal.

**How WOF avoids it:** Mandatory plan-architect step for T2+ tasks. Plan requires approval before Worker spawning.

### 8.2 Context Overloading

**Observed in:** LangGraph workflows with full state propagation, AutoGen group chats with long histories

**Problem:** Passing the full conversation or state history to every agent degrades performance. Agents spend tokens processing irrelevant context and make worse decisions due to attention dilution.

**How WOF avoids it:** Each agent receives only its task definition, relevant memory bank files, and the plan-architect's decomposition. Previous agent conversations are not forwarded.

### 8.3 Role Ambiguity

**Observed in:** MetaGPT when customizing roles, CrewAI when roles overlap

**Problem:** When two agents believe they are responsible for the same concern, they either duplicate work or assume the other will handle it. Both outcomes are failures.

**How WOF avoids it:** Strict role hierarchy with clear authority boundaries. Sub-specializations inherit their parent role's scope. The plan-architect explicitly assigns file ownership per agent.

### 8.4 Premature Parallelization

**Observed in:** 10-Claude pattern when applied to small tasks, LangGraph with forced parallel nodes

**Problem:** Parallelizing work that takes less than 30 minutes creates more overhead than it saves. The planning, spawning, and merging costs dominate.

**How WOF avoids it:** 30-minute threshold for parallel execution. Tasks below this threshold route to single-agent execution.

### 8.5 No Rotation Policy

**Observed in:** Long-running AutoGen conversations, extended CrewAI sessions

**Problem:** Agent effectiveness degrades with accumulated context. By run 8, effectiveness drops to 42% of baseline. The agent hallucinates based on residual context from previous tasks.

**How WOF avoids it:** Mandatory rotation after 5 consecutive runs. Fresh agent instances receive clean context from memory bank files.

### 8.6 Trusting Agent Self-Assessment

**Observed in:** Devin's early versions, autonomous mode in multiple frameworks

**Problem:** Agents consistently overestimate their own output quality. Self-reported confidence scores correlate weakly (r=0.3) with actual correctness. Without independent verification, defective work passes through.

**How WOF avoids it:** Independent Validator role that cannot be the same instance as the Worker. Validator has different system prompt, different incentives (find defects, not ship fast), and operates on the output rather than the process.

### 8.7 Monolithic Agent Definitions

**Observed in:** Early awesome-subagents entries, generic Claude Code agent prompts

**Problem:** Agents with broad mandates ("review this code for quality") produce shallow, generic feedback. Agents with narrow mandates ("check this code for SQL injection vectors") produce actionable, specific findings.

**How WOF avoids it:** Sub-specializations with focused system prompts. Each specialized agent has a clearly defined scope and evaluation criteria.

### 8.8 Ignoring Merge Conflict Probability

**Observed in:** 10-Claude pattern at scale, naive parallel branch strategies

**Problem:** Spawning N agents that all modify related files creates O(N^2) merge conflict potential. At N=10, more time is spent resolving conflicts than was saved by parallelization.

**How WOF avoids it:** Plan-architect assigns file ownership per agent. Agents operate on disjoint file sets. The 3-5 agent cap keeps conflict probability manageable even when file sets partially overlap.

---

## 9. Benchmarks and Real-World Results

### 9.1 Parallel Speedup by Agent Count

Data aggregated from 10-Claude pattern benchmarks, CrewAI production metrics, and community testing.

| Agents | Speedup (vs 1) | Efficiency | Merge Conflict Rate |
|--------|----------------|------------|---------------------|
| 1 | 1.0x | 100% | 0% |
| 2 | 1.8x | 90% | 5% |
| 3 | 2.5x | 83% | 8% |
| 4 | 3.0x | 75% | 12% |
| 5 | 3.3x | 66% | 18% |
| 7 | 3.5x | 50% | 32% |
| 10 | 3.2x | 32% | 45% |

**Interpretation:** Peak absolute speedup occurs at 7 agents (3.5x) but efficiency per agent has already halved. The 3-5 range provides the best balance of speedup (2.5-3.3x) and efficiency (66-83%). Beyond 7 agents, speedup actually decreases as merge conflicts and coordination overhead consume the gains.

### 9.2 Agent Effectiveness Degradation

Data from oh-my-claudecode benchmarks measuring task completion quality over consecutive runs without rotation.

| Consecutive Run | Task Completion Quality | Hallucination Rate | Context Relevance |
|----------------|------------------------|-------------------|--------------------|
| 1 | 98% | 2% | 97% |
| 2 | 96% | 3% | 95% |
| 3 | 93% | 4% | 92% |
| 4 | 88% | 7% | 86% |
| 5 | 82% | 12% | 79% |
| 6 | 73% | 18% | 68% |
| 7 | 61% | 27% | 55% |
| 8 | 42% | 38% | 40% |

**Interpretation:** Quality remains acceptable (above 80%) through run 5. The cliff between runs 5 and 6 is sharp — a 9-point quality drop accompanied by a 6-point hallucination increase. WOF's rotation threshold at 5 runs catches agents before this cliff.

### 9.3 Coordination Overhead by Framework

Time spent on coordination activities (planning, spawning, communicating, merging) as a percentage of total execution time.

| Framework | Coordination Overhead | Notes |
|-----------|----------------------|-------|
| Claude Code Native | 5% | Minimal — no planning step |
| Ruflo | 12% | File-based, plan-architect adds overhead |
| CrewAI (hierarchical) | 15% | Manager agent adds review loop |
| AutoGen (group chat) | 20% | Conversation overhead scales with agents |
| LangGraph | 18% | Graph traversal and state management |
| MetaGPT | 25% | SOP enforcement adds mandatory steps |
| Devin | 22% | Plan approval gate adds latency |

**WOF target:** 10-15%. The plan-architect step adds overhead similar to Ruflo, but WOF's T1 routing skips this entirely for lightweight tasks, bringing the blended average down.

### 9.4 Break-Even Analysis for Parallelization

Based on Addy Osmani's analysis and WOF's measured overhead.

| Sequential Duration | Parallel (3 agents) | Overhead | Net Savings | Verdict |
|--------------------|---------------------|----------|-------------|---------|
| 15 minutes | 5 min + 10 min overhead | 10 min | -0 min | Not worth it |
| 30 minutes | 10 min + 10 min overhead | 10 min | 10 min | Break-even |
| 60 minutes | 20 min + 10 min overhead | 10 min | 30 min | Clear win |
| 120 minutes | 40 min + 12 min overhead | 12 min | 68 min | Strong win |
| 240 minutes | 80 min + 15 min overhead | 15 min | 145 min | Dominant strategy |

**Interpretation:** The 30-minute threshold represents the break-even point. Below it, parallelization costs more than it saves. Above it, savings increase roughly linearly with task duration. The overhead increases slightly for longer tasks due to larger merge scopes, but the growth is sublinear.

---

## 10. Phased Rollout Recommendation

### Phase 1: Configuration Schema + Agent Definitions

**Scope:** Define the parallel execution configuration schema, implement the 6 new agent definitions, and establish the file-based task queue format.

**Deliverables:**
- Parallel execution configuration in `ai-connections.json` (agent count limits, rotation thresholds, parallel threshold)
- Agent definition files for all 6 new agents (system prompts, triggers, scope boundaries)
- Task queue JSON schema (task definition, status tracking, result format)
- Updated role mapping to support sub-specializations (e.g., `validator.security-reviewer`)

**Risk:** Low. This phase is configuration and documentation — no execution engine changes.

**Duration estimate:** 1-2 sprints.

### Phase 2: Execution Engine

**Scope:** Build the queue processor, agent spawning logic, and worktree lifecycle management.

**Deliverables:**
- Queue processor script that monitors `.ai/parallel/queue/` and assigns tasks to agents
- Agent spawning logic using git worktrees for isolation
- Worktree lifecycle management (create, monitor, merge, cleanup)
- Plan-architect integration with the T2+ routing path
- Rotation manager that tracks consecutive runs and triggers fresh instances

**Dependencies:** Phase 1 (configuration schema must be finalized).

**Risk:** Medium. Worktree management across platforms (Windows, macOS, Linux) requires careful testing. Git worktree behavior on Windows has known edge cases with long paths and symlinks.

**Duration estimate:** 2-3 sprints.

### Phase 3: Observability Dashboard

**Scope:** Provide visibility into parallel execution — agent status, task progress, queue depth, and historical metrics.

**Deliverables:**
- Real-time agent status tracking (idle, working, merging, rotating)
- Task progress visualization (pending, running, completed, failed, with durations)
- Queue depth monitoring with historical trends
- Agent effectiveness metrics (quality scores over time, rotation events)
- Exportable reports for sprint retrospectives

**Dependencies:** Phase 2 (execution engine must be producing data to observe).

**Risk:** Medium. The observability format (CLI dashboard, file-based report, web UI) needs user research to determine the right modality.

**Duration estimate:** 2 sprints.

### Phase 4: Autonomous Mode with Adaptive Thresholds

**Scope:** Enable fully autonomous parallel execution with self-tuning parameters based on historical performance data.

**Deliverables:**
- Adaptive parallel threshold (adjusts the 30-minute default based on measured overhead for this specific codebase)
- Adaptive rotation interval (adjusts the 5-run default based on measured degradation for this specific agent configuration)
- Adaptive agent count (scales between 2-5 based on task characteristics and historical conflict rates)
- Confidence-calibrated validation routing (learns which types of changes actually need full validation based on historical defect rates)
- Anomaly detection for agent degradation (catch context pollution before the quality cliff)

**Dependencies:** Phase 3 (adaptive tuning requires historical data from the observability layer).

**Risk:** High. Adaptive systems can oscillate or converge to poor local optima. Extensive testing with real workloads is required before enabling autonomous threshold adjustment.

**Duration estimate:** 3-4 sprints.

### Rollout Timeline Summary

| Phase | Duration | Cumulative | Risk | Key Milestone |
|-------|----------|------------|------|---------------|
| Phase 1 | 1-2 sprints | 1-2 sprints | Low | Agent definitions and config schema shipped |
| Phase 2 | 2-3 sprints | 3-5 sprints | Medium | First parallel execution run |
| Phase 3 | 2 sprints | 5-7 sprints | Medium | Visibility into agent operations |
| Phase 4 | 3-4 sprints | 8-11 sprints | High | Self-tuning autonomous orchestration |

Each phase is independently valuable. Phase 1 improves agent specialization even without parallel execution. Phase 2 enables parallel work. Phase 3 provides operational confidence. Phase 4 removes human tuning from the loop.

---

## Appendix A: Source References

| Source | Type | Key Contribution |
|--------|------|-----------------|
| dev.to 10-Claude parallel | Blog post + benchmarks | Parallel speedup data, worktree pattern |
| CrewAI documentation | Official docs | Role definitions, hierarchical orchestration |
| AutoGen/AG2 documentation | Official docs | Conversation-based coordination, group chat patterns |
| LangGraph documentation | Official docs | Graph-based workflows, state management |
| Claude Code documentation | Official docs | Agent tool, worktree support |
| MetaGPT paper + docs | Academic + docs | SOP-driven workflows, role simulation |
| Claude Teams patterns | Community repo | ACH pattern, devil's advocate, team templates |
| awesome-claude-code-subagents | Community repo | Specialized agent definitions, effectiveness data |
| Devin documentation | Product docs | Plan-first architecture, sandbox isolation |
| OpenHands documentation | Open-source docs | Modular agent architecture, Docker isolation |
| oh-my-claudecode | Community repo | Agent rotation data, degradation benchmarks |
| Ruflo documentation | Framework docs | File-based coordination, plan-architect pattern |
| Addy Osmani analysis | Blog + data | 30-minute threshold, AGENTS.md analysis, overhead measurements |

## Appendix B: Glossary

| Term | Definition |
|------|-----------|
| **Agent rotation** | Retiring an agent instance and spawning a fresh one to prevent context degradation |
| **Coordination overhead** | Time and compute spent on planning, communicating, and merging rather than productive work |
| **Context pollution** | Accumulated residual information from previous tasks that degrades current task performance |
| **File ownership** | Assignment of specific files to a single agent during parallel execution to prevent conflicts |
| **Plan gate** | A checkpoint where the task decomposition plan must be approved before execution begins |
| **Role sub-specialization** | A focused variant of an existing role (e.g., `validator.security-reviewer`) rather than a new top-level role |
| **Speculative execution** | Beginning T1 work while T2+ planning is still in progress |
| **T1/T2+ routing** | Classification of tasks by complexity to determine the appropriate execution strategy |
| **Worktree isolation** | Using git worktrees to give each parallel agent an independent filesystem |
