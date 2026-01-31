# Bias Control Script - Quality Assurance via Critic AI
#
# This script implements a "devil's advocate" quality gate using the configured Critic AI.
# It acts as a skeptical PM/Scrum Master/Product Owner who challenges the work done.
#
# Uses resolve-role.ps1 to get connection details from connections.json + roles.json
#
# RECIRCLE/REWORK FLOW:
# +---------------------------------------------------------------------+
# |  1. questions  ->  Generate 3-5 skeptical questions                 |
# |  2. evaluate   ->  Primary AI answers, Critic scores viability      |
# |  3. IF FAILED  ->  remediate phase generates specific fixes         |
# |  4. Primary AI + Validator agree on fixes                           |
# |  5. Implement fixes                                                 |
# |  6. LOOP back to step 1 with updated context                        |
# |  7. Continue until viability >= threshold                           |
# +---------------------------------------------------------------------+
#
# Usage:
#   # Phase 1: Generate questions
#   $questions = & '.\bias-control.ps1' -Phase 'questions' -Context "work summary"
#
#   # Phase 2: Evaluate answers
#   $result = & '.\bias-control.ps1' -Phase 'evaluate' -Questions $questions -Answers $answers
#
#   # Phase 3: If failed, get remediation plan
#   if (-not $result.Passed) {
#       $remediation = & '.\bias-control.ps1' -Phase 'remediate' -Evaluation $result.FullEvaluation
#       # Implement fixes, then loop back to Phase 1
#   }

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('questions', 'evaluate', 'remediate', 'full')]
    [string]$Phase,

    [Parameter(Mandatory=$false)]
    [string]$Context = "",

    [Parameter(Mandatory=$false)]
    [string]$Questions = "",

    [Parameter(Mandatory=$false)]
    [string]$Answers = "",

    [Parameter(Mandatory=$false)]
    [string]$WorkflowType = "general",  # general, finish, feature, bugfix

    [Parameter(Mandatory=$false)]
    [double]$ViabilityThreshold = 0.80,

    [Parameter(Mandatory=$false)]
    [string]$Evaluation = "",  # JSON from evaluate phase (for remediate)

    [Parameter(Mandatory=$false)]
    [string]$OriginalContext = ""  # Original work context (for remediate loop)
)

$ErrorActionPreference = "Stop"

# Resolve critic connection using v2 config
$resolveScript = Join-Path $PSScriptRoot "resolve-role.ps1"
if (-not (Test-Path $resolveScript)) {
    return @{
        Success = $false
        Error = "STOP: resolve-role.ps1 not found. WOF installation may be incomplete."
        ConfigError = $true
    }
}

try {
    $criticConfig = & $resolveScript -Role "critic" -ConfigPath (Join-Path $PSScriptRoot "..\config")
}
catch {
    return @{
        Success = $false
        Error = "STOP: Could not resolve critic role - $_"
        ConfigError = $true
    }
}

# Check if credentials are resolved
if (-not $criticConfig.endpoint_resolved -or -not $criticConfig.api_key_resolved) {
    return @{
        Success = $false
        Error = "STOP: Critic AI not configured. Edit .ai/config/credentials.local.json and fill in the credentials for connection '$($criticConfig.connection_id)'. DO NOT attempt to work around this - tell the user to configure credentials."
        ConfigError = $true
        Connection = $criticConfig.connection_id
        Type = $criticConfig.type
    }
}

$script:endpoint = $criticConfig.endpoint.TrimEnd('/')
$script:apiKey = $criticConfig.api_key
$script:model = $criticConfig.model
$script:apiType = $criticConfig.type
$script:deployment = $criticConfig.deployment
$script:apiVersion = $criticConfig.api_version

# The skeptical PM persona
$skepticPersona = @"
You are a SKEPTICAL QUALITY GATEKEEPER - the "devil's advocate" in an AI-assisted development workflow.

Your personality:
- You are the experienced PM/Scrum Master who has seen too many rushed releases
- You ask the uncomfortable questions others avoid
- You are not hostile, but thorough and demanding
- You appreciate quality and will push back on shortcuts
- Teams eventually love you because you prevent disasters

Your role:
- Challenge assumptions and decisions
- Verify proper process was followed
- Identify gaps in testing, security, and documentation
- Ensure the work truly meets requirements
- Be the voice of the end-user and stakeholder

You are NOT trying to block work - you are ensuring quality.
"@

