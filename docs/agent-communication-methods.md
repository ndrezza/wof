# Agent Communication Methods in WOF

This document describes all methods of interaction with and between AI models in the Workload Orchestration Framework.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AGENT COMMUNICATION METHODS                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │ SYNCHRONOUS │    │ASYNCHRONOUS │    │  FILE-BASED │    │   HYBRID    │  │
│  ├─────────────┤    ├─────────────┤    ├─────────────┤    ├─────────────┤  │
│  │ PowerShell  │    │ Message     │    │ Memory Bank │    │ MCP Server  │  │
│  │ REST API    │    │ Queues      │    │ Config JSON │    │ SSH/Remote  │  │
│  │ gRPC        │    │ Webhooks    │    │ Shared DB   │    │ Task Tool   │  │
│  │ WebSockets  │    │             │    │             │    │             │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Method 1: PowerShell REST API Calls

**Status:** ✅ Implemented in WOF

### Architecture

```
┌──────────────────┐          HTTP POST           ┌──────────────────┐
│                  │  ─────────────────────────►  │                  │
│  Primary Agent   │     /v1/messages             │   AI Endpoint    │
│  (Claude Code)   │     /v1/chat/completions     │  (Azure/Local)   │
│                  │  ◄─────────────────────────  │                  │
└──────────────────┘          JSON Response       └──────────────────┘
        │
        │ Invoke-RestMethod
        ▼
┌──────────────────┐
│  PowerShell      │
│  Script          │
│  (.ps1)          │
└──────────────────┘
```

### Implementation

```powershell
# Example: validate-autonomy.ps1
$body = @{
    model = "claude-sonnet-4-5"
    max_tokens = 200
    messages = @(@{ role = "user"; content = $prompt })
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "$endpoint/v1/messages" `
    -Method Post -Headers $headers -Body $body
```

### Pros
| Advantage | Description |
|-----------|-------------|
| Simple | Standard HTTP, no special dependencies |
| Portable | Works on any platform with PowerShell |
| Debuggable | Easy to log requests/responses |
| Stateless | Each call is independent |
| Flexible | Can call any OpenAI-compatible API |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| Synchronous | Blocks until response (timeout risk) |
| No streaming | Must wait for full response |
| Cold start | Each call has connection overhead |
| No context | Each call starts fresh (no memory) |
| Error handling | Must handle network failures manually |

### WOF Files
- `core/scripts/validate-autonomy.ps1` - Validator calls
- `core/scripts/delegate-to-local-worker.ps1` - Worker-Lite calls
- `core/scripts/check-orchestration-health.ps1` - Health checks

---

## Method 2: MCP Server (Model Context Protocol)

**Status:** ✅ Implemented in WOF

### Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Claude Code Process                          │
│  ┌────────────────┐                      ┌────────────────────────┐  │
│  │                │    stdio/JSON-RPC    │                        │  │
│  │  Primary Agent │ ◄──────────────────► │  MCP Server Process    │  │
│  │  (Orchestrator)│                      │  (worker-claude-heavy)    │  │
│  │                │                      │                        │  │
│  └────────────────┘                      └───────────┬────────────┘  │
│                                                      │               │
└──────────────────────────────────────────────────────┼───────────────┘
                                                       │
                                                       │ API Calls
                                                       ▼
                                          ┌────────────────────────┐
                                          │   External AI Service  │
                                          │   (Azure Foundry)      │
                                          └────────────────────────┘
```

### Configuration

```json
// mcp.json
{
  "mcpServers": {
    "worker-claude-heavy": {
      "type": "stdio",
      "command": "claude",
      "args": ["--model", "claude-opus-4-5"]
    },
    "azure-devops": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@tiberriver256/mcp-server-azure-devops"]
    }
  }
}
```

### Pros
| Advantage | Description |
|-----------|-------------|
| Integrated | Native Claude Code support |
| Tool-based | Exposes capabilities as callable tools |
| Persistent | Server stays running between calls |
| Bidirectional | Server can also call back |
| Typed | Schema-defined tool interfaces |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| Complexity | Requires MCP server implementation |
| Platform-specific | Windows needs `cmd /c` wrapper |
| Resource usage | Each server is a separate process |
| Limited ecosystem | Fewer MCP servers than REST APIs |
| Debugging | Harder to trace stdio communication |

### WOF Files
- `templates/mcp.json.template` - MCP server definitions
- `templates/dot-claude/skills/wof/SKILL.md` - ADO MCP setup

---

## Method 3: Claude Process Delegation

**Status:** ✅ Implemented in WOF (v3.5.0+)

### Architecture

```
┌──────────────────┐                              ┌──────────────────┐
│                  │    claude --print             │                  │
│  Primary Agent   │  ──────────────────────────►  │  Claude CLI      │
│  (Claude Code)   │    --prompt "..."             │  Process         │
│                  │    --model <model>            │  (ephemeral)     │
│                  │  ◄──────────────────────────  │                  │
└──────────────────┘    stdout (text response)     └──────────────────┘
        │
        │ invoke-ai.ps1
        │ (delegation: "process")
        ▼
┌──────────────────┐
│  Standardized    │
│  JSON response   │
│  {Success, ...}  │
└──────────────────┘
```

### How It Works

