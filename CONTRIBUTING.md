# Contributing

Contributions should preserve AD ATLAS as a small, read-only Active Directory inventory tool.

## Before opening a pull request

- Use only synthetic directory names and computer objects in examples and tests.
- Never commit real reports, hostnames, domain names, OU structures, credentials, or other sensitive environment data.
- Keep Active Directory access read-only and limited to the properties required by the CSV output.
- Preserve Windows PowerShell 5.1 compatibility.
- Update documentation when behavior, parameters, output, or security boundaries change.

## Validation

Run the same checks used by CI:

```powershell
Install-Module Pester -RequiredVersion 6.0.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser

Invoke-Pester -Path .\tests
Invoke-ScriptAnalyzer -Path .\Get-AD-ATLAS.ps1 -Severity Warning,Error
```

Tests must not contact a real Active Directory domain.

## Pull requests

Keep changes focused and explain:

- what changed
- why it changed
- security or privacy impact
- how it was validated

Security vulnerabilities should be reported according to [SECURITY.md](SECURITY.md), not through a public pull request.
