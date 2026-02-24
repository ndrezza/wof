# Flexible AI Connections

This document describes the unified AI invocation system in WOF, including all supported connection types, delegation methods, and the generic script delegation contract.

## Overview

WOF supports 4 delegation methods for AI invocation:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      DELEGATION METHODS                                      │
├──────────────┬──────────────┬──────────────┬──────────────────────────────────┤
│   native     │     mcp      │   process    │           script               │
├──────────────┼──────────────┼──────────────┼──────────────────────────────────┤
│ Claude Code  │ MCP Server   │ claude CLI   │ PowerShell script              │
│ handles it   │ (stdio)      │ --print      │ with -InputJson                │
│ directly     │              │              │                                │
│              │              │              │                                │
│ Orchestrator │ Worker-Heavy │ Quick AI     │ Worker-Lite                    │
│ only         │ Validator    │ queries      │ Custom scripts                 │
│              │ Critic       │ No tools     │                                │
│              │              │              │                                │
│ Handled by   │ Handled by   │ invoke-ai.ps1│ invoke-ai.ps1                  │
│ Claude Code  │ Claude Code  │              │                                │
└──────────────┴──────────────┴──────────────┴──────────────────────────────────┘
```

## invoke-ai.ps1 — Unified AI Invocation

`invoke-ai.ps1` consolidates all REST API call logic into a single script. It replaces the duplicated API switch statements found in `validate-autonomy.ps1`, `bias-control.ps1`, `interview-validator.ps1`, `delegate-to-local-worker.ps1`, and `check-orchestration-health.ps1`.

### Usage

```powershell
# By role (uses roles.json + connections.json)
.\invoke-ai.ps1 -Role "validator" -Prompt "Should I refactor this code?" -AsJson

# By connection ID (uses connections.json directly)
.\invoke-ai.ps1 -ConnectionId "ai4" -Prompt "Hello" -MaxTokens 256

# With system prompt and model override
.\invoke-ai.ps1 -Role "worker-lite" -Prompt "Find ILogger usage" `
    -SystemPrompt "You are a code search assistant." `
    -Model "deepseek-coder-v2:16b"
```

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-Role` | One of Role/ConnectionId | — | WOF role name (primary, worker-heavy, worker-lite, validator, critic) |
| `-ConnectionId` | One of Role/ConnectionId | — | Connection ID from connections.json (ai1-ai10) |
| `-Prompt` | Yes | — | User prompt text |
| `-SystemPrompt` | No | — | System prompt (optional) |
| `-Model` | No | From config | Override model name |
| `-MaxTokens` | No | 1024 | Maximum response tokens |
| `-Temperature` | No | -1 (API default) | Sampling temperature |
| `-AsJson` | No | — | Output as JSON string |
| `-ConfigPath` | No | `.ai\config` | Path to config directory |

### Standardized Response

Every invocation returns this structure:

```json
{
  "Success": true,
  "Content": "The AI response text...",
  "Model": "claude-sonnet-4-5",
  "TokensUsed": 142,
  "ConnectionType": "anthropic",
  "ConnectionId": "ai1",
  "Latency": 1523,
  "Error": null
}
```

| Field | Type | Description |
|-------|------|-------------|
| `Success` | bool | Whether the call succeeded |
| `Content` | string | AI response text (null on failure) |
| `Model` | string | Model that was used |
| `TokensUsed` | int | Total tokens consumed (0 if unavailable) |
| `ConnectionType` | string | Connection type used |
| `ConnectionId` | string | Connection ID used |
| `Latency` | long | Response time in milliseconds |
| `Error` | string | Error message (null on success) |

## Delegation Methods

### 1. Native

Used only by the Primary (Orchestrator) role. Claude Code handles this directly — `invoke-ai.ps1` is not involved.

```json
{
  "delegation": "native",
  "connection": "native"
}
```

### 2. MCP (Model Context Protocol)

Used for roles that need independent tool access (file read/write, bash, git). Claude Code manages MCP servers — `invoke-ai.ps1` is not involved.

```json
{
  "delegation": "mcp",
  "mcp_server": "validator-claude"
}
```

**When to use:** Validator, Critic, Worker-Heavy — any role that needs to independently verify claims by reading files, running tests, or checking git history.

### 3. Process Delegation

Spawns a `claude --print` process for quick AI queries without MCP overhead. No tool access.

```json
{
  "delegation": "process",
  "model": "claude-sonnet-4-5"
}
```

**How it works:**
1. `invoke-ai.ps1` builds a `claude --print --prompt "..." --model <model>` command
2. Spawns the process and captures stdout
3. Returns the output in the standardized response format

**When to use:** Quick, stateless AI queries that don't need tool access. Lighter than MCP (no persistent server process), heavier than REST (spawns claude process).

