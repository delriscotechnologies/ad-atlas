#Requires -Version 5.1

<#
.SYNOPSIS
Builds AD ATLAS: a CSV map of Active Directory computers and department OUs.

.DESCRIPTION
Retrieves Active Directory computer objects, derives a department from their OU path,
and writes one CSV file. The Active Directory operation is read-only.

.PARAMETER AllComputers
Confirms that the query should include all computer objects in the current domain.
This is an operator confirmation guardrail, not an authorization boundary.

.PARAMETER MaxComputers
Safety limit for the number of computer objects. The query requests one extra object
so the script can stop when the limit is exceeded.

.PARAMETER DepartmentStrategy
ClosestRelevant selects the first non-technical OU above the computer.
TopRelevant selects the highest non-technical OU in the path.

.PARAMETER IgnoreOUs
OU names that represent technical containers rather than departments.

.PARAMETER OutputPath
Destination CSV path. By default, the script creates a timestamped CSV under
Documents\AD-ATLAS-Reports.

.PARAMETER AllowNetworkOutput
Explicitly permits a direct UNC output path. Direct UNC paths are rejected by default.
Mapped or mounted filesystem drives remain available through OutputPath.

.EXAMPLE
.\Get-AD-ATLAS.ps1 -AllComputers

.EXAMPLE
.\Get-AD-ATLAS.ps1 -AllComputers -MaxComputers 50000

.EXAMPLE
.\Get-AD-ATLAS.ps1 -AllComputers -IgnoreOUs 'Devices','Computers','Workstations','Laptops','Servers'

.EXAMPLE
.\Get-AD-ATLAS.ps1 -AllComputers -OutputPath '\\fileserver\reports\AD-ATLAS.csv' -AllowNetworkOutput
#>

param(
    [switch]$AllComputers,

    [ValidateRange(1, 1000000)]
    [int]$MaxComputers = 10000,

    [ValidateSet('ClosestRelevant', 'TopRelevant')]
    [string]$DepartmentStrategy = 'ClosestRelevant',

    [AllowEmptyCollection()]
    [string[]]$IgnoreOUs = @(
        'Devices', 'Computers', 'Workstations', 'Laptops', 'Desktops',
        'Servers', 'Clients', 'Endpoints', 'Managed Devices'
    ),

    [AllowEmptyString()]
    [string]$OutputPath,

    [switch]$AllowNetworkOutput
)

Set-StrictMode -Version Latest

$script:ToolVersion = '1.3.1'
$script:VendorName = 'Del Risco Technologies'

function Split-DistinguishedName {
    param([string]$DistinguishedName)

    $parts = [System.Collections.Generic.List[string]]::new()
    $start = 0
    $backslashCount = 0

    for ($index = 0; $index -lt $DistinguishedName.Length; $index++) {
        $character = $DistinguishedName[$index]

        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq ',' -and ($backslashCount % 2 -eq 0)) {
            $parts.Add($DistinguishedName.Substring($start, $index - $start))
            $start = $index + 1
        }

        $backslashCount = 0
    }

    $parts.Add($DistinguishedName.Substring($start))
    return $parts
}

function ConvertFrom-DistinguishedNameValue {
    param([string]$Value)

    $decoded = [System.Text.StringBuilder]::new()
    $index = 0

    while ($index -lt $Value.Length) {
        $character = $Value[$index]

        if ($character -ne '\' -or $index + 1 -ge $Value.Length) {
            $null = $decoded.Append($character)
            $index++
            continue
        }

        $bytes = [System.Collections.Generic.List[byte]]::new()
        $cursor = $index

        while (
            $cursor + 2 -lt $Value.Length -and
            $Value[$cursor] -eq '\' -and
            $Value.Substring($cursor + 1, 2) -match '^[0-9A-Fa-f]{2}$'
        ) {
            $bytes.Add([Convert]::ToByte($Value.Substring($cursor + 1, 2), 16))
            $cursor += 3
        }

        if ($bytes.Count -gt 0) {
            $null = $decoded.Append([System.Text.Encoding]::UTF8.GetString($bytes.ToArray()))
            $index = $cursor
            continue
        }

        $escapedCharacter = $Value[$index + 1]
        if ($escapedCharacter -in @(',', '+', '"', '\', '<', '>', ';', '=', '#', ' ')) {
            $null = $decoded.Append($escapedCharacter)
            $index += 2
            continue
        }

        $null = $decoded.Append($character)
        $index++
    }

    return $decoded.ToString()
}

function Resolve-DepartmentOU {
    param(
        [AllowEmptyString()][string]$DistinguishedName,
        [AllowEmptyCollection()][string[]]$IgnoreOUs,
        [string]$Strategy
    )

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
        return [pscustomobject]@{
            DepartmentOU = ''
            OUPath       = ''
        }
    }

    $ous = @(
        foreach ($part in (Split-DistinguishedName -DistinguishedName $DistinguishedName)) {
            if ($part -match '^OU=(.*)$') {
                ConvertFrom-DistinguishedNameValue -Value $matches[1]
            }
        }
    )

    $relevantOUs = @(
        foreach ($ou in $ous) {
            if ($ou -notin @($IgnoreOUs)) {
                $ou
            }
        }
    )

    $department = ''
    if ($relevantOUs.Count -gt 0) {
        if ($Strategy -eq 'TopRelevant') {
            $department = [string]$relevantOUs[$relevantOUs.Count - 1]
        }
        else {
            $department = [string]$relevantOUs[0]
        }
    }

    return [pscustomobject]@{
        DepartmentOU = $department
        OUPath       = ($ous -join ' / ')
    }
}

