# .NET Project Example

This example shows how to configure the Workload Orchestration Framework (WOF) for a .NET solution.

## Setup

```powershell
# From the Workload-Orchestration repository root
.\setup.ps1 -TargetPath "C:\code\MyDotNetProject" `
    -SolutionName "MyDotNetProject" `
    -GitDefaultBranch "main" `
    -BuildCommand "dotnet build" `
    -WorkItemPrefix "#"
```

## Customizations

### Build Command Options

For different .NET project types:

```powershell
# Standard solution
-BuildCommand "dotnet build"

# Specific project
-BuildCommand "dotnet build src/MyProject/MyProject.csproj"

# With configuration
-BuildCommand "dotnet build -c Release"

# Including tests
-BuildCommand "dotnet build && dotnet test"
```

### Example CLAUDE.md Additions

Add these to your generated CLAUDE.md for .NET-specific behavior:

```markdown
## .NET-Specific Conventions

### Project Structure
- Solutions in root directory
- Projects in `src/` folder
- Tests in `tests/` folder with `.Tests` suffix

### Coding Standards
- Use file-scoped namespaces
- Async methods suffixed with `Async`
- Use `ILogger<T>` for logging
- Prefer record types for DTOs

### NuGet Packages
- Check for vulnerabilities: `dotnet list package --vulnerable`
- Update packages: `dotnet outdated` (requires dotnet-outdated-tool)
```

## Files Generated

After setup, your project will have:

```
MyDotNetProject/
├── CLAUDE.md
├── .claude/
│   └── settings.json
├── .ai/
│   ├── scripts/
│   │   ├── get-worker-routing.ps1
│   │   ├── validate-autonomy.ps1
│   │   ├── bias-control.ps1
│   │   └── ...
│   ├── config/
│   │   ├── routing-rules.md
│   │   ├── risk-rules.yaml
│   │   └── credentials.local.ps1  # Create from template
│   ├── memory/
│   │   ├── architecture.md
│   │   ├── conventions.md
│   │   └── current-sprint.md
│   └── agents/
│       └── orchestrator.md
└── MyDotNetProject.sln
```

## Testing the Setup

```powershell
# Validate configuration
.\.ai\scripts\check-orchestration-health.ps1

# Test routing decision
.\.ai\scripts\get-worker-routing.ps1 -TaskDescription "Add new API endpoint for user management"
# Expected: worker-heavy (T2+ task)

.\.ai\scripts\get-worker-routing.ps1 -TaskDescription "Find where UserService is defined"
# Expected: worker-lite (T1 task)
```