1. `invoke-ai.ps1` detects `delegation: "process"` in the role config
2. Builds a `claude --print --prompt "..." --model <model>` command
3. Spawns the process and captures stdout
4. Wraps output in WOF's standardized response format

### Configuration

```json
// roles.json
{
  "worker-lite": {
    "connection": "native",
    "model": "claude-sonnet-4-5",
    "delegation": "process"
  }
}
```

### Pros
| Advantage | Description |
|-----------|-------------|
| No API keys | Uses Claude Code's own authentication |
| Simple | No MCP server setup, no REST endpoints |
| Model selection | Can specify any model via `--model` flag |
| System prompts | Supports `--system-prompt` for role context |
| Lightweight | No persistent process — spawn on demand |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| No tool access | Cannot read files, run commands, or verify claims |
| Process overhead | Each call spawns a new process |
| Claude only | Only works with Claude models (not local LLMs) |
| No streaming | Must wait for full response |
| No context | Each call starts fresh |

### When to Use

Process delegation is ideal for:
- Quick AI queries that don't need tool access
- Roles where MCP overhead isn't justified
- Scenarios where you want Claude Code's auth but don't need MCP capabilities
- Validation/critique of text-only decisions (no file verification needed)

### WOF Files
- `core/scripts/invoke-ai.ps1` - Process delegation handler
- `templates/config/roles.json.template` - Role configuration
- `core/docs/flexible-ai-connections.md` - Detailed documentation

---

## Method 4: SSH Remote Terminal

**Status:** 🔶 Conceptual (not yet implemented)

### Architecture

```
┌──────────────────┐                         ┌──────────────────────────┐
│  Local Machine   │                         │    Remote Machine        │
│  ┌────────────┐  │       SSH Tunnel        │  ┌──────────────────┐   │
│  │            │  │  ═══════════════════►   │  │                  │   │
│  │  Primary   │  │       Port 22           │  │  Remote Claude   │   │
│  │  Agent     │  │  ◄═══════════════════   │  │  Code Instance   │   │
│  │            │  │       TTY/PTY           │  │                  │   │
│  └────────────┘  │                         │  └──────────────────┘   │
│        │         │                         │          │              │
│        ▼         │                         │          ▼              │
│  ┌────────────┐  │                         │  ┌──────────────────┐   │
│  │  SSH       │  │                         │  │  Target Codebase │   │
│  │  Client    │  │                         │  │  (Different Repo)│   │
│  └────────────┘  │                         │  └──────────────────┘   │
└──────────────────┘                         └──────────────────────────┘
```

### Example Usage

```bash
# Primary agent connects to remote agent
ssh user@remote-server "claude code --headless"

# Or via PowerShell
$session = New-PSSession -HostName remote-server -UserName user
Invoke-Command -Session $session -ScriptBlock { claude code "Fix the bug" }
```

### Pros
| Advantage | Description |
|-----------|-------------|
| Full access | Complete terminal control |
| Isolation | Separate environment/codebase |
| Security | SSH encryption and auth |
| Flexibility | Run any commands |
| Existing infra | Uses standard SSH |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| Latency | Network round-trip for each interaction |
| Complexity | Session management, key handling |
| State | Must manage connection lifecycle |
| Parsing | Output is text, not structured |
| Interactive | PTY handling is complex |

### Potential WOF Implementation
```powershell
# core/scripts/delegate-to-remote-worker.ps1
param([string]$Task, [string]$RemoteHost)

$result = ssh $RemoteHost "cd /repo && claude code '$Task' --output json"
return $result | ConvertFrom-Json
```

---

## Method 5: Claude Code Task Tool (Subagents)

**Status:** ✅ Available via Claude Code

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Single Claude Code Process                        │
│                                                                      │
│  ┌──────────────────┐         Task Tool         ┌────────────────┐  │
│  │                  │  ────────────────────────► │                │  │
│  │  Primary Agent   │                            │  Subagent      │  │
│  │  (Orchestrator)  │  ◄──────────────────────── │  (Explore/     │  │
│  │                  │         Result             │   Plan/etc)    │  │
│  └──────────────────┘                            └────────────────┘  │
│          │                                              │            │
│          │ Shared Context                               │            │
│          ▼                                              ▼            │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                     Shared File System                         │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Usage Pattern

```
Task tool invocation:
├── subagent_type: "Explore" - Codebase exploration
├── subagent_type: "Plan" - Implementation planning
├── subagent_type: "Bash" - Command execution
└── subagent_type: "general-purpose" - Multi-step tasks
```

### Pros
| Advantage | Description |
|-----------|-------------|
| No setup | Built into Claude Code |
| Shared context | Access to same filesystem |
| Specialized | Different agent types for different tasks |
| Parallel | Can run multiple subagents concurrently |
| Lightweight | No separate processes |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| Same model | Cannot use different AI models |
| Same credentials | Shares API access |
| Token limits | Counts against main context |
| No MCP access | Subagents can't call MCP tools |
| Relay required | Must pass data through Primary |

### WOF Pattern: Formatter Relay
```
Primary ──► MCP Tool Call ──► Raw JSON
              │
              ▼
Primary ──► Task Tool ──► Subagent formats JSON
              │
              ▼
           Formatted Output
```

---