function Protect-CsvCell {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    $formulaAfterOptionalWhitespace = '^[\x00-\x20]*[=+\-@\uFF1D\uFF0B\uFF0D\uFF20]'

    if ($text -match '^[\t\r\n]' -or $text -match $formulaAfterOptionalWhitespace) {
        return "'$text"
    }

    return $text
}

function Resolve-InventoryOutputPath {
    param(
        [AllowEmptyString()][string]$RequestedPath,
        [switch]$AllowNetworkOutput
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        $reportRoot = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'AD-ATLAS-Reports'
        $fileName = 'AD-ATLAS_{0}_{1}.csv' -f `
            (Get-Date).ToString('yyyyMMdd_HHmmss'), `
            ([guid]::NewGuid().ToString('N').Substring(0, 6))
        $RequestedPath = Join-Path -Path $reportRoot -ChildPath $fileName
    }

    $provider = $null
    $drive = $null
    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $RequestedPath,
        [ref]$provider,
        [ref]$drive
    )

    if ($provider.Name -ne 'FileSystem') {
        throw "OutputPath must use the FileSystem provider: '$RequestedPath'."
    }

    if (-not $AllowNetworkOutput -and $resolvedPath.StartsWith('\\')) {
        throw "Direct UNC output requires -AllowNetworkOutput: '$RequestedPath'."
    }

    if ([System.IO.Path]::GetExtension($resolvedPath) -ine '.csv') {
        throw "OutputPath must end in .csv: '$resolvedPath'."
    }

    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        throw "OutputPath points to a directory: '$resolvedPath'. Select a CSV filename."
    }

    if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
        throw "Output file already exists: '$resolvedPath'. Select a new filename to avoid overwriting data."
    }

    $parentDirectory = Split-Path -Path $resolvedPath -Parent
    if ([string]::IsNullOrWhiteSpace($parentDirectory)) {
        throw "Could not determine the parent directory for '$resolvedPath'."
    }

    if (-not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parentDirectory -Force -ErrorAction Stop
    }

    return $resolvedPath
}

function Show-InventorySummary {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'Write-Host is used only for the small interactive console summary.'
    )]
    param(
        [int]$ComputerCount,
        [int]$DepartmentCount,
        [int]$UnclassifiedCount,
        [string]$Path
    )

    $asciiArt = @(
        '    _  _____ _        _    ____'
        '   / \|_   _| |      / \  / ___|'
        '  / _ \ | | | |     / _ \ \___ \'
        ' / ___ \| | | |___ / ___ \ ___) |'
        '/_/   \_\_| |_____/_/   \_\____/'
    )

    $artWidth = [int]($asciiArt | Measure-Object -Property Length -Maximum).Maximum
    $separator = '-' * $artWidth
    $consoleWidth = 80

    try {
        if ([Console]::WindowWidth -gt 0) {
            $consoleWidth = [Console]::WindowWidth
        }
    }
    catch {
        $consoleWidth = 80
    }

    $paddingCount = [int][Math]::Max(0, [Math]::Floor(($consoleWidth - $separator.Length) / 2))
    $leftPadding = ' ' * $paddingCount

    Write-Host -Object ''
    foreach ($line in $asciiArt) {
        Write-Host -Object ($leftPadding + $line.TrimEnd()) -ForegroundColor White
    }
    Write-Host -Object ($leftPadding + 'ACTIVE DIRECTORY OU MAP') -ForegroundColor DarkGray
    Write-Host -Object ($leftPadding + ("{0}  |  v{1}" -f $script:VendorName, $script:ToolVersion)) -ForegroundColor DarkGray
    Write-Host -Object ($leftPadding + $separator) -ForegroundColor DarkGray
    Write-Host -Object ($leftPadding + ' Computers      : ') -NoNewline -ForegroundColor DarkGray
    Write-Host -Object $ComputerCount -ForegroundColor Green
    Write-Host -Object ($leftPadding + ' Departments    : ') -NoNewline -ForegroundColor DarkGray
    Write-Host -Object $DepartmentCount -ForegroundColor Green
    Write-Host -Object ($leftPadding + ' Unclassified   : ') -NoNewline -ForegroundColor DarkGray
    Write-Host -Object $UnclassifiedCount -ForegroundColor Green
    Write-Host -Object ($leftPadding + $separator) -ForegroundColor DarkGray
    Write-Host -Object ($leftPadding + ' CSV            : ') -NoNewline -ForegroundColor DarkGray
    Write-Host -Object $Path -ForegroundColor White
    Write-Host -Object ''
}

