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
$script:capability = $criticConfig.capability  # high, medium, low

# =============================================================================
# CAPABILITY-AWARE PROMPTING
# =============================================================================
# Different prompt strategies based on model capability level:
#   high   - Full skeptical PM persona, open-ended questions, complex JSON
#   medium - Structured questions, simpler JSON format
#   low    - Yes/no checklist, one question at a time, minimal parsing

# The skeptical PM persona (for high/medium capability)
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

    # Different strategies based on model capability
    switch ($script:capability) {
        "high" {
            # Full skeptical PM persona, open-ended questions, complex JSON
            return Get-SkepticalQuestions-High -WorkContext $WorkContext -Workflow $Workflow
        }
        "medium" {
            # Structured questions, simpler format
            return Get-SkepticalQuestions-Medium -WorkContext $WorkContext -Workflow $Workflow
        }
        "low" {
            # Yes/no checklist approach
            return Get-SkepticalQuestions-Low -WorkContext $WorkContext -Workflow $Workflow
        }
        default {
            # Default to medium
            return Get-SkepticalQuestions-Medium -WorkContext $WorkContext -Workflow $Workflow
        }
    }
}

function Get-SkepticalQuestions-High {
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

function Get-SkepticalQuestions-Medium {
    param([string]$WorkContext, [string]$Workflow)

    # Simpler prompt, more structured output
    $systemPrompt = "You are a code reviewer checking if work was done correctly."

    $userPrompt = @"
Review this work and list 3-5 concerns as questions.

WORK:
$WorkContext

Reply with ONLY a JSON object like this:
{"questions":[{"id":1,"question":"Was X done?"},{"id":2,"question":"Did Y happen?"}]}
"@

    $response = Invoke-CriticAI -SystemPrompt $systemPrompt -UserPrompt $userPrompt

    $cleanResponse = $response -replace '```json', '' -replace '```', ''
    $jsonMatch = [regex]::Match($cleanResponse, '\{[\s\S]*\}')
    if ($jsonMatch.Success) {
        $parsed = $jsonMatch.Value | ConvertFrom-Json
        # Add missing fields for consistency
        if ($parsed.questions) {
            $parsed.questions = $parsed.questions | ForEach-Object {
                if (-not $_.category) { $_ | Add-Member -NotePropertyName "category" -NotePropertyValue "general" -Force }
                if (-not $_.why_asking) { $_ | Add-Member -NotePropertyName "why_asking" -NotePropertyValue "Quality check" -Force }
                $_
            }
        }
        return $parsed
    }

    throw "Could not parse questions from Critic AI response: $response"
}

function Get-SkepticalQuestions-Low {
    param([string]$WorkContext, [string]$Workflow)

    # For low-capability models: use a predefined checklist with yes/no questions
    # The model just needs to understand the context and mark applicable items

    $checklistByWorkflow = @{
        "general" = @(
            @{id=1; category="testing"; question="Were tests written for new code?"; why_asking="Tests prevent regressions"}
            @{id=2; category="testing"; question="Do all tests pass?"; why_asking="Broken tests block releases"}
            @{id=3; category="security"; question="Are there any hardcoded secrets or passwords?"; why_asking="Security vulnerability"}
            @{id=4; category="quality"; question="Does the code handle errors properly?"; why_asking="Unhandled errors cause crashes"}
            @{id=5; category="process"; question="Was the code reviewed?"; why_asking="Reviews catch bugs"}
        )
        "feature" = @(
            @{id=1; category="requirements"; question="Does the feature match the requirements?"; why_asking="Must meet spec"}
            @{id=2; category="testing"; question="Are there tests for the new feature?"; why_asking="Features need tests"}
            @{id=3; category="security"; question="Does the feature handle user input safely?"; why_asking="Input validation"}
            @{id=4; category="quality"; question="Is the feature documented?"; why_asking="Users need docs"}
            @{id=5; category="testing"; question="Do all existing tests still pass?"; why_asking="No regressions"}
        )
        "bugfix" = @(
            @{id=1; category="testing"; question="Is there a test that reproduces the bug?"; why_asking="Prevent regression"}
            @{id=2; category="quality"; question="Does the fix address the root cause?"; why_asking="Not just symptoms"}
            @{id=3; category="testing"; question="Do all tests pass after the fix?"; why_asking="No new bugs"}
            @{id=4; category="security"; question="Could the bug have security implications?"; why_asking="Security review"}
            @{id=5; category="process"; question="Was the fix reviewed?"; why_asking="Second opinion"}
        )
        "finish" = @(
            @{id=1; category="testing"; question="Does the build pass?"; why_asking="Must build cleanly"}
            @{id=2; category="testing"; question="Do all tests pass?"; why_asking="Tests must pass"}
            @{id=3; category="security"; question="Are there any exposed secrets in the commit?"; why_asking="Security check"}
            @{id=4; category="process"; question="Is the commit message descriptive?"; why_asking="History clarity"}
            @{id=5; category="quality"; question="Is the work item linked?"; why_asking="Traceability"}
        )
    }

    $questions = if ($checklistByWorkflow.ContainsKey($Workflow)) {
        $checklistByWorkflow[$Workflow]
    } else {
        $checklistByWorkflow["general"]
    }

    # For low-capability models, we just return the predefined questions
    # The model doesn't generate questions - it will just evaluate answers to these
    return @{
        questions = $questions
        _generated = $false
        _capability = "low"
        _note = "Using predefined checklist for low-capability model"
    }
}

function Evaluate-Answers {
    param(
        [string]$QuestionsJson,
        [string]$AnswersText,
        [double]$Threshold
    )

    # Different strategies based on model capability
    switch ($script:capability) {
        "high" {
            return Evaluate-Answers-High -QuestionsJson $QuestionsJson -AnswersText $AnswersText -Threshold $Threshold
        }
        "medium" {
            return Evaluate-Answers-Medium -QuestionsJson $QuestionsJson -AnswersText $AnswersText -Threshold $Threshold
        }
        "low" {
            return Evaluate-Answers-Low -QuestionsJson $QuestionsJson -AnswersText $AnswersText -Threshold $Threshold
        }
        default {
            return Evaluate-Answers-Medium -QuestionsJson $QuestionsJson -AnswersText $AnswersText -Threshold $Threshold
        }
    }
}

function Evaluate-Answers-High {
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

function Evaluate-Answers-Medium {
    param(
        [string]$QuestionsJson,
        [string]$AnswersText,
        [double]$Threshold
    )

    # Simpler evaluation prompt
    $systemPrompt = "You are evaluating answers to review questions. Be brief."

    $userPrompt = @"
Questions: $QuestionsJson

Answers: $AnswersText

Rate from 0.0 to 1.0. Reply ONLY with JSON:
{"overall_viability":0.X,"passed":true/false,"summary":"one sentence"}
"@

    $response = Invoke-CriticAI -SystemPrompt $systemPrompt -UserPrompt $userPrompt

    $cleanResponse = $response -replace '```json', '' -replace '```', ''
    $jsonMatch = [regex]::Match($cleanResponse, '\{[\s\S]*?\}')
    if ($jsonMatch.Success) {
        $parsed = $jsonMatch.Value | ConvertFrom-Json
        # Add missing fields
        if (-not $parsed.evaluations) { $parsed | Add-Member -NotePropertyName "evaluations" -NotePropertyValue @() -Force }
        if (-not $parsed.critical_issues) { $parsed | Add-Member -NotePropertyName "critical_issues" -NotePropertyValue @() -Force }
        if (-not $parsed.recommendations) { $parsed | Add-Member -NotePropertyName "recommendations" -NotePropertyValue @() -Force }
        $parsed | Add-Member -NotePropertyName "threshold_used" -NotePropertyValue $Threshold -Force
        return $parsed
    }

    throw "Could not parse evaluation from Critic AI response: $response"
}

function Evaluate-Answers-Low {
    param(
        [string]$QuestionsJson,
        [string]$AnswersText,
        [double]$Threshold
    )

    # For low-capability models: evaluate each answer with a simple yes/no question
    # This avoids complex JSON parsing issues

    $questions = try {
        ($QuestionsJson | ConvertFrom-Json).questions
    } catch {
        @()
    }

    $evaluations = @()
    $passCount = 0
    $totalCount = [Math]::Max($questions.Count, 1)

    foreach ($q in $questions) {
        # Ask a simple yes/no question for each
        $simplePrompt = @"
Answer YES or NO only.

Question that was asked: $($q.question)

Answer given: $AnswersText

Is this answer acceptable? Reply only YES or NO.
"@

        try {
            $response = Invoke-CriticAI -SystemPrompt "Reply only YES or NO." -UserPrompt $simplePrompt
            $isYes = $response -match '\bYES\b'
            $isNo = $response -match '\bNO\b'

            $quality = if ($isYes -and -not $isNo) {
                $passCount++
                "satisfactory"
            } elseif ($isNo -and -not $isYes) {
                "unsatisfactory"
            } else {
                # Unclear response - treat as partial
                $passCount += 0.5
                "partial"
            }

            $evaluations += @{
                question_id = $q.id
                answer_quality = $quality
                confidence = if ($quality -eq "satisfactory") { 0.8 } elseif ($quality -eq "partial") { 0.5 } else { 0.3 }
                concerns = if ($quality -ne "satisfactory") { "Answer needs improvement" } else { $null }
            }
        }
        catch {
            # If API call fails, mark as partial
            $passCount += 0.5
            $evaluations += @{
                question_id = $q.id
                answer_quality = "partial"
                confidence = 0.5
                concerns = "Could not evaluate: $_"
            }
        }
    }

    # Calculate overall viability
    $viability = [Math]::Round($passCount / $totalCount, 2)
    $passed = $viability -ge $Threshold

    # Return as PSCustomObject for consistent handling
    return [PSCustomObject]@{
        evaluations = $evaluations
        overall_viability = $viability
        passed = $passed
        summary = "Evaluated $totalCount questions: $passCount passed (low-capability mode)"
        critical_issues = @()
        recommendations = if (-not $passed) { @("Address the unsatisfactory answers") } else { @() }
        threshold_used = $Threshold
        _capability = "low"
        _note = "Evaluated with simple yes/no questions for low-capability model"
    }
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
                CriticCapability = $script:capability
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
                        CriticCapability = $script:capability
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
                CriticCapability = $script:capability
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
                CriticCapability = $script:capability
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
                CriticCapability = $script:capability
            }
        }
        catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    }
}