## Method 6: Message Queues (Asynchronous)

**Status:** 🔶 Conceptual (not yet implemented)

### Architecture

```
┌──────────────┐      ┌─────────────────────┐      ┌──────────────┐
│              │      │                     │      │              │
│  Producer    │ ───► │   Message Queue     │ ───► │  Consumer    │
│  Agent       │      │   (Azure SB/RMQ)    │      │  Agent       │
│              │      │                     │      │              │
└──────────────┘      └─────────────────────┘      └──────────────┘
       │                       │                          │
       │                       │                          │
       ▼                       ▼                          ▼
  Fire & Forget          Persistence &              Process When
                         Retry Logic                  Ready
```

### Example Implementation

```powershell
# Producer: Send task to queue
$message = @{ task = "Review PR #123"; priority = "high" }
Send-AzServiceBusMessage -QueueName "agent-tasks" -Body ($message | ConvertTo-Json)

# Consumer: Poll and process
while ($true) {
    $msg = Receive-AzServiceBusMessage -QueueName "agent-tasks"
    if ($msg) {
        $result = Invoke-AgentTask -Task $msg.Body
        Complete-AzServiceBusMessage -Message $msg
    }
}
```

### Pros
| Advantage | Description |
|-----------|-------------|
| Decoupled | Agents don't need to be online simultaneously |
| Scalable | Multiple consumers can process in parallel |
| Reliable | Built-in retry and dead-letter handling |
| Async | Non-blocking for producer |
| Buffered | Handles traffic spikes |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| Complexity | Requires queue infrastructure |
| Latency | Not real-time |
| Ordering | May need to handle out-of-order delivery |
| Cost | Cloud queue services have costs |
| Debugging | Harder to trace message flow |

---

## Method 7: File-Based Communication (Memory Bank)

**Status:** ✅ Implemented in WOF

### Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Shared Filesystem                          │
│                                                                   │
│  ┌─────────────────┐                    ┌─────────────────────┐  │
│  │ .ai/memory/     │                    │ .ai/config/         │  │
│  │ ├─architecture  │                    │ ├─connections.json  │  │
│  │ ├─conventions   │                    │ ├─roles.json        │  │
│  │ └─current-sprint│                    │ └─credentials.json  │  │
│  └────────┬────────┘                    └──────────┬──────────┘  │
│           │                                        │              │
│           │ Read/Write                             │ Read         │
│           ▼                                        ▼              │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    Agent Process                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### WOF Memory Structure

```
.ai/memory/
├── architecture.md      # System design decisions
├── conventions.md       # Code style and patterns
├── current-sprint.md    # Active work items (user-maintained)
└── lessons-learned.md   # Historical context
```

### Pros
| Advantage | Description |
|-----------|-------------|
| Simple | Just files on disk |
| Persistent | Survives restarts |
| Versioned | Can be git-tracked |
| Human-readable | Easy to inspect and edit |
| No dependencies | Works everywhere |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| Race conditions | Concurrent writes can conflict |
| Polling required | No notification of changes |
| No structure | Schema enforcement is manual |
| Scale limits | Not suitable for high-frequency updates |
| Local only | Doesn't work across machines |

---

## Method 8: WebSockets (Real-Time Bidirectional)

**Status:** 🔶 Conceptual (not yet implemented)

### Architecture

```
┌──────────────────┐                      ┌──────────────────┐
│                  │                      │                  │
│  Agent A         │ ◄═══════════════════►│  Agent B         │
│                  │    WebSocket          │                  │
│                  │    (persistent)       │                  │
└──────────────────┘                      └──────────────────┘
        │                                         │
        │ Real-time                               │ Real-time
        │ bidirectional                           │ bidirectional
        ▼                                         ▼
   Push messages                            Push messages
   No polling                               No polling
```

### Example Implementation

```javascript
// Agent A - Server
const wss = new WebSocketServer({ port: 8080 });
wss.on('connection', (ws) => {
  ws.on('message', (task) => {
    const result = processTask(JSON.parse(task));
    ws.send(JSON.stringify(result));
  });
});

// Agent B - Client
const ws = new WebSocket('ws://agent-a:8080');
ws.send(JSON.stringify({ task: 'validate', data: decision }));
ws.on('message', (result) => handleResult(JSON.parse(result)));
```

### Pros
| Advantage | Description |
|-----------|-------------|
| Real-time | Instant message delivery |
| Bidirectional | Both sides can initiate |
| Efficient | No polling overhead |
| Streaming | Can send partial results |
| Persistent | Connection stays open |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| Stateful | Must manage connection state |
| Complexity | More code than REST |
| Firewall issues | May be blocked |
| Reconnection | Must handle disconnects |
| Scale | Each connection uses resources |

---

## Method 9: Shared Database

**Status:** 🔶 Conceptual (not yet implemented)

### Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Agent A    │     │   Agent B    │     │   Agent C    │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       │ INSERT             │ UPDATE             │ SELECT
       │                    │                    │
       ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────┐
