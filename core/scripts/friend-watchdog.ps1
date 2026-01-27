# Friend Watchdog Script - Rules Compliance Validator
#
# This script implements a "Friend" AI persona that validates
# whether the Primary AI is following the rules defined in CLAUDE.md.
#
# Unlike the skeptical Critic, the Friend is a POSITIVE REINFORCEMENT agent:
# - Encourages rule compliance
# - Gently reminds about forgotten rules
# - Validates approach against documented processes
# - Helps prevent rule drift during complex tasks
#
# Usage:
#   # Check if a planned action follows the rules
#   $result = & '.\friend-watchdog.ps1' -Action "I'm about to commit directly to master" -Context "Finishing a bugfix"
#
#   # Validate workflow compliance
#   $result = & '.\friend-watchdog.ps1' -Action "Skipping tests because the change is small" -WorkflowPhase "implement"
#
#   # Get rule reminder for a specific area
#   $result = & '.\friend-watchdog.ps1' -RuleArea "git" -Action "About to push code"

param(
    [Parameter(Mandatory=$false)]
    [string]$Action = "",  # What the AI is about to do

    [Parameter(Mandatory=$false)]
    [string]$Context = "",  # Why/what's happening

    [Parameter(Mandatory=$false)]
    [string]$WorkflowPhase = "",  # Current phase if in 9-phase workflow

    [Parameter(Mandatory=$false)]
    [ValidateSet('git', 'testing', 'security', 'documentation', 'delegation', 'general', 'workflow')]
    [string]$RuleArea = "general",

    [Parameter(Mandatory=$false)]
    [switch]$ShowDetails
)

$ErrorActionPreference = "Stop"

# Load credentials
$credPath = Join-Path $PSScriptRoot "..\config\credentials.local.ps1"
if (Test-Path $credPath) {
    . $credPath
}

# Friend uses GPT-4o (Azure OpenAI)
$endpoint = $env:AZURE_OPENAI_ENDPOINT
$apiKey = $env:AZURE_OPENAI_API_KEY

if (-not $endpoint -or -not $apiKey) {
    return @{
        Success = $false
        Error = "Azure OpenAI (GPT-4o) not configured. Set AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_API_KEY."
    }
}

$endpoint = $endpoint.TrimEnd('/')

# Load CLAUDE.md rules
$claudeMdPath = Join-Path $PSScriptRoot "..\..\CLAUDE.md"
$claudeMdContent = ""
if (Test-Path $claudeMdPath) {
    $claudeMdContent = Get-Content $claudeMdPath -Raw
}
else {
    return @{
        Success = $false
        Error = "CLAUDE.md not found at $claudeMdPath"
    }
}

# The Friend persona - positive reinforcement
$friendPersona = @"
You are the FRIEND - a supportive AI companion who helps ensure rule compliance.

Your personality:
- You are warm, encouraging, and genuinely helpful
- You want the Primary AI to succeed by following the established rules
- You gently remind about rules without being condescending
- You celebrate good compliance and correct behavior
- You are NOT critical or punishing - you are a supportive guide

Your role:
- Validate that planned actions follow CLAUDE.md rules
- Remind about relevant rules that might be forgotten
- Suggest the correct approach when rules would be violated
- Provide positive reinforcement when rules are being followed
- Help prevent "rule drift" during complex tasks

Key principle: You are a FRIEND, not a gatekeeper. You help, not block.

IMPORTANT RULES FROM CLAUDE.md (partial - focus on these key areas):

## Git Rules:
- NEVER commit directly to master - always use feature branches
- Commit format: #[WorkItemID] Description (no AI attribution)
- NEVER add Co-Authored-By or AI branding to commits/PRs
- Never skip hooks (--no-verify) unless user explicitly requests

## Workflow Rules:
- Use 9-phase workflow for features
- MUST run tests in Phase 4 - no skipping
- MUST update current-sprint.md in Phase 7
- MUST achieve viability >= 80% before finishing

## Delegation Rules:
- MUST delegate to Worker for research/investigation tasks
- MUST delegate for tasks requiring >5 tool calls
- Keep security-sensitive operations in Primary

## Autonomy Rules:
- Validate 33-50% of non-trivial decisions with Validator
- Proceed when confidence > 0.7, ask user when <= 0.7
- DO, don't suggest - execute operations, don't tell user to do them
"@