**Pros:**
- No API key management (uses Claude Code's own auth)
- Model selection via `--model` flag
- System prompt support via `--system-prompt`

**Cons:**
- No tool access (can't read files, run commands)
- Process spawn overhead per call
- Only works with Claude models

### 4. Script Delegation

Calls a PowerShell script with the `-InputJson` parameter following the generic script contract.

```json
{
  "delegation": "script",
  "script": ".ai/scripts/delegate-to-local-worker.ps1"
}
```

**How it works:**
1. `invoke-ai.ps1` builds a JSON payload with prompt, connection details, etc.
2. Calls the script: `& $scriptPath -InputJson $jsonPayload`
3. Parses the script's JSON output into the standardized response format

**When to use:** Custom delegation logic, local models, or any scenario needing specialized request handling.

## Generic Script Delegation Contract

Any PowerShell script can participate in WOF's delegation system by accepting the `-InputJson` parameter.

### Input Contract

The script receives a `-InputJson` parameter containing:

```json
{
  "prompt": "The user's prompt text",
  "systemPrompt": "Optional system prompt",
  "model": "model-name-from-config",
  "maxTokens": 1024,
  "connection": {
    "id": "ai4",
    "type": "openai-compatible",
    "endpoint": "http://localhost:11434",
    "apiKey": "ollama",
    "deployment": null,
    "apiVersion": null
  }
}
```

### Output Contract

The script should return JSON matching this format:

```json
{
  "Success": true,
  "Content": "Response text here",
  "Model": "deepseek-coder-v2-lite-instruct",
  "TokensUsed": 45,
  "Error": null
}
```

If the script returns non-JSON text, `invoke-ai.ps1` wraps it as `Content` with `Success: true`.

### Example: Minimal Custom Script

```powershell
param(
    [string]$InputJson
)

$input = $InputJson | ConvertFrom-Json

# Your custom logic here
$response = "Processed: $($input.prompt)"

@{
    Success = $true
    Content = $response
    Model = $input.model
} | ConvertTo-Json
```

## Connection Types

### anthropic (Anthropic / Azure AI Foundry Anthropic)

```
POST $endpoint/v1/messages
Headers: api-key, x-api-key, anthropic-version: 2023-06-01
Body: { model, max_tokens, messages: [{role, content}], system? }
Response: .content[0].text
```

### azure-openai (Azure OpenAI)

```
POST $endpoint/openai/deployments/$deployment/chat/completions?api-version=...
Headers: api-key
Body: { messages: [{role, content}], max_tokens }
Response: .choices[0].message.content
```

### openai-compatible (OpenAI, Ollama, local models)

```
POST $endpoint/v1/chat/completions
Headers: Authorization: Bearer $apiKey (optional)
Body: { model, messages: [{role, content}], max_tokens }
Response: .choices[0].message.content
```

## OpenAI API Compatibility

Many AI providers expose an OpenAI-compatible API. WOF's `openai-compatible` connection type works with:

| Provider | Endpoint | Notes |
|----------|----------|-------|
| **OpenAI** | `https://api.openai.com` | Native API |
| **Ollama** (v0.14+) | `http://localhost:11434` | Native OpenAI compat, no proxy needed |
| **vLLM** | `http://localhost:8000` | OpenAI-compatible server |
| **llama.cpp** | `http://localhost:8080` | With `--api-oai` flag |
| **LM Studio** | `http://localhost:1234` | Built-in OpenAI compat |
| **Claude** (via proxy) | Varies | With claude-code-proxy or similar |

### Ollama v0.14+ OpenAI Compatibility

Ollama 0.14 and later natively supports the OpenAI `/v1/chat/completions` endpoint. No proxy is required:

```json
{
  "ai4": {
    "alias": "Local Ollama",
    "type": "openai-compatible",
    "endpoint": "http://localhost:11434",
    "api_key": "ollama",
    "default_model": "qwen3-coder:30b"
  }
}
```

## Adding a New Connection Type

To add support for a new API format:

1. **Update `invoke-ai.ps1`** — Add a new case in the `switch ($resolvedType)` block:
   - Set appropriate headers
   - Build the request body
   - Construct the URI

2. **Update response normalization** — Add a case to extract content from the new API's response format

3. **Update `connections.json.template`** — Document the new type

4. **Update this document** — Add the new type to the Connection Types section

## Migration Guide

### From Duplicated API Calls

Existing scripts (`validate-autonomy.ps1`, `bias-control.ps1`, etc.) have their own switch statements for API types. To migrate:

**Before (duplicated in each script):**
```powershell
switch ($apiType) {
    "anthropic" { ... }
    "azure-openai" { ... }
    "openai-compatible" { ... }
}
$response = Invoke-RestMethod -Uri $uri ...
```

**After (using invoke-ai.ps1):**
```powershell
$result = & (Join-Path $PSScriptRoot "invoke-ai.ps1") `
    -Role "validator" -Prompt $validatorPrompt -MaxTokens 200
if ($result.Success) {
    $responseText = $result.Content
} else {
    Write-Error $result.Error
}
```

Benefits:
- Single place to fix API bugs
- New connection types automatically available everywhere
- Standardized error handling and response format
- Latency tracking included

### From Legacy Environment Variables

If you're using `$env:LOCAL_WORKER_ENDPOINT` directly:

**Before:**
```powershell
$endpoint = $env:LOCAL_WORKER_ENDPOINT
$response = Invoke-RestMethod -Uri "$endpoint/v1/chat/completions" ...
```

**After:**
```powershell
$result = & .\invoke-ai.ps1 -ConnectionId "ai4" -Prompt "Hello"
```

---

*Document Version: 1.0.0*
*Last Updated: 2026-02-24*