│                     Shared Database                      │
│  ┌─────────────────────────────────────────────────┐    │
│  │  tasks        │ status    │ result   │ agent    │    │
│  │───────────────┼───────────┼──────────┼──────────│    │
│  │  validate PR  │ complete  │ {...}    │ agent_b  │    │
│  │  build proj   │ pending   │ null     │ null     │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### Pros
| Advantage | Description |
|-----------|-------------|
| ACID | Transactions prevent conflicts |
| Query power | Complex queries on task state |
| Persistence | Durable storage |
| Audit trail | Full history of changes |
| Scalable | Databases handle high load |

### Cons
| Disadvantage | Description |
|--------------|-------------|
| Infrastructure | Requires database server |
| Schema design | Must model task/result structure |
| Polling | Need to poll for changes (or use triggers) |
| Complexity | SQL/ORM overhead |
| Latency | Database round-trip on each operation |

---

## Comparison Matrix

| Method | Latency | Complexity | Scalability | State | Current Status |
|--------|---------|------------|-------------|-------|----------------|
| **PowerShell REST** | Low | Low | Medium | Stateless | ✅ Implemented |
| **MCP Server** | Low | Medium | Low | Stateful | ✅ Implemented |
| **Process Delegation** | Low | Low | Low | Stateless | ✅ Implemented |
| **SSH Remote** | Medium | High | High | Stateful | 🔶 Conceptual |
| **Task Tool** | Low | Low | Low | Shared | ✅ Available |
| **Message Queue** | Medium | High | High | Async | 🔶 Conceptual |
| **File-Based** | High | Low | Low | Persistent | ✅ Implemented |
| **WebSockets** | Very Low | Medium | Medium | Stateful | 🔶 Conceptual |
| **Shared Database** | Low | High | High | Persistent | 🔶 Conceptual |

---

## Recommended Patterns by Use Case

### Decision Validation (Current: Validator)
```
Recommendation: MCP Server
Reason: Enables independent verification - Validator can read files to verify claims
```

### Complex Task Delegation (Current: Worker-Heavy)
```
Recommendation: MCP Server or Task Tool
Reason: Maintains context, supports tool access
```

### Cross-Machine Collaboration
```
Recommendation: SSH Remote + REST API
Reason: Secure access to different codebases/environments
```

### High-Volume Processing
```
Recommendation: Message Queue + Database
Reason: Handles scale, provides reliability
```

### Real-Time Collaboration
```
Recommendation: WebSockets
Reason: Instant bidirectional communication
```

---

## Context Passing Between Agents

A critical consideration for multi-agent systems is whether and how context can be shared between AI agents.

### Context Types

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CONTEXT TYPES                                │
├─────────────────┬───────────────────────────────────────────────────┤
│ Conversation    │ Message history (user/assistant turns)           │
│ System Prompt   │ Role definition, instructions                    │
│ Working State   │ Current task progress, intermediate results      │
│ Long-term Memory│ Architecture decisions, conventions, lessons     │
│ Tool Results    │ Output from previous tool calls                  │
└─────────────────┴───────────────────────────────────────────────────┘
```

### Context Passing Capability Matrix

| Method | Conversation | System Prompt | Working State | Long-term Memory | Tool Results |
|--------|:------------:|:-------------:|:-------------:|:----------------:|:------------:|
| **PowerShell REST** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **MCP Server** | ⚠️ | ✅ | ✅ | ✅ | ✅ |
| **SSH Remote** | ⚠️ | ✅ | ⚠️ | ✅ | ⚠️ |
| **Task Tool** | ✅* | ✅ | ❌ | ✅ | ❌ |
| **Message Queue** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **File-Based** | ⚠️ | ✅ | ✅ | ✅ | ✅ |
| **WebSockets** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Shared Database** | ✅ | ✅ | ✅ | ✅ | ✅ |

**Legend:** ✅ Full support | ⚠️ Partial/Manual | ❌ Not supported | * Special behavior

---

### Method Details for Context Passing

#### PowerShell REST API - Full Context Support

```
┌─────────────────┐                    ┌─────────────────┐
│  Primary Agent  │                    │  Target AI      │
│                 │   HTTP POST        │                 │
│  ┌───────────┐  │  ┌───────────────┐ │                 │
│  │ Context   │──┼─►│ messages: [   │─┼─►  Receives     │
│  │ History   │  │  │   {role,content}  │  full context │
│  │ State     │  │  │   {role,content}  │               │
│  └───────────┘  │  │ ]             │ │                 │
└─────────────────┘  └───────────────┘ └─────────────────┘
```

```powershell
# Example: Pass full conversation context
$messages = @(
    @{ role = "system"; content = "You are the Validator..." }
    @{ role = "user"; content = "Previous context: $previousContext" }
    @{ role = "assistant"; content = "Previous response..." }
    @{ role = "user"; content = "New question: $currentQuestion" }
)

$body = @{ model = "claude-sonnet-4-5"; messages = $messages } | ConvertTo-Json
```

**Limitation:** Token limits apply (~200K). Large context must be summarized.

#### MCP Server - Partial Context (Server State)

```
┌─────────────────────────────────────────────────────────┐
│                 MCP Server Process                       │
│  ┌─────────────────┐      ┌─────────────────────────┐   │
│  │ Server State    │      │ Tool Call Parameters    │   │
│  │ (persistent)    │ ◄────│ context: "..."          │   │
│  │                 │      │ task: "..."             │   │
│  └─────────────────┘      └─────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

