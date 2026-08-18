# Security Policy

## Supported Versions

Security fixes are applied to the latest version on the `main` branch.

## Reporting a Vulnerability

Use GitHub private vulnerability reporting when available. If private vulnerability reporting is unavailable, open a public issue containing no sensitive details and request a private contact channel before sharing reproduction material.

Do not publish credentials, private domain names, hostnames, OU structures, IP addresses, report files, or working exploit material in a public issue.

Include the affected version, reproduction steps using synthetic data whenever possible, the potential impact, and any suggested mitigations.

## Intended Use

This project is a read-only Active Directory inventory tool. Use it only in environments you own or are explicitly authorized to assess.

The generated CSV file contains internal computer names and OU structures. Store it outside public repositories, restrict filesystem access, and remove it according to your organization's retention policy.

## Security Boundaries

The script:

- Uses the current Windows identity.
- Uses `Get-ADComputer` as its only Active Directory query.
- Limits the requested AD result set to `MaxComputers + 1` objects.
- Uses only `Name` and `DistinguishedName` from the returned AD objects.
- Exports only the department label, computer name, and OU hierarchy derived from those values.
- Writes directly to the requested CSV path and refuses to overwrite an existing file.
- Does not modify Active Directory.
- Does not connect to endpoint hosts.
- Does not accept or store credentials.
- Rejects direct UNC output paths unless `-AllowNetworkOutput` is provided explicitly.
- Treats `-AllComputers` as operator confirmation rather than an authorization control.