# Dot-sourcing loads the helper functions without running the inventory.
if ($MyInvocation.InvocationName -eq '.') {
    return
}

if (-not $AllComputers) {
    throw 'Use -AllComputers to confirm that you want to inventory every computer object in the current domain.'
}

try {
    Import-Module -Name ActiveDirectory -ErrorAction Stop
}
catch {
    throw 'The ActiveDirectory PowerShell module was not found or could not be loaded. Install the RSAT Active Directory tools and try again.'
}

$resultLimit = $MaxComputers + 1
$computers = @(
    Get-ADComputer -Filter '*' -ResultSetSize $resultLimit -ErrorAction Stop
)

if ($computers.Count -gt $MaxComputers) {
    throw @"
The domain contains more than $MaxComputers computer objects. No CSV was created.
Review the expected domain size, then rerun with a deliberate higher limit, for example:
  .\Get-AD-ATLAS.ps1 -AllComputers -MaxComputers 50000
"@
}

$rows = @(
    foreach ($computer in $computers) {
        $ouInfo = Resolve-DepartmentOU `
            -DistinguishedName ([string]$computer.DistinguishedName) `
            -IgnoreOUs $IgnoreOUs `
            -Strategy $DepartmentStrategy

        $department = [string]$ouInfo.DepartmentOU
        if ([string]::IsNullOrWhiteSpace($department)) {
            $department = '[Unclassified]'
        }

        [pscustomobject][ordered]@{
            Department             = $department
            ComputerName           = [string]$computer.Name
            OrganizationalUnitPath = [string]$ouInfo.OUPath
        }
    }
)
$rows = @($rows | Sort-Object -Property Department, ComputerName)

$resolvedOutputPath = Resolve-InventoryOutputPath `
    -RequestedPath $OutputPath `
    -AllowNetworkOutput:$AllowNetworkOutput

$protectedRows = @(
    foreach ($row in $rows) {
        [pscustomobject][ordered]@{
            Department             = Protect-CsvCell -Value $row.Department
            ComputerName           = Protect-CsvCell -Value $row.ComputerName
            OrganizationalUnitPath = Protect-CsvCell -Value $row.OrganizationalUnitPath
        }
    }
)

if ($protectedRows.Count -eq 0) {
    Out-File `
        -LiteralPath $resolvedOutputPath `
        -Encoding UTF8 `
        -NoClobber `
        -InputObject '"Department","ComputerName","OrganizationalUnitPath"' `
        -ErrorAction Stop
}
else {
    $protectedRows |
        Export-Csv -LiteralPath $resolvedOutputPath -NoTypeInformation -Encoding UTF8 -NoClobber -ErrorAction Stop
}

$departmentCount = @(
    $rows |
        Where-Object -FilterScript { $_.Department -ne '[Unclassified]' } |
        ForEach-Object -Process { [string]$_.Department } |
        Sort-Object -Unique
).Count
$unclassifiedCount = @($rows | Where-Object -FilterScript { $_.Department -eq '[Unclassified]' }).Count

Show-InventorySummary `
    -ComputerCount $rows.Count `
    -DepartmentCount $departmentCount `
    -UnclassifiedCount $unclassifiedCount `
    -Path $resolvedOutputPath