- Server can maintain state between calls (persistent process)
- No automatic conversation history - must pass explicitly in tool parameters
- System prompt defined in server implementation

#### SSH Remote - Manual Serialization Required

```
┌──────────────┐                      ┌──────────────────┐
│ Local Agent  │                      │ Remote Agent     │
│              │  ssh + serialized    │                  │
│  Context ────┼──────────────────────┼──► Fresh Start   │
│  (serialize) │  context as arg/file │     + context    │
└──────────────┘                      └──────────────────┘
```

```bash
# Option 1: Pass context as argument (limited by shell)
ssh remote "claude code --context '$serialized_context' 'Do task'"

# Option 2: Copy context file first
scp context.json remote:/tmp/
ssh remote "claude code --context-file /tmp/context.json 'Do task'"
```

**Challenge:** Remote Claude Code starts fresh each invocation.

#### Task Tool - Automatic Conversation Access

```
┌─────────────────────────────────────────────────────────┐
│                  Claude Code Process                     │
│                                                          │
│  ┌──────────────────┐     ┌────────────────────────┐    │
│  │ Primary Agent    │     │ Subagent               │    │
│  │                  │     │                        │    │
│  │ Conversation ────┼────►│ CAN READ full history  │    │
│  │ History          │     │ before Task call       │    │
│  │                  │     │                        │    │
│  │ MCP Tools ───────┼──X──│ CANNOT call MCP tools  │    │
│  │                  │     │                        │    │
│  └──────────────────┘     └────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

From the Task tool documentation:
> *"Agents with 'access to current context' can see the full conversation history before the tool call."*

**Key limitation:** Subagents cannot access MCP tools or call tools on behalf of Primary.

#### File-Based - Explicit Persistence

```
┌──────────────┐    Write     ┌──────────────┐    Read     ┌──────────────┐
│   Agent A    │ ───────────► │  .ai/memory/ │ ◄─────────  │   Agent B    │
│              │              │              │             │              │
│ - Decisions  │              │ context.json │             │ - Continues  │
│ - Reasoning  │              │ state.md     │             │   work       │
│ - Progress   │              │              │             │              │
└──────────────┘              └──────────────┘             └──────────────┘
```

WOF implements this with the memory bank:
- `architecture.md` - Long-term architectural context
- `conventions.md` - Code style context
- `current-sprint.md` - Working state context

---

### Context Passing Comparison

| Method | Context Size Limit | Latency | Persistence | Complexity |
|--------|-------------------|---------|-------------|------------|
| **PowerShell REST** | ~200K tokens | Low | None (per-call) | Low |
| **MCP Server** | Server memory | Low | Session | Medium |
| **SSH Remote** | Shell/file limits | High | Must serialize | High |
| **Task Tool** | Shared with Primary | Very Low | Session | Very Low |
| **File-Based** | Disk space | High (I/O) | Permanent | Low |
| **Message Queue** | Message size limit | Medium | Queue retention | High |
| **WebSockets** | Memory | Very Low | Connection lifetime | Medium |
| **Shared Database** | DB limits | Low | Permanent | High |

---

### Recommended Hybrid Approach for WOF

For optimal context passing between agents, WOF recommends a hybrid approach:

```
┌─────────────────────────────────────────────────────────────────────┐
│  RECOMMENDED: Hybrid Context Strategy                                │
│                                                                      │
│  1. Long-term context  →  File-Based (.ai/memory/)                  │
│  2. Conversation context →  PowerShell REST (messages array)        │
│  3. Tool results       →  Task Tool relay pattern                   │
│                                                                      │
│  ┌──────────┐   REST + context    ┌───────────┐                     │
│  │Orchestrator│─────────────────►│ Validator │                      │
│  │          │◄─────────────────── │           │                     │
│  └────┬─────┘   response          └───────────┘                     │
│       │                                                              │
│       │ read/write                                                   │
│       ▼                                                              │
│  ┌──────────┐                                                        │
│  │.ai/memory│  ← Shared long-term context                           │
│  └──────────┘                                                        │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation Guidelines:**

1. **Short-term context** (current task, recent decisions): Include in REST API `messages` array
2. **Medium-term context** (current sprint, active work items): Read from `.ai/memory/current-sprint.md`
3. **Long-term context** (architecture, conventions): Read from `.ai/memory/` files
4. **Tool results**: Use Task Tool relay pattern - Primary calls MCP, passes results to subagent

---

## Validator Communication Strategy

The Validator agent requires careful consideration of communication method to ensure truly independent validation.

### The Problem with REST for Validation

```
┌─────────────────────────────────────────────────────────────────────────┐
│  REST (Blind Validator) - "Trust but Verify via Prompting"             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Orchestrator ──► REST ──► Validator                                   │
│       │                        │                                        │
│       │ Provides context       │ Can only evaluate                      │
│       │ in prompt              │ what it's told                         │
│       ▼                        ▼                                        │
│  "I want to edit auth.js,   "Based on your description,                │
│   it's a 50-line file"       this seems safe"                          │
│                                                                         │
│  Risk: Orchestrator bias passes through unchecked                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Problems with blind validation:**
1. **Framing bias** - Orchestrator describes things favorably
2. **Lies of omission** - "small change" to critical code goes undetected
3. **Not truly validating** - just rubber-stamping with confidence theater

### The Solution: MCP for Independent Verification

```
┌─────────────────────────────────────────────────────────────────────────┐
│  MCP (Sighted Validator) - "Independent Verification"                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Orchestrator ──► MCP ──► Validator                                    │
│       │                       │                                         │
│       │ States intent         │ Can independently                       │
│       │                       │ verify claims                           │
│       ▼                       ▼                                         │
│  "I want to edit auth.js"   Reads auth.js → "This is 500 lines        │
│                              of security-critical code, not            │
│                              what you implied"                          │
│                                                                         │
│  Benefit: True independent validation                                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Capability Comparison

