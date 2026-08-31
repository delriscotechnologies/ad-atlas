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
- Imports the RSAT Active Directory module from the Windows PowerShell system module directory rather than searching user-controlled module paths.
- Uses `Get-ADRootDSE` and `Get-ADComputer` as its only Active Directory queries.
- Anchors that query to the default naming context returned by `Get-ADRootDSE` so the caller's current `AD:` location cannot narrow the inventory silently.
- Limits the requested AD result set to `MaxComputers + 1` objects.
- Requests only the additional `CanonicalName` property and uses it with the default `Name` property.
- Exports only the department label, computer name, and OU hierarchy derived from those values.
- Writes to a same-directory temporary file, publishes the completed CSV atomically, and refuses to overwrite an existing file.
- Does not modify Active Directory.
- Does not connect to endpoint hosts.
- Does not accept or store credentials.
- Rejects UNC and mapped-network-drive output unless `-AllowNetworkOutput` is provided explicitly.
- Treats `-AllComputers` as operator confirmation rather than an authorization control.

CSV fields are neutralized before export to reduce spreadsheet-formula injection risk. No CSV neutralization is universal across every spreadsheet and save/reopen workflow; validate the report workflow against the spreadsheet application used in your environment.
