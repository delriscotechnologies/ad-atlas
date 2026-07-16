<p align="center">
  <strong>AD ATLAS</strong><br>
  <sub>Map every Active Directory computer to the OU that matters.</sub>
</p>

AD ATLAS is a single PowerShell script that inventories every computer object in the current Active Directory domain and organizes the results by the most relevant department OU.

It collects only what it needs:

- computer name
- department derived from OU placement
- complete OU path used to verify that decision

It does not collect operating-system, DNS, account-status, or logon metadata. It does not generate risk signals or scores.

> Use this script only in Active Directory environments you own or are explicitly authorized to inventory. The generated CSV contains internal computer names and OU structure. Never commit a real report to a public repository.

## requirements

- Windows PowerShell 5.1 or newer
- connectivity to the domain
- the RSAT Active Directory PowerShell module
- an account allowed to read AD computer objects

Domain Admin is not required. The script uses the current Windows identity and never asks for credentials.

## one command

```powershell
.\Get-AD-ATLAS.ps1 -AllComputers
```

The script creates one timestamped CSV under:

```text
Documents\AD-ATLAS-Reports\
```

The CSV is sorted first by department and then by computer name:

```csv
"Department","ComputerName","OrganizationalUnitPath"
"Finance","FIN-LAP-001","Laptops / Finance / Devices"
"Human Resources","HR-WS-002","Workstations / Human Resources / Devices"
```

The console centers the Standard ATLAS wordmark automatically using the current PowerShell window width. The wordmark is printed in bright white; supporting information stays visually secondary:

```text
    _  _____ _        _    ____
   / \|_   _| |      / \  / ___|
  / _ \ | | | |     / _ \ \___ \
 / ___ \| | | |___ / ___ \ ___) |
/_/   \_\_| |_____/_/   \_\____/
ACTIVE DIRECTORY OU MAP
Del Risco Technologies  |  v1.3.0
---------------------------------
 Computers      : 342
 Departments    : 12
 Unclassified   : 4
---------------------------------
 CSV            : C:\Users\user\Documents\AD-ATLAS-Reports\AD-ATLAS_20260715_193500_a1b2c3.csv
```

The wordmark was generated with [TAAG](https://patorjk.com/software/taag/) using the Standard font.

## how department mapping works

Given this computer:

```text
CN=FIN-LAP-001,OU=Laptops,OU=Finance,OU=Devices,DC=company,DC=com
```

The default technical-container list ignores `Laptops` and `Devices`, so the result is:

```text
Department:             Finance
ComputerName:           FIN-LAP-001
OrganizationalUnitPath: Laptops / Finance / Devices
```

The default `ClosestRelevant` strategy selects the closest OU that is not in the ignored list. Customize technical containers when the organization uses different names:

```powershell
.\Get-AD-ATLAS.ps1 `
  -AllComputers `
  -IgnoreOUs 'Devices','Computers','Workstations','Laptops','Desktops','Servers'
```

If the organization identifies departments using the highest relevant OU instead:

```powershell
.\Get-AD-ATLAS.ps1 `
  -AllComputers `
  -DepartmentStrategy TopRelevant
```

Computers that cannot be associated with a department appear as `[Unclassified]` so they are visible instead of silently omitted.

## domains larger than 10,000 computers

The default safety limit is 10,000. If the query crosses that limit, the script stops and does not create a partial CSV.

After confirming the expected size of the domain, rerun with an intentional higher limit:

```powershell
.\Get-AD-ATLAS.ps1 `
  -AllComputers `
  -MaxComputers 50000
```

The accepted range is 1 to 1,000,000 computers.

## choose the CSV location

```powershell
.\Get-AD-ATLAS.ps1 `
  -AllComputers `
  -OutputPath 'C:\Reports\AD-ATLAS.csv'
```

For safety, the script refuses to overwrite an existing file.

## what it does not do

- modify, move, disable, or delete Active Directory objects
- connect to endpoint hosts
- execute remote commands
- scan ports or vulnerabilities
- collect operating system, DNS, enabled state, or logon activity
- generate risk signals, severity levels, or security conclusions

## security controls

- uses only the read-only `Get-ADComputer` command
- retains and exports only the computer name and Distinguished Name needed for OU mapping
- requires the explicit `-AllComputers` confirmation switch
- stops at 10,000 results unless the operator raises the limit
- neutralizes spreadsheet-formula prefixes in CSV cells
- accepts output paths only from the local or mounted filesystem
- refuses accidental output-file overwrites
- contains no hardcoded credentials or credential parameter

## downloaded script

Review the script before running it. If Windows marks a reviewed download as blocked:

```powershell
Get-FileHash .\Get-AD-ATLAS.ps1 -Algorithm SHA256
Unblock-File .\Get-AD-ATLAS.ps1
```

Security reports should follow [SECURITY.md](SECURITY.md).