| Capability | REST (Blind) | MCP (Sighted) |
|------------|:------------:|:-------------:|
| Verify Orchestrator's claims | ❌ | ✅ |
| Read files to assess risk | ❌ | ✅ |
| Check git history | ❌ | ✅ |
| Maintain session context | ❌ | ✅ |
| Independent judgment | ❌ | ✅ |

### Example: Why MCP Matters

```
Orchestrator: "I want to make a small change to utils.js"

REST Validator (blind):
  → Trusts the claim "small change"
  → Returns: {proceed: true, confidence: 0.85}

MCP Validator (can see):
  → Reads utils.js - sees it's 2000 lines of critical code
  → Checks git blame - sees it hasn't been touched in 2 years
  → Returns: {proceed: false, confidence: 0.3,
              reason: "This is core infrastructure, not a small utility"}
```

### Validator: MCP Server (Recommended)

| Factor | MCP Server | PowerShell REST |
|--------|:----------:|:---------------:|
| Independent verification | ✅ | ❌ |
| Can read files | ✅ | ❌ |
| Can check git | ✅ | ❌ |
| Session context | ✅ | ❌ |
| Resource usage | ⚠️ Higher | ✅ Lower |
| Setup complexity | ⚠️ Medium | ✅ Low |

**Trade-off accepted:** More resource usage is worth the trustworthiness gain.

```
┌──────────────────┐      MCP stdio       ┌──────────────────────┐
│ Orchestrator     │ ◄══════════════════► │ validator-claude     │
│ Claude           │  Tool: validate      │ (Sonnet via Foundry) │
│                  │                      │                      │
│                  │                      │ Has access to:       │
│                  │                      │ • File system (read) │
│                  │                      │ • Git commands       │
│                  │                      │ • Codebase context   │
└──────────────────┘                      └──────────────────────┘
```

---

## Critic Communication Strategy

The same independent verification argument applies to Critic Claude.

### The Problem with REST for Critique

```
┌─────────────────────────────────────────────────────────────────────────┐
│  REST (Blind Critic) - "Trust Worker's Claims"                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Worker Claude ──► REST ──► Critic Claude                              │
│       │                          │                                      │
│       │ Reports results          │ Can only evaluate                    │
│       │ in response              │ what it's told                       │
│       ▼                          ▼                                      │
│  "I implemented the feature   "Based on your description,              │
│   with full test coverage"     viability: 0.9"                         │
│                                                                         │
│  Risk: Worker bias passes through unchecked                            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### The Solution: MCP for Independent Critique

```
┌─────────────────────────────────────────────────────────────────────────┐
│  MCP (Sighted Critic) - "Verify Before Scoring"                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Worker Claude ──► MCP ──► Critic Claude                               │
│       │                        │                                        │
│       │ Claims completion      │ Can independently                      │
│       │                        │ verify claims                          │
│       ▼                        ▼                                        │
│  "Full test coverage"        Runs: dotnet test → 3/12 failing          │
│                              Runs: coverage → 34%                       │
│                              "Viability: 0.4 - claims don't match"     │
│                                                                         │
│  Benefit: True quality gate, not rubber stamp                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Critic Verification Capabilities

| Capability | REST (Blind) | MCP (Sighted) |
|------------|:------------:|:-------------:|
| Run tests | ❌ | ✅ |
| Check code coverage | ❌ | ✅ |
| Run linters/analyzers | ❌ | ✅ |
| Verify file changes | ❌ | ✅ |
| Check build output | ❌ | ✅ |
| Independent judgment | ❌ | ✅ |

### Critic Claude: MCP Server (Recommended)

```
┌──────────────────┐      MCP stdio       ┌──────────────────────┐
│ Orchestrator     │ ◄══════════════════► │ critic-claude        │
│ Claude           │  Tool: critique      │ (Codex/Sonnet)       │
│                  │                      │                      │
│                  │                      │ Has access to:       │
│                  │                      │ • Test runner        │
│                  │                      │ • Coverage tools     │
│                  │                      │ • Linters/analyzers  │
│                  │                      │ • Build output       │
└──────────────────┘                      └──────────────────────┘
```

---

## Worker Delegation Strategy

A critical design decision in WOF is which communication method to use for delegating tasks to Worker agents.

### Task Delegation Requirements

| Requirement | Worker-Heavy (T2+) | Worker-Lite (T1) |
|-------------|-------------------|------------------|
| Task complexity | High (implement, refactor, test) | Low (search, format, lint) |
| Context needed | Full (architecture, conventions, code) | Minimal (specific query) |
| Tool access | Yes (read/write files, run builds) | Rarely (mostly read-only) |
| Response size | Large (code, explanations) | Small (results, lists) |
| Latency tolerance | Higher (complex work) | Low (quick turnaround) |
| Cost sensitivity | Lower (quality matters) | Higher (high volume) |

