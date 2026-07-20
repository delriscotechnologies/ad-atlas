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

AD ATLAS is one PowerShell script that inventories the computer objects in the current Active Directory domain and selects a department candidate using explicit OU rules.

Each successful run creates one CSV with the computer name, the selected department label, and the OU hierarchy used for review. It does not build a database, contact endpoint hosts, or write unrelated system metadata to the report.

> Use AD ATLAS only in Active Directory environments you own or are explicitly authorized to inventory. A real report contains internal computer names and OU structure; never commit one to a public repository.

## Quick Start

You need a domain-connected Windows host with Windows PowerShell 5.1, the RSAT Active Directory module, and permission to read computer objects. Domain Admin is not required; the script uses your current Windows identity and never asks for credentials.

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

When the inventory finishes, the terminal shows how many computers were found, how many distinct classified department labels were selected, how many objects remain unclassified, and where the report was saved. `[Unclassified]` rows remain in the CSV but are not counted as departments.

```text
    _  _____ _        _    ____
   / \|_   _| |      / \  / ___|
  / _ \ | | | |     / _ \ \___ \
 / ___ \| | | |___ / ___ \ ___) |
/_/   \_\_| |_____/_/   \_\____/
ACTIVE DIRECTORY OU MAP
Del Risco Technologies  |  v1.3.1
---------------------------------
 Computers      : 342
 Departments    : 12
 Unclassified   : 4
---------------------------------
 CSV            : C:\Users\user\Documents\AD-ATLAS-Reports\AD-ATLAS_20260715_193500_a1b2c3.csv
```

The CSV stays deliberately small. `Department` contains the selected grouping, `ComputerName` identifies the object, and `OrganizationalUnitPath` preserves the OU hierarchy used to review that choice. A report looks like this:

```csv
"Department","ComputerName","OrganizationalUnitPath"
"Finance","FIN-LAP-001","Laptops / Finance / Devices"
"Human Resources","HR-WS-002","Workstations / Human Resources / Devices"
"Research, Development","LAB-WS-009","Workstations / Research, Development / Devices"
"[Unclassified]","KIOSK-004",""
```

## How Department Mapping Works

Consider this Distinguished Name:

```text
CN=FIN-LAP-001,OU=Laptops,OU=Finance,OU=Devices,DC=company,DC=com
```

AD ATLAS applies a transparent heuristic rather than determining organizational meaning. Every OU not present in `IgnoreOUs` becomes a candidate, and the configured strategy selects the closest or highest candidate. With the default rules, `Laptops` and `Devices` are skipped and the example produces:

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
| `-AllComputers` | Explicitly confirms the domain-wide inventory; it is an operator guardrail, not an authorization boundary |
| `-IgnoreOUs` | Defines technical containers that should not become departments |
| `-DepartmentStrategy` | Chooses the closest or highest relevant OU |
| `-MaxComputers` | Limits the AD result request to the configured value plus one and stops before creating an oversized report |
| `-OutputPath` | Writes the CSV to a specific local or mounted filesystem path |
| `-AllowNetworkOutput` | Explicitly permits a direct UNC output path, which is rejected by default |

If the domain contains more objects than `-MaxComputers`, AD ATLAS stops without creating a partial report. It also refuses to overwrite an existing output file.

A direct UNC path requires explicit confirmation:

```powershell
.\Get-AD-ATLAS.ps1 `
  -AllComputers `
  -OutputPath '\\fileserver\reports\AD-ATLAS.csv' `
  -AllowNetworkOutput
```

## Safety and Privacy

- Uses `Get-ADComputer` as its only Active Directory query and requests no more than `MaxComputers + 1` results.
- Selects only `Name` and `DistinguishedName` from returned AD objects.
- Exports only the derived `Department`, `ComputerName`, and `OrganizationalUnitPath` fields.
- Does not modify Active Directory, connect to endpoints, run remote commands, or handle credentials.
- Mitigates common spreadsheet-formula prefixes before writing CSV cells.
- Accepts only filesystem output paths, blocks direct UNC paths by default, and refuses accidental overwrites.
- Writes through a same-directory temporary file so the final CSV appears atomically. Normal failures remove it; an abrupt process or system termination can leave an ignored `.AD-ATLAS-*.tmp` file that should be deleted securely.
- Keeps unclassified computers visible instead of silently dropping them.

Public CI parses the script and runs PSScriptAnalyzer under Windows PowerShell 5.1 and PowerShell 7. It does not contact a domain.

Store real reports and any residual temporary files outside public repositories, restrict access to them, and remove them according to your organization's retention policy.

See [SECURITY.md](SECURITY.md) for reporting and handling guidance.

## License

AD ATLAS is available under the [MIT License](LICENSE).
