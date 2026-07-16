<h1 align="center">AD ATLAS</h1>

<p align="center">
  A read-only map from Active Directory computers to the OUs that matter.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#what-you-get">Output</a> ·
  <a href="#how-department-mapping-works">Mapping</a> ·
  <a href="SECURITY.md">Security</a>
</p>

---

AD ATLAS is one PowerShell script that inventories the computer objects in the current Active Directory domain and groups them by the most relevant department OU.

Each run creates one CSV with the computer name, the selected department, and the full OU path behind that decision. It does not build a database, contact endpoint hosts, or collect unrelated system metadata.

> Use AD ATLAS only in Active Directory environments you own or are explicitly authorized to inventory. A real report contains internal computer names and OU structure; never commit one to a public repository.

## Quick Start

You need Windows PowerShell 5.1 or newer, domain connectivity, the RSAT Active Directory module, and permission to read computer objects. Domain Admin is not required; the script uses your current Windows identity and never asks for credentials.

```powershell
git clone https://github.com/delriscotechnologies/ad-atlas.git
cd ad-atlas
.\Get-AD-ATLAS.ps1 -AllComputers
```

The report is written to a timestamped file under:

```text
Documents\AD-ATLAS-Reports\
```

## What You Get

When the inventory finishes, the terminal gives you a quick sense of the domain: how many computers were found, how many department groups were identified, how many objects still need classification, and where the report was saved.

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

The CSV stays deliberately small. `Department` is the useful grouping, `ComputerName` identifies the object, and `OrganizationalUnitPath` shows exactly why that grouping was chosen. See the [synthetic sample report](sample-output/AD-ATLAS.csv) for the complete schema.

## How Department Mapping Works

Consider this Distinguished Name:

```text
CN=FIN-LAP-001,OU=Laptops,OU=Finance,OU=Devices,DC=company,DC=com
```

`Laptops` and `Devices` are technical containers, so the default `ClosestRelevant` strategy skips them and produces:

```text
Department:             Finance
ComputerName:           FIN-LAP-001
OrganizationalUnitPath: Laptops / Finance / Devices
```

If your organization uses different technical containers, replace the ignored list:

```powershell
.\Get-AD-ATLAS.ps1 `
  -AllComputers `
  -IgnoreOUs 'Devices','Computers','Workstations','Laptops','Desktops','Servers'
```

If departments are represented by the highest relevant OU instead, use:

```powershell
.\Get-AD-ATLAS.ps1 -AllComputers -DepartmentStrategy TopRelevant
```

Objects that cannot be associated with a department remain visible as `[Unclassified]`.

## Useful Controls

| Option | Purpose |
| --- | --- |
| `-AllComputers` | Explicitly confirms the domain-wide inventory |
| `-IgnoreOUs` | Defines technical containers that should not become departments |
| `-DepartmentStrategy` | Chooses the closest or highest relevant OU |
| `-MaxComputers` | Raises or lowers the default 10,000-object safety limit |
| `-OutputPath` | Writes the CSV to a specific local or mounted filesystem path |

If the query exceeds `-MaxComputers`, AD ATLAS stops without creating a partial report. It also refuses to overwrite an existing output file.

## Safety and Privacy

- Uses only the read-only `Get-ADComputer` command.
- Reads and retains only `Name` and `DistinguishedName`.
- Does not modify Active Directory, connect to endpoints, run remote commands, or handle credentials.
- Neutralizes spreadsheet-formula prefixes before writing CSV cells.
- Accepts only filesystem output paths and refuses accidental overwrites.
- Keeps unclassified computers visible instead of silently dropping them.

Store real reports outside public repositories, restrict access to them, and remove them according to your organization's retention policy. See [SECURITY.md](SECURITY.md) for reporting and handling guidance.

## Development

The Pester suite covers DN parsing, OU selection, CSV structure, spreadsheet-formula hardening, and the computer-count safety limit. CI runs it in both Windows PowerShell and PowerShell 7, followed by PSScriptAnalyzer.

```powershell
Invoke-Pester -Path .\tests
```

## License

AD ATLAS is available under the [MIT License](LICENSE).