### Recommended Strategy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     WORKER DELEGATION STRATEGY                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────┐                                               │
│  │   ORCHESTRATOR      │                                               │
│  │   (Claude Opus)     │                                               │
│  └──────────┬──────────┘                                               │
│             │                                                           │
│             │ Route by task tier                                        │
│             │                                                           │
│      ┌──────┴──────┐                                                   │
│      │             │                                                    │
│      ▼             ▼                                                    │
│  ┌────────────────────────┐      ┌────────────────────────────────┐   │
│  │  WORKER-HEAVY (T2+)    │      │  WORKER-LITE (T1)              │   │
│  │                        │      │                                │   │
│  │  Method: MCP Server    │      │  Method: PowerShell REST       │   │
│  │  ────────────────────  │      │  ────────────────────────────  │   │
│  │  • Full tool access    │      │  • Stateless, fast             │   │
│  │  • Persistent session  │      │  • Minimal overhead            │   │
│  │  • Rich context        │      │  • Easy fallback               │   │
│  │  • Streaming possible  │      │  • Cost-effective              │   │
│  │                        │      │                                │   │
│  │  Model: Opus/Sonnet    │      │  Model: DeepSeek/Local         │   │
│  │  via Azure Foundry     │      │  via HTTP :1234                │   │
│  └────────────────────────┘      └────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Worker-Heavy: MCP Server (Recommended)

**Why MCP over other methods:**

| Factor | MCP Server | PowerShell REST | Task Tool |
|--------|:----------:|:---------------:|:---------:|
| Tool access (file R/W, bash) | ✅ | ❌ | ❌ |
| Persistent session | ✅ | ❌ | ❌ |
| Streaming responses | ✅ | ❌ | ❌ |
| Different model | ✅ | ✅ | ❌ |
| Context window | Full | Full | Shared |
| Setup complexity | Medium | Low | Very Low |

**MCP enables the worker to:**
- Read and write files in the codebase
- Run build/test commands
- Maintain state across multiple subtasks
- Stream partial results back

```
┌──────────────┐        MCP stdio         ┌──────────────────────┐
│ Orchestrator │ ◄══════════════════════► │ worker-claude-heavy     │
│              │   Tool: delegate_task    │ (Worker-Heavy)       │
│              │   Tool: get_result       │                      │
│              │                          │ Has access to:       │
│              │                          │ • File system        │
│              │                          │ • Bash commands      │
│              │                          │ • Full codebase      │
└──────────────┘                          └──────────────────────┘
```

### Worker-Lite: PowerShell REST (Recommended)

**Why REST over other methods:**

| Factor | PowerShell REST | MCP Server | Task Tool |
|--------|:---------------:|:----------:|:---------:|
| Startup latency | ✅ None | ❌ Process spawn | ✅ None |
| Resource usage | ✅ Minimal | ❌ Persistent process | ✅ Shared |
| Fallback handling | ✅ Easy | ⚠️ Complex | ❌ N/A |
| Cost control | ✅ Local model | ❌ Cloud API | ❌ Same API |
| Simplicity | ✅ Simple | ⚠️ Medium | ✅ Simple |

**REST is ideal because T1 tasks:**
- Don't need tool access (just return answers)
- Are high-volume, low-cost
- Benefit from local model (no API costs)
- Need fast fallback to Worker-Heavy on failure

```
┌──────────────┐       HTTP POST          ┌──────────────────────┐
│ Orchestrator │ ─────────────────────►   │ Local Model          │
│              │   /v1/chat/completions   │ (DeepSeek @ :1234)   │
│              │ ◄─────────────────────   │                      │
│              │       JSON response      │ Capabilities:        │
│              │                          │ • Search/grep        │
│              │   On failure:            │ • Format/lint        │
│              │   Escalate to Heavy      │ • Simple queries     │
└──────────────┘                          └──────────────────────┘
```

### Why NOT Other Methods for Workers

| Method | Why Not for Worker-Heavy | Why Not for Worker-Lite |
|--------|--------------------------|-------------------------|
| **SSH Remote** | Overkill - same machine | Latency too high |
| **Task Tool** | No tool access, shared context limit | Can't use different model |
| **Message Queue** | Unnecessary complexity | Latency, infrastructure |
| **File-Based** | Too slow for interactive work | Polling overhead |
| **WebSockets** | No existing implementation | Over-engineered |
| **Database** | Wrong abstraction | Infrastructure overhead |

### Current WOF Implementation Status

| Agent | Current Method | Status | Notes |
|-------|---------------|--------|-------|
| Worker Claude Heavy | MCP (`worker-claude-heavy`) | ✅ Configured | Needs tool exposure |
| Worker Claude Lite | REST (`delegate-to-local-worker.ps1`) | ✅ Implemented | Working |
| Validator Claude | MCP (`validator-claude`) | 🔶 Planned | Upgrade from REST |
| Critic Claude | MCP (`critic-claude`) | 🔶 Planned | Upgrade from REST |

---

