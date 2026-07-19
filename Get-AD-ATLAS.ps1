#Requires -Version 5.1

<#
.SYNOPSIS
Builds AD ATLAS: a CSV map of Active Directory computers and department OUs.

.DESCRIPTION
Retrieves Active Directory computer objects, retains their names and Distinguished
Names, selects a department candidate using explicit OU rules, and writes one CSV file.

The Active Directory operation is read-only. The script calls Get-ADComputer and
does not connect to endpoints or modify Active Directory.

.PARAMETER AllComputers
Confirms that the query should include all computer objects in the current domain.
This is an operator confirmation guardrail, not an authorization boundary.

.PARAMETER MaxComputers
Safety limit for the number of computer objects. The default is 10,000. The Active
Directory query requests at most this value plus one object so the script can detect
and stop when the limit is exceeded.

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

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$AllComputers,

    [Parameter()]
    [ValidateRange(1, 1000000)]
    [int]$MaxComputers = 10000,

    [Parameter()]
    [ValidateSet('ClosestRelevant', 'TopRelevant')]
    [string]$DepartmentStrategy = 'ClosestRelevant',

    [Parameter()]
    [AllowEmptyCollection()]
    [string[]]$IgnoreOUs = @(
        'Devices', 'Computers', 'Workstations', 'Laptops', 'Desktops',
        'Servers', 'Clients', 'Endpoints', 'Managed Devices'
    ),

    [Parameter()]
    [AllowEmptyString()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$AllowNetworkOutput
)

Set-StrictMode -Version Latest

$script:ToolVersion = '1.3.1'
$script:VendorName = 'Del Risco Technologies'

