<h1 align="center">AD ATLAS</h1>

<p align="center">
  A read-only map of Active Directory computers and their OU structure.
</p>

---

AD ATLAS is a PowerShell script that inventories computer objects in the current Active Directory domain and maps them to a department candidate using OU rules.

> Use AD ATLAS only in Active Directory environments you own or are authorized to inventory.

## Install

You need PowerShell, the RSAT Active Directory module, domain connectivity, and permission to read computer objects.

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

The CSV contains three fields:

| Field | Description |
| --- | --- |
| Department | Selected department or [Unclassified] |
| ComputerName | Active Directory computer name |
| OrganizationalUnitPath | OU hierarchy used for the mapping |

Reports are saved under Documents\AD-ATLAS-Reports unless a different output path is provided.

## Demo

```powershell
.\Get-AD-ATLAS.ps1 -AllComputers
```

Example:

```text
Department:             Finance
ComputerName:           FIN-LAP-001
OrganizationalUnitPath: Laptops / Finance / Devices
```

## Scope and limits

- Read-only Active Directory inventory.
- Does not modify Active Directory or connect to endpoint computers.
- Uses the current Windows identity and does not request credentials.
- Department mapping is based on OU structure and should be reviewed for your environment.
- Real reports may contain internal computer names and OU information.

See [SECURITY.md](SECURITY.md) for security guidance.

## License

AD ATLAS is available under the [MIT License](LICENSE).
