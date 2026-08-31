<h1 align="center">AD ATLAS</h1>

<p align="center">
  A read-only map of Active Directory computers and their OU structure.
</p>

---

AD ATLAS is a PowerShell script that inventories computer objects in the current Active Directory domain and maps them to a department candidate using the AD `CanonicalName` hierarchy.

> Use AD ATLAS only in Active Directory environments you own or are authorized to inventory.

## Install

Requires PowerShell 5.1, RSAT Active Directory tools, and domain access. A standard domain account is sufficient; Domain Admin privileges are not required.

```powershell
git clone https://github.com/delriscotechnologies/ad-atlas.git
cd ad-atlas
.\Get-AD-ATLAS.ps1 -AllComputers
```

## What it does

1. Reads computer objects from Active Directory.
2. Builds the OU path for each computer.
3. Selects a department candidate using configurable OU rules.
4. Exports the results to CSV.

## Output

The terminal shows the inventory summary and report location:

```text
AD ATLAS | v1.5.0
Computers    : 342
Departments  : 12
Unclassified : 4
CSV          : C:\Users\user\Documents\AD-ATLAS-Reports\AD-ATLAS_20260715_193500_a1b2c3.csv
```

The CSV contains:

```csv
"Department","ComputerName","OrganizationalUnitPath"
"Finance","FIN-LAP-001","Laptops / Finance / Devices"
"Human Resources","HR-WS-002","Workstations / Human Resources / Devices"
"[Unclassified]","KIOSK-004",""
```

Reports are saved under Documents\AD-ATLAS-Reports unless a different output path is provided.

## Demo

```powershell
.\Get-AD-ATLAS.ps1 -AllComputers
```

Example mapping:

```text
Department:             Finance
ComputerName:           FIN-LAP-001
OrganizationalUnitPath: Laptops / Finance / Devices
```

## Scope and limits

- Read-only Active Directory inventory.
- Does not modify Active Directory or connect to endpoint computers.
- Uses the current Windows identity and does not request credentials.
- Queries the domain's explicit default naming context, even when launched from an `AD:` drive.
- Department mapping is based on OU structure and should be reviewed for your environment.
- Real reports may contain internal computer names and OU information.
- Local output is the default. UNC and mapped-network-drive output require `-AllowNetworkOutput`.

See [SECURITY.md](SECURITY.md) for security guidance.

## License

AD ATLAS is available under the [MIT License](LICENSE).