function Split-DistinguishedName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DistinguishedName)

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
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$DistinguishedName,

        [AllowEmptyCollection()]
        [string[]]$IgnoreOUs,

        [Parameter(Mandatory = $true)]
        [ValidateSet('ClosestRelevant', 'TopRelevant')]
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
            $ignored = $false
            foreach ($ignoredOU in @($IgnoreOUs)) {
                if ($ignoredOU -ieq $ou) {
                    $ignored = $true
                    break
                }
            }

            if (-not $ignored) {
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

function ConvertTo-DepartmentInventoryRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Computer,
        [Parameter(Mandatory = $true)][ValidateSet('ClosestRelevant', 'TopRelevant')][string]$Strategy,
        [AllowEmptyCollection()][string[]]$IgnoreOUs
    )

    $computerName = [string]$Computer.Name
    $distinguishedName = [string]$Computer.DistinguishedName
    $ouInfo = Resolve-DepartmentOU `
        -DistinguishedName $distinguishedName `
        -IgnoreOUs $IgnoreOUs `
        -Strategy $Strategy

    $department = [string]$ouInfo.DepartmentOU
    if ([string]::IsNullOrWhiteSpace($department)) {
        $department = '[Unclassified]'
    }

    return [pscustomobject][ordered]@{
        Department             = $department
        ComputerName           = $computerName
        OrganizationalUnitPath = [string]$ouInfo.OUPath
    }
}

function Protect-CsvCell {
    [CmdletBinding()]
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

function Get-ClassifiedDepartmentCount {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows)

    return @(
        $Rows |
            Where-Object Department -ne '[Unclassified]' |
            ForEach-Object { [string]$_.Department } |
            Sort-Object -Unique
    ).Count
}

function Resolve-InventoryOutputPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$RequestedPath,
        [switch]$AllowNetworkOutput
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        $reportRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AD-ATLAS-Reports'
        $uniqueName = 'AD-ATLAS_{0}_{1}.csv' -f `
            (Get-Date).ToString('yyyyMMdd_HHmmss'), `
            ([guid]::NewGuid().ToString('N').Substring(0, 6))
        $RequestedPath = Join-Path $reportRoot $uniqueName
    }

    $uncPattern = '^(?:Microsoft\.PowerShell\.Core\\FileSystem::)?\\\\'
    if (-not $AllowNetworkOutput.IsPresent -and $RequestedPath -match $uncPattern) {
        throw "Direct UNC output requires -AllowNetworkOutput: '$RequestedPath'."
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

    if (-not $AllowNetworkOutput.IsPresent -and $resolvedPath.StartsWith('\\')) {
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

function Export-DepartmentInventoryCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $protectedRows = @(
        foreach ($row in $Rows) {
            [pscustomobject][ordered]@{
                Department             = Protect-CsvCell -Value $row.Department
                ComputerName           = Protect-CsvCell -Value $row.ComputerName
                OrganizationalUnitPath = Protect-CsvCell -Value $row.OrganizationalUnitPath
            }
        }
    )

    $parentDirectory = Split-Path -Path $Path -Parent
    $temporaryName = '.AD-ATLAS-{0}.tmp' -f ([guid]::NewGuid().ToString('N'))
    $temporaryPath = Join-Path $parentDirectory $temporaryName

    try {
        if ($protectedRows.Count -eq 0) {
            '"Department","ComputerName","OrganizationalUnitPath"' |
                Set-Content -LiteralPath $temporaryPath -Encoding UTF8 -ErrorAction Stop
        }
        else {
            $protectedRows |
                Export-Csv -LiteralPath $temporaryPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        }

        # The two-argument Move operation fails if another process created the
        # destination after Resolve-InventoryOutputPath validated it.
        [System.IO.File]::Move($temporaryPath, $Path)
    }
    finally {
        # This removes the temporary report after normal failures. A process kill or
        # system crash can still leave the ignored .AD-ATLAS-*.tmp file behind.
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Import-ActiveDirectoryModule {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'The ActiveDirectory PowerShell module was not found. Install the RSAT Active Directory tools and try again.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
}

function Get-DomainComputerInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$MaxComputers)

    $resultLimit = $MaxComputers + 1
    $computers = @(
        Get-ADComputer -Filter '*' -ResultSetSize $resultLimit -ErrorAction Stop |
            Select-Object -First $resultLimit -Property Name, DistinguishedName
    )
    if ($computers.Count -gt $MaxComputers) {
        throw @"
The domain contains more than $MaxComputers computer objects. No CSV was created.
Review the expected domain size, then rerun with a deliberate higher limit, for example:
  .\Get-AD-ATLAS.ps1 -AllComputers -MaxComputers 50000
"@
    }

    return $computers
}

function Show-InventorySummary {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'Write-Host is used only for the small interactive console summary.'
    )]
    param(
        [Parameter(Mandatory = $true)][int]$ComputerCount,
        [Parameter(Mandatory = $true)][int]$DepartmentCount,
        [Parameter(Mandatory = $true)][int]$UnclassifiedCount,
        [Parameter(Mandatory = $true)][string]$Path
    )

    # Standard wordmark generated with TAAG (patorjk.com/software/taag).
    $asciiArt = @(
        '    _  _____ _        _    ____'
        '   / \|_   _| |      / \  / ___|'
        '  / _ \ | | | |     / _ \ \___ \'
        ' / ___ \| | | |___ / ___ \ ___) |'
        '/_/   \_\_| |_____/_/   \_\____/'
    )
    $artWidth = [int](
        $asciiArt |
            ForEach-Object { $_.Length } |
            Measure-Object -Maximum
    ).Maximum
    $separator = '-' * $artWidth
    $consoleWidth = 80
    try {
        if ([Console]::WindowWidth -gt 0) {
            $consoleWidth = [Console]::WindowWidth
        }
    }
    catch {
        # Some redirected and non-interactive hosts do not expose WindowWidth.
        $consoleWidth = 80
    }
    $paddingCount = [int][Math]::Max(0, [Math]::Floor(($consoleWidth - $separator.Length) / 2))
    $leftPadding = ' ' * $paddingCount

    Write-Host ''
    foreach ($line in $asciiArt) {
        Write-Host ($leftPadding + $line.TrimEnd()) -ForegroundColor White
    }
    Write-Host ($leftPadding + 'ACTIVE DIRECTORY OU MAP') -ForegroundColor DarkGray
    Write-Host ($leftPadding + ("{0}  |  v{1}" -f $script:VendorName, $script:ToolVersion)) -ForegroundColor DarkGray
    Write-Host ($leftPadding + $separator) -ForegroundColor DarkGray
    Write-Host ($leftPadding + ' Computers      : ') -NoNewline -ForegroundColor DarkGray
    Write-Host $ComputerCount -ForegroundColor Green
    Write-Host ($leftPadding + ' Departments    : ') -NoNewline -ForegroundColor DarkGray
    Write-Host $DepartmentCount -ForegroundColor Green
    Write-Host ($leftPadding + ' Unclassified   : ') -NoNewline -ForegroundColor DarkGray
    Write-Host $UnclassifiedCount -ForegroundColor Green
    Write-Host ($leftPadding + $separator) -ForegroundColor DarkGray
    Write-Host ($leftPadding + ' CSV            : ') -NoNewline -ForegroundColor DarkGray
    Write-Host $Path -ForegroundColor White
    Write-Host ''
}

function Invoke-AdComputerDepartmentInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$MaxComputers,
        [Parameter(Mandatory = $true)][ValidateSet('ClosestRelevant', 'TopRelevant')][string]$Strategy,
        [AllowEmptyCollection()][string[]]$IgnoreOUs,
        [AllowEmptyString()][string]$OutputPath,
        [switch]$AllowNetworkOutput
    )

    Import-ActiveDirectoryModule
    $computers = @(Get-DomainComputerInventory -MaxComputers $MaxComputers)

    $rows = @(
        foreach ($computer in $computers) {
            ConvertTo-DepartmentInventoryRow `
                -Computer $computer `
                -Strategy $Strategy `
                -IgnoreOUs $IgnoreOUs
        }
    )
    $rows = @($rows | Sort-Object Department, ComputerName)

    $resolvedOutputPath = Resolve-InventoryOutputPath `
        -RequestedPath $OutputPath `
        -AllowNetworkOutput:$AllowNetworkOutput
    Export-DepartmentInventoryCsv -Rows $rows -Path $resolvedOutputPath

    $departmentCount = Get-ClassifiedDepartmentCount -Rows $rows
    $unclassifiedCount = @($rows | Where-Object Department -eq '[Unclassified]').Count
    Show-InventorySummary `
        -ComputerCount $rows.Count `
        -DepartmentCount $departmentCount `
        -UnclassifiedCount $unclassifiedCount `
        -Path $resolvedOutputPath
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $AllComputers.IsPresent) {
        throw 'Use -AllComputers to confirm that you want to inventory every computer object in the current domain.'
    }

    Invoke-AdComputerDepartmentInventory `
        -MaxComputers $MaxComputers `
        -Strategy $DepartmentStrategy `
        -IgnoreOUs $IgnoreOUs `
        -OutputPath $OutputPath `
        -AllowNetworkOutput:$AllowNetworkOutput
}