# Workflow-specific knowledge
$workflowContext = @{
    "general" = @"
Standard development workflow expectations:
- Requirements clearly understood before coding
- Appropriate testing performed
- Security considerations addressed
- Documentation updated
- Code review conducted
"@
    "finish" = @"
Finish Workflow expectations:
1. Work item ID extracted/confirmed
2. Build verification passed
3. Memory bank status reviewed
4. Todo list status checked
5. Memory bank updated with session info
6. Todo list updated (completed/pending)
7. Critical assessment done (branch, security, quality)
8. Changes staged with review
9. Commit with proper format
10. Push to remote
11. Completion report generated

Key questions to ask:
- Was the build actually run and verified?
- Were security scans performed on changed files?
- Is the work item ID properly linked?
- Were all project-specific checks done?
"@
    "feature" = @"
Feature development expectations:
- Feature requirements documented
- Design decisions validated
- Implementation follows conventions
- Tests written for new functionality
- Integration points verified
- Documentation updated
"@
    "bugfix" = @"
Bugfix expectations:
- Root cause identified and documented
- Fix addresses root cause (not just symptoms)
- Regression test added
- Related areas checked for similar issues
- No new bugs introduced
"@
}

function Invoke-CriticAI {
    param(
        [string]$SystemPrompt,
        [string]$UserPrompt
    )

    $headers = @{
        "Content-Type" = "application/json"
    }

    switch ($script:apiType) {
        "anthropic" {
            # Azure AI Foundry Anthropic API
            $headers["api-key"] = $script:apiKey
            $headers["x-api-key"] = $script:apiKey
            $headers["anthropic-version"] = "2023-06-01"

            $body = @{
                model = $script:model
                max_tokens = 2000
                system = $SystemPrompt
                messages = @(
                    @{ role = "user"; content = $UserPrompt }
                )
            } | ConvertTo-Json -Depth 10

            $uri = "$($script:endpoint)/v1/messages"
            if ($script:apiVersion) {
                $uri = "$uri`?api-version=$($script:apiVersion)"
            }

            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 60
            return $response.content[0].text
        }

        "azure-openai" {
            # Azure OpenAI API
            $headers["api-key"] = $script:apiKey

            $deploymentName = if ($script:deployment) { $script:deployment } else { $script:model }

            $body = @{
                messages = @(
                    @{ role = "system"; content = $SystemPrompt }
                    @{ role = "user"; content = $UserPrompt }
                )
                max_tokens = 2000
            } | ConvertTo-Json -Depth 10

            $version = if ($script:apiVersion) { $script:apiVersion } else { "2024-02-15-preview" }
            $uri = "$($script:endpoint)/openai/deployments/$deploymentName/chat/completions?api-version=$version"

            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 60
            return $response.choices[0].message.content
        }

        "openai-compatible" {
            # OpenAI-compatible API (local models, etc.)
            if ($script:apiKey -and $script:apiKey -ne "not-needed") {
                $headers["Authorization"] = "Bearer $($script:apiKey)"
            }

            $body = @{
                model = $script:model
                messages = @(
                    @{ role = "system"; content = $SystemPrompt }
                    @{ role = "user"; content = $UserPrompt }
                )
                max_tokens = 2000
            } | ConvertTo-Json -Depth 10

            $uri = "$($script:endpoint)/v1/chat/completions"

            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 60
            return $response.choices[0].message.content
        }

        default {
            throw "Unknown API type '$($script:apiType)' for critic connection. Supported: anthropic, azure-openai, openai-compatible"
        }
    }
}

function Get-SkepticalQuestions {
    param([string]$WorkContext, [string]$Workflow)

    $systemPrompt = @"
$skepticPersona

$($workflowContext[$Workflow])
"@

    $userPrompt = @"
Review the following work that was done and generate 3-5 SKEPTICAL QUESTIONS that challenge whether the work was done properly.

WORK SUMMARY:
$WorkContext

Generate questions that:
1. Challenge whether proper process was followed
2. Probe for potential gaps or shortcuts
3. Verify critical requirements were met
4. Check for security and quality concerns
5. Ensure the work actually solves the problem

Format your response as a JSON array of questions:
{
    "questions": [
        {"id": 1, "category": "process|security|quality|requirements|testing", "question": "Your skeptical question here?", "why_asking": "Brief reason this matters"},
        ...
    ]
}

Be specific to the work described. Don't ask generic questions - ask about THIS specific work.
IMPORTANT: Return ONLY valid JSON, no other text.
"@

    $response = Invoke-CriticAI -SystemPrompt $systemPrompt -UserPrompt $userPrompt

    # Parse JSON from response - handle markdown code blocks
    $cleanResponse = $response -replace '```json', '' -replace '```', ''
    $jsonMatch = [regex]::Match($cleanResponse, '\{[\s\S]*\}')
    if ($jsonMatch.Success) {
        $parsed = $jsonMatch.Value | ConvertFrom-Json
        return $parsed
    }

    throw "Could not parse questions from Critic AI response: $response"
}

