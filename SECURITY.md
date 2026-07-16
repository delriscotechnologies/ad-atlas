# Security Policy

## Supported Versions

Security fixes are applied to the latest version on the `main` branch.

## Reporting a Vulnerability

Use GitHub private vulnerability reporting when available. Do not publish credentials, private domain names, hostnames, OU structures, IP addresses, report files, or working exploit material in a public issue.

Include the affected version, reproduction steps using synthetic data whenever possible, the potential impact, and any suggested mitigations.

## Intended Use

This project is a read-only Active Directory inventory tool. Use it only in environments you own or are explicitly authorized to assess.

The generated CSV file contains internal computer names and OU structures. Store it outside public repositories, restrict filesystem access, and remove it according to your organization's retention policy.

## Security Boundaries

The script:

- Uses the current Windows identity.
- Uses `Get-ADComputer` as its only Active Directory query.
- Retains and exports only computer names and distinguished names.
- Does not modify Active Directory.
- Does not connect to endpoint hosts.
- Does not accept or store credentials.
- Never contacts a real domain from public CI; the real-domain integration test requires explicit opt-in.
