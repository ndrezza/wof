# Bias Control Script - Quality Assurance via Critic AI
#
# This script implements a "devil's advocate" quality gate using Azure OpenAI.
# It acts as a skeptical PM/Scrum Master/Product Owner who challenges the work done.
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

# Load credentials
$credPath = Join-Path $PSScriptRoot "..\config\credentials.local.ps1"
if (Test-Path $credPath) {
    . $credPath
}

$endpoint = $env:AZURE_CODEX_ENDPOINT
$apiKey = $env:AZURE_CODEX_API_KEY

if (-not $endpoint -or -not $apiKey) {
    return @{
        Success = $false
        Error = "Critic AI not configured. Set AZURE_CODEX_ENDPOINT and AZURE_CODEX_API_KEY."
    }
}

# Note: Codex endpoint already includes the full path, so we don't modify it
$endpoint = $endpoint.TrimEnd('/')

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

    # Azure OpenAI Responses API format
    $body = @{
        model = "gpt-5.1-codex-mini"
        input = @(
            @{ role = "system"; content = $SystemPrompt }
            @{ role = "user"; content = $UserPrompt }
        )
    } | ConvertTo-Json -Depth 10

    $headers = @{
        "api-key" = $apiKey
        "Content-Type" = "application/json"
    }

    # Endpoint already includes full path with api-version
    $uri = $endpoint

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 60
        # Responses API returns output directly or in output_text field
        if ($response.output_text) {
            return $response.output_text
        }
        elseif ($response.output) {
            # Handle array of outputs
            if ($response.output -is [array]) {
                $textOutput = $response.output | Where-Object { $_.type -eq 'message' } | Select-Object -First 1
                if ($textOutput.content) {
                    if ($textOutput.content -is [array]) {
                        return ($textOutput.content | Where-Object { $_.type -eq 'output_text' } | Select-Object -First 1).text
                    }
                    return $textOutput.content
                }
            }
            return $response.output
        }
        elseif ($response.choices) {
            # Fallback to chat completions format
            return $response.choices[0].message.content
        }
        throw "Unexpected response format from Critic AI"
    }
    catch {
        throw "Critic AI API error: $_"
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
            }
        }
        catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }
}