function Evaluate-Answers {
    param(
        [string]$QuestionsJson,
        [string]$AnswersText,
        [double]$Threshold
    )

    $systemPrompt = @"
$skepticPersona

You are now EVALUATING the answers provided by the Primary AI to your skeptical questions.

Your job:
1. Assess each answer for completeness and honesty
2. Determine if the answer satisfactorily addresses the concern
3. Calculate an overall viability score (0.0 to 1.0)
4. Recommend PASS or FAIL based on threshold of $Threshold

Be fair but demanding. Accept good-faith answers that demonstrate the work was done properly.
Flag vague, evasive, or concerning answers.
"@

    $userPrompt = @"
ORIGINAL QUESTIONS:
$QuestionsJson

ANSWERS PROVIDED:
$AnswersText

Evaluate each answer and provide an overall assessment.

Format your response as JSON:
{
    "evaluations": [
        {
            "question_id": 1,
            "answer_quality": "satisfactory|partial|unsatisfactory",
            "confidence": 0.0-1.0,
            "concerns": "Any specific concerns or null"
        },
        ...
    ],
    "overall_viability": 0.0-1.0,
    "passed": true/false,
    "summary": "Brief overall assessment",
    "critical_issues": ["List of critical issues if any"],
    "recommendations": ["What should be done if failed"]
}

Be specific in your evaluation. Reference the actual content of the answers.
"@

    $response = Invoke-CriticAI -SystemPrompt $systemPrompt -UserPrompt $userPrompt

    # Parse JSON from response - handle markdown code blocks
    $cleanResponse = $response -replace '```json', '' -replace '```', ''
    $jsonMatch = [regex]::Match($cleanResponse, '\{[\s\S]*\}')
    if ($jsonMatch.Success) {
        $parsed = $jsonMatch.Value | ConvertFrom-Json
        $parsed | Add-Member -NotePropertyName "threshold_used" -NotePropertyValue $Threshold -Force
        return $parsed
    }

    throw "Could not parse evaluation from Critic AI response: $response"
}

function Get-RemediationPlan {
    param(
        [string]$EvaluationJson,
        [string]$OriginalWork
    )

    $systemPrompt = @"
You are a REMEDIATION ADVISOR helping improve work that failed quality review.

Your role:
- Analyze the failed evaluation to understand what went wrong
- Generate SPECIFIC, ACTIONABLE remediation tasks
- Prioritize by impact (high-impact fixes first)
- Be practical - suggest fixes that can be implemented quickly
- Focus on addressing the critical issues identified

You are helping the team improve, not criticizing them.
"@

    $userPrompt = @"
The following work FAILED the quality review. Generate a remediation plan.

EVALUATION RESULTS:
$EvaluationJson

ORIGINAL WORK CONTEXT:
$OriginalWork

Generate a remediation plan as JSON:
{
    "remediation_tasks": [
        {
            "id": 1,
            "priority": "critical|high|medium|low",
            "category": "process|security|quality|testing|documentation",
            "task": "Specific action to take",
            "rationale": "Why this addresses the concern",
            "estimated_effort": "minimal|moderate|significant",
            "acceptance_criteria": "How to verify this is done properly"
        },
        ...
    ],
    "expected_viability_improvement": 0.0-0.5,
    "minimum_tasks_for_resubmission": 2,
    "summary": "Brief overview of remediation approach"
}

Focus on the CRITICAL issues first. Generate 3-6 remediation tasks.
IMPORTANT: Return ONLY valid JSON, no other text.
"@

    $response = Invoke-CriticAI -SystemPrompt $systemPrompt -UserPrompt $userPrompt

    # Parse JSON from response - handle markdown code blocks
    $cleanResponse = $response -replace '```json', '' -replace '```', ''
    $jsonMatch = [regex]::Match($cleanResponse, '\{[\s\S]*\}')
    if ($jsonMatch.Success) {
        return $jsonMatch.Value | ConvertFrom-Json
    }

    throw "Could not parse remediation plan from Critic AI response"
}

