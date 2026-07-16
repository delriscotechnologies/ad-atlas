$runIntegration = $env:AD_ATLAS_RUN_INTEGRATION -eq '1'

Describe 'AD ATLAS authorized-domain integration' -Tag 'Integration' -Skip:(-not $runIntegration) {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\Get-AD-ATLAS.ps1'
        $maxComputers = 10000

        if (-not [string]::IsNullOrWhiteSpace($env:AD_ATLAS_INTEGRATION_MAX_COMPUTERS)) {
            $parsedLimit = 0
            if (-not [int]::TryParse($env:AD_ATLAS_INTEGRATION_MAX_COMPUTERS, [ref]$parsedLimit)) {
                throw 'AD_ATLAS_INTEGRATION_MAX_COMPUTERS must be an integer.'
            }
            if ($parsedLimit -lt 1 -or $parsedLimit -gt 1000000) {
                throw 'AD_ATLAS_INTEGRATION_MAX_COMPUTERS must be between 1 and 1000000.'
            }
            $maxComputers = $parsedLimit
        }
    }

    It 'creates and validates a temporary CSV from the current authorized domain' {
        $outputPath = Join-Path $TestDrive 'AD-ATLAS-integration.csv'

        try {
            & $scriptPath `
                -AllComputers `
                -MaxComputers $maxComputers `
                -OutputPath $outputPath

            Test-Path -LiteralPath $outputPath -PathType Leaf | Should-BeTrue
            Get-Content -LiteralPath $outputPath -TotalCount 1 |
                Should-Be '"Department","ComputerName","OrganizationalUnitPath"'

            $rows = @(Import-Csv -LiteralPath $outputPath)
            ($rows.Count -le $maxComputers) | Should-BeTrue
            foreach ($row in $rows) {
                [string]::IsNullOrWhiteSpace([string]$row.Department) | Should-BeFalse
                [string]::IsNullOrWhiteSpace([string]$row.ComputerName) | Should-BeFalse
            }
        }
        finally {
            if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
                Remove-Item -LiteralPath $outputPath -Force
            }
        }
    }
}