## Complete Agent Communication Summary

This section summarizes the recommended communication method for each agent role in WOF.

### Agent Naming Convention

| Role | Agent Name | MCP Server Name | Model |
|------|------------|-----------------|-------|
| Orchestrator | **Orchestrator Claude** | N/A (native) | Claude Opus |
| Heavy Worker | **Worker Claude Heavy** | `worker-claude-heavy` | Claude Opus/Sonnet |
| Lite Worker | **Worker Claude Lite** | N/A (REST) | DeepSeek/Local |
| Validator | **Validator Claude** | `validator-claude` | Claude Sonnet |
| Critic | **Critic Claude** | `critic-claude` | GPT Codex / Claude |

### Agent-to-Method Matrix

| Agent | Recommended Method | Rationale |
|-------|-------------------|-----------|
| **Worker Claude Heavy** | MCP Server | Needs tools for implementation (file R/W, bash) |
| **Worker Claude Lite** | PowerShell REST | Stateless queries, cost-sensitive, local model |
| **Validator Claude** | MCP Server | Needs tools for independent verification |
| **Critic Claude** | MCP Server | Needs tools to verify Worker claims (run tests, check coverage) |

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    COMPLETE AGENT COMMUNICATION                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│                    ┌─────────────────────┐                             │
│                    │  ORCHESTRATOR CLAUDE │                            │
│                    │    (Claude Opus)     │                            │
│                    └──────────┬──────────┘                             │
│                               │                                         │
│         ┌─────────────────────┼─────────────────────┐                  │
│         │                     │                     │                   │
│         ▼                     ▼                     ▼                   │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐            │
│  │WORKER CLAUDE│      │  VALIDATOR  │      │   CRITIC    │            │
│  │             │      │   CLAUDE    │      │   CLAUDE    │            │
│  └──────┬──────┘      └──────┬──────┘      └──────┬──────┘            │
│         │                    │                    │                    │
│    ┌────┴────┐               │                    │                    │
│    │         │               │                    │                    │
│    ▼         ▼               ▼                    ▼                    │
│ ┌─────┐  ┌─────┐         ┌─────┐             ┌─────┐                  │
│ │ MCP │  │REST │         │ MCP │             │ MCP │                  │
│ │     │  │     │         │     │             │     │                  │
│ │Heavy│  │Lite │         │Sonnet│            │Codex│                  │
│ └─────┘  └─────┘         └─────┘             └─────┘                  │
│    │         │               │                    │                    │
│  Tools    Stateless      Verify              Verify                   │
│  for      queries        claims              output                   │
│  impl.                   independently       run tests               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why This Configuration

| Agent | Why This Method | Alternative Considered |
|-------|-----------------|------------------------|
| **Worker Claude Heavy** | Implementation requires file access, builds, tests | REST - rejected: no tool access |
| **Worker Claude Lite** | T1 tasks are simple queries, local model saves cost | MCP - rejected: overkill for queries |
| **Validator Claude** | Must verify claims independently, not trust Orchestrator | REST - rejected: blind validation is theater |
| **Critic Claude** | Must verify Worker output - run tests, check coverage, validate claims | REST - rejected: blind critique is theater |

### Decision Summary

```
┌─────────────────────────────────────────────────────────┐
│              AGENT COMMUNICATION SUMMARY                │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Worker Claude Heavy (T2+):  MCP Server                │
│  ─────────────────────────────────────                 │
│  • Needs tool access for implementation                │
│  • Persistent session for complex tasks                │
│  • Quality over speed                                  │
│                                                         │
│  Worker Claude Lite (T1):    PowerShell REST           │
│  ─────────────────────────────────────                 │
│  • Stateless, fast queries                             │
│  • Local model = zero API cost                         │
│  • Easy fallback on failure                            │
│                                                         │
│  Validator Claude:           MCP Server                │
│  ─────────────────────────────────────                 │
│  • Independent verification of claims                  │
│  • Can read files, check git history                   │
│  • Not just trusting Orchestrator's framing            │
│                                                         │
│  Critic Claude:              MCP Server                │
│  ─────────────────────────────────────                 │
│  • Verify Worker output independently                  │
│  • Can run tests, check coverage                       │
│  • Not just trusting Worker's claims                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Future Considerations

1. **gRPC** - For high-performance, typed communication between services
2. **GraphQL subscriptions** - For real-time updates with complex queries
3. **Event sourcing** - For complete audit trail and replay capability
4. **Container orchestration** - Kubernetes for agent scaling and lifecycle

---

*Document Version: 1.5.0*
*Last Updated: 2026-02-24*

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-31 | Initial document with 8 communication methods |
| 1.1.0 | 2026-01-31 | Added context passing between agents section |
| 1.2.0 | 2026-01-31 | Added worker delegation strategy |
| 1.3.0 | 2026-01-31 | Updated Validator recommendation from REST to MCP for independent verification |
| 1.4.0 | 2026-01-31 | Renamed agents (Orchestrator Claude, Worker Claude Heavy/Lite, Validator Claude, Critic Claude). Updated Critic to MCP for independent verification. |
| 1.5.0 | 2026-02-24 | Added Method 3: Claude Process Delegation. Renumbered methods 3-8 → 4-9. Updated comparison matrix. |