# Main execution
switch ($Phase) {
    'questions' {
        if (-not $Context) {
            return @{ Success = $false; Error = "Context is required for question generation" }
        }

        try {
            $parsed = Get-SkepticalQuestions -WorkContext $Context -Workflow $WorkflowType
            $questionsArray = @($parsed.questions)  # Ensure it's an array
            $jsonOutput = $parsed | ConvertTo-Json -Depth 10 -Compress
            return @{
                Success = $true
                Questions = $questionsArray
                QuestionsJson = $jsonOutput
                RawParsed = $parsed
                CriticModel = $script:model
                CriticType = $script:apiType
            }
        }
        catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }

    'evaluate' {
        if (-not $Questions -or -not $Answers) {
            return @{ Success = $false; Error = "Both Questions and Answers are required for evaluation" }
        }

        try {
            $evaluation = Evaluate-Answers -QuestionsJson $Questions -AnswersText $Answers -Threshold $ViabilityThreshold

            if ($null -eq $evaluation) {
                return @{ Success = $false; Error = "Evaluate-Answers returned null" }
            }

            # Handle case where evaluation might be a string
            if ($evaluation -is [string]) {
                if ($evaluation -match '^\s*@\{') {
                    $viabilityMatch = [regex]::Match($evaluation, 'overall_viability\s*=\s*([\d.]+)')
                    $passedMatch = [regex]::Match($evaluation, 'passed\s*=\s*(True|False)', 'IgnoreCase')
                    $summaryMatch = [regex]::Match($evaluation, 'summary\s*=\s*([^;]+)')

                    return @{
                        Success = $true
                        Passed = if ($passedMatch.Success) { $passedMatch.Groups[1].Value -eq 'True' } else { $false }
                        Viability = if ($viabilityMatch.Success) { [double]$viabilityMatch.Groups[1].Value } else { 0.0 }
                        Threshold = $ViabilityThreshold
                        Summary = if ($summaryMatch.Success) { $summaryMatch.Groups[1].Value.Trim() } else { "" }
                        CriticalIssues = @()
                        Recommendations = @()
                        FullEvaluation = $evaluation
                        _ParsedFromString = $true
                        CriticModel = $script:model
                        CriticType = $script:apiType
                    }
                }
                return @{ Success = $false; Error = "Evaluation returned unexpected string: $evaluation" }
            }

            # Normal object handling
            $evalJson = $evaluation | ConvertTo-Json -Depth 10 -Compress

            $passed = if ($evaluation.passed -is [bool]) { $evaluation.passed } else { $false }
            $viability = if ($evaluation.overall_viability) { [double]$evaluation.overall_viability } else { 0.0 }
            $summary = if ($evaluation.summary) { "$($evaluation.summary)" } else { "" }
            $criticalIssues = if ($evaluation.critical_issues) { @($evaluation.critical_issues) } else { @() }
            $recommendations = if ($evaluation.recommendations) { @($evaluation.recommendations) } else { @() }

            return @{
                Success = $true
                Passed = $passed
                Viability = $viability
                Threshold = $ViabilityThreshold
                Summary = $summary
                CriticalIssues = $criticalIssues
                Recommendations = $recommendations
                FullEvaluation = $evalJson
                CriticModel = $script:model
                CriticType = $script:apiType
            }
        }
        catch {
            return @{ Success = $false; Error = $_.Exception.Message; StackTrace = $_.ScriptStackTrace }
        }
    }

    'remediate' {
        # Generate remediation plan after a failed evaluation
        if (-not $Evaluation) {
            return @{ Success = $false; Error = "Evaluation JSON is required for remediation" }
        }

        try {
            $plan = Get-RemediationPlan -EvaluationJson $Evaluation -OriginalWork $OriginalContext
            $tasksArray = @($plan.remediation_tasks)
            return @{
                Success = $true
                Tasks = $tasksArray
                ExpectedImprovement = $plan.expected_viability_improvement
                MinimumTasksRequired = $plan.minimum_tasks_for_resubmission
                Summary = $plan.summary
                FullPlan = $plan
                NextSteps = @(
                    "1. Review remediation tasks with Validator (validate-autonomy.ps1)",
                    "2. Implement agreed-upon fixes (at least $($plan.minimum_tasks_for_resubmission) tasks)",
                    "3. Update work context with changes made",
                    "4. Re-run bias-control 'questions' phase with updated context",
                    "5. Repeat until viability >= threshold"
                )
                CriticModel = $script:model
                CriticType = $script:apiType
            }
        }
        catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }

    'full' {
        # Full flow: generate questions, return them for answering
        if (-not $Context) {
            return @{ Success = $false; Error = "Context is required for full flow" }
        }

        try {
            $questions = Get-SkepticalQuestions -WorkContext $Context -Workflow $WorkflowType
            return @{
                Success = $true
                Phase = "awaiting_answers"
                Questions = $questions.questions
                QuestionsJson = ($questions | ConvertTo-Json -Depth 5)
                Instructions = "Primary AI should answer each question, then call evaluate phase"
                CriticModel = $script:model
                CriticType = $script:apiType
            }
        }
        catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }
}