# Rule area specific context
$ruleAreaContext = @{
    "git" = @"
GIT-SPECIFIC RULES:
- NEVER commit to master directly
- Always create feature branch: feature/[id]-[description]
- Commit format: #[ID] Description (no AI attribution!)
- Stage specific files, not "git add -A" (could include secrets)
- NEVER force push to main/master
- NEVER use --no-verify unless user explicitly requests
- Create NEW commits after hook failures, don't amend
"@
    "testing" = @"
TESTING-SPECIFIC RULES:
- Tests are MANDATORY in Phase 4 of 9-phase workflow
- Run tests BEFORE committing
- Use run-tests.ps1 script for structured results
- Never skip tests because "change is small"
- Add regression tests for bugfixes
"@
    "security" = @"
SECURITY-SPECIFIC RULES:
- Never commit .env, credentials, or secrets
- Review [AllowAnonymous] attributes carefully
- Don't expose internal endpoints
- Validate at system boundaries
- Keep security operations in Primary (not Worker)
"@
    "documentation" = @"
DOCUMENTATION-SPECIFIC RULES:
- Update current-sprint.md after significant actions
- Don't create unnecessary README/MD files
- Update memory bank during Phase 7
- Document decisions and rationale
"@
    "delegation" = @"
DELEGATION-SPECIFIC RULES:
- MUST delegate to Worker for:
  * Research/investigation tasks
  * Multi-file exploration (>3 files)
  * Git/ADO analysis
  * Tasks requiring >5 tool calls
- Primary KEEPS:
  * User interaction
  * Final git operations
  * Validation/Critic calls
  * Security-sensitive operations
"@
    "workflow" = @"
9-PHASE WORKFLOW RULES:
1. Intake - Understand requirements
2. Design - Validate with Validator (>0.7 confidence)
3. Implement - Write code, build must pass
4. Test - MANDATORY, cannot skip
5. Critique - bias-control.ps1 (viability >= 80%)
6. Validate - Final build + tests
7. Document - UPDATE current-sprint.md
8. Review - Documentation check
9. Finish - Commit, push, PR

Phase gates are ENFORCED - use phase-gate.ps1
"@
    "general" = @"
GENERAL RULES:
- DO, don't suggest - execute operations yourself
- No AI attribution in commits/PRs
- Use multi-AI architecture for non-trivial tasks
- Validate decisions with Validator (33-50%)
- Answer questions in ADO, not to user directly
- Read work items before acting on them
"@
}

function Invoke-Friend {
    param(
        [string]$SystemPrompt,
        [string]$UserPrompt
    )

    $body = @{
        messages = @(
            @{ role = "system"; content = $SystemPrompt }
            @{ role = "user"; content = $UserPrompt }
        )
        max_tokens = 1000
        temperature = 0.5  # Lower temperature for consistent rule checking
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "api-key" = $apiKey
        "Content-Type" = "application/json"
    }

    $uri = "$endpoint/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview"

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 30
        return $response.choices[0].message.content
    }
    catch {
        throw "Friend (GPT-4o) API error: $_"
    }
}

# Build system prompt with relevant rules
$systemPrompt = @"
$friendPersona

$($ruleAreaContext[$RuleArea])
"@

# Build user prompt based on input
$userPrompt = @"
The Primary AI is about to take the following action:

ACTION: $Action
$(if ($Context) { "CONTEXT: $Context" })
$(if ($WorkflowPhase) { "CURRENT WORKFLOW PHASE: $WorkflowPhase" })

Please evaluate this action against the CLAUDE.md rules and provide:

1. COMPLIANCE: Is this action compliant with the rules? (yes/mostly/no)
2. RELEVANT_RULES: Which specific rules apply to this action?
3. CONCERNS: Any rules that might be violated or forgotten?
4. SUGGESTION: If not compliant, what should be done instead?
5. ENCOURAGEMENT: A brief positive message (you're the Friend!)

Format your response as JSON:
{
    "compliance": "yes|mostly|no",
    "confidence": 0.0-1.0,
    "relevant_rules": ["rule1", "rule2"],
    "concerns": ["concern1"] or [],
    "suggestion": "What to do instead" or null,
    "encouragement": "Positive message",
    "proceed": true/false
}

Be supportive but accurate. If the action is fine, celebrate it!
IMPORTANT: Return ONLY valid JSON.
"@

try {
    $response = Invoke-Friend -SystemPrompt $systemPrompt -UserPrompt $userPrompt

    # Parse JSON from response
    $cleanResponse = $response -replace '```json', '' -replace '```', ''
    $jsonMatch = [regex]::Match($cleanResponse, '\{[\s\S]*\}')

    if ($jsonMatch.Success) {
        $parsed = $jsonMatch.Value | ConvertFrom-Json

        return @{
            Success = $true
            Compliance = $parsed.compliance
            Confidence = $parsed.confidence
            Proceed = $parsed.proceed
            RelevantRules = @($parsed.relevant_rules)
            Concerns = @($parsed.concerns)
            Suggestion = $parsed.suggestion
            Encouragement = $parsed.encouragement
            RuleArea = $RuleArea
        }
    }

    throw "Could not parse Friend response: $response"
}
catch {
    return @{
        Success = $false
        Error = $_.Exception.Message
    }
}
