#requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$AllComputers,
    [ValidateRange(1, 1000000)][int]$MaxComputers = 10000,
    [ValidateSet('ClosestRelevant', 'TopRelevant')]
    [string]$DepartmentStrategy = 'ClosestRelevant',
    [AllowEmptyCollection()][string[]]$IgnoreOUs = @(
        'Devices', 'Computers', 'Workstations', 'Laptops', 'Desktops',
        'Servers', 'Clients', 'Endpoints', 'Managed Devices'
    ),
    [AllowEmptyString()][string]$OutputPath,
    [switch]$AllowNetworkOutput
)

Set-StrictMode -Version Latest

function Split-CanonicalName {
    param([string]$Value)

    $parts = [Collections.Generic.List[string]]::new()
    $start = $slashes = 0
    for ($i = 0; $i -lt $Value.Length; $i++) {
        if ($Value[$i] -eq '\') {
            $slashes++
            continue
        }
        if ($Value[$i] -eq '/' -and $slashes % 2 -eq 0) {
            $parts.Add($Value.Substring($start, $i - $start))
            $start = $i + 1
        }
        $slashes = 0
    }
    $parts.Add($Value.Substring($start))
    $parts
}

function Resolve-Department {
    param(
        [AllowEmptyString()][string]$CanonicalName,
        [Collections.Generic.HashSet[string]]$IgnoredOUs,
        [string]$Strategy
    )

    $parts = @(Split-CanonicalName $CanonicalName)
    $ous = @(if ($parts.Count -gt 2) {
        @($parts[1..($parts.Count - 2)] | ForEach-Object { $_.Replace('\/', '/').Replace('\\', '\') })
    }
    else { @() })
    [array]::Reverse($ous)

    $department = ''
    foreach ($ou in $ous) {
        if ($IgnoredOUs.Contains($ou)) { continue }
        $department = $ou
        if ($Strategy -eq 'ClosestRelevant') { break }
    }

    [pscustomobject]@{
        Department = $department
        OUPath     = $ous -join ' / '
    }
}

function Protect-CsvCell {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    if ($text -match '^(?:[\t\r\n]|[\x00-\x20]*[=+\-@\uFF1D\uFF0B\uFF0D\uFF20])') { return "'$text" }
    $text
}

function Resolve-OutputPath {
    param(
        [AllowEmptyString()][string]$RequestedPath,
        [switch]$AllowNetworkOutput
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        $root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AD-ATLAS-Reports'
        $name = 'AD-ATLAS_{0}_{1}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'),
            ([guid]::NewGuid().ToString('N').Substring(0, 6))
        $RequestedPath = Join-Path $root $name
    }

    $provider = $drive = $null
    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $RequestedPath, [ref]$provider, [ref]$drive
    )
    if ($provider.Name -ne 'FileSystem') { throw "OutputPath must use FileSystem: '$RequestedPath'." }
    $network = $path.StartsWith('\\') -or ($null -ne $drive -and [string]$drive.DisplayRoot -like '\\*')
    if ($network -and -not $AllowNetworkOutput) { throw "Network output requires -AllowNetworkOutput: '$RequestedPath'." }
    if ([IO.Path]::GetExtension($path) -ine '.csv') { throw "OutputPath must end in .csv: '$path'." }
    if (Test-Path -LiteralPath $path) { throw "Output path already exists: '$path'." }
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    $path
}

function Export-Inventory {
    param(
        [AllowEmptyCollection()][object[]]$Rows,
        [string]$Path
    )

    $temp = '{0}.{1}.tmp' -f $Path, [guid]::NewGuid().ToString('N')
    try {
        if ($Rows.Count) {
            $Rows | ForEach-Object {
                [pscustomobject][ordered]@{
                    Department             = Protect-CsvCell $_.Department
                    ComputerName           = Protect-CsvCell $_.ComputerName
                    OrganizationalUnitPath = Protect-CsvCell $_.OrganizationalUnitPath
                }
            } | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding UTF8 -NoClobber -ErrorAction Stop
        }
        else {
            $header = '"Department","ComputerName","OrganizationalUnitPath"' + [Environment]::NewLine
            [IO.File]::WriteAllText($temp, $header, [Text.UTF8Encoding]::new($true))
        }
        [IO.File]::Move($temp, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference = 'Stop'
if (-not $AllComputers) { throw 'Use -AllComputers to confirm the full-domain inventory.' }

try {
    Import-Module (Join-Path $PSHOME 'Modules\ActiveDirectory\ActiveDirectory.psd1') -ErrorAction Stop
}
catch {
    throw 'Use 64-bit Windows PowerShell 5.1 with RSAT Active Directory tools installed.'
}

$ignored = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($ou in $IgnoreOUs) { if (-not [string]::IsNullOrWhiteSpace($ou)) { $null = $ignored.Add($ou) } }
$departments = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$unclassified = 0

$searchBase = [string](Get-ADRootDSE -ErrorAction Stop).DefaultNamingContext
if ([string]::IsNullOrWhiteSpace($searchBase)) { throw 'Active Directory returned no default naming context.' }
$computers = @(Get-ADComputer -Filter '*' -SearchBase $searchBase -Properties CanonicalName `
        -ResultSetSize ($MaxComputers + 1) -ErrorAction Stop)
if ($computers.Count -gt $MaxComputers) {
    throw "The domain contains more than $MaxComputers computers. No CSV was created. Increase -MaxComputers deliberately."
}

$rows = @(foreach ($computer in $computers) {
        $info = Resolve-Department -CanonicalName ([string]$computer.CanonicalName) -IgnoredOUs $ignored -Strategy $DepartmentStrategy
        $department = [string]$info.Department
        if ([string]::IsNullOrWhiteSpace($department)) {
            $department = '[Unclassified]'
            $unclassified++
        }
        else { $null = $departments.Add($department) }

        [pscustomobject][ordered]@{
            Department             = $department
            ComputerName           = [string]$computer.Name
            OrganizationalUnitPath = [string]$info.OUPath
        }
    })
$rows = @($rows | Sort-Object Department, ComputerName)

$path = Resolve-OutputPath -RequestedPath $OutputPath -AllowNetworkOutput:$AllowNetworkOutput
Export-Inventory -Rows $rows -Path $path
Write-Information -MessageData ("`nAD ATLAS | v1.5.0`nComputers: $($rows.Count)`nDepartments: $($departments.Count)`nUnclassified: $unclassified`nCSV: $path`n") -InformationAction Continue
