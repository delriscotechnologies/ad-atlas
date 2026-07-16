# Security policy

## supported version

Security fixes are applied to the latest version on the `main` branch.

## reporting a vulnerability

Use GitHub private vulnerability reporting when it is available. Do not publish credentials, private domain names, hostnames, OU structures, IP addresses, report files, or working exploit material in a public issue.

Include the affected version, reproduction steps using synthetic data where possible, impact, and any suggested mitigation.

## intended use

This project is a read-only Active Directory inventory tool. Use it only in environments you own or are explicitly authorized to assess.

The generated CSV file contains internal computer names and OU structure. Store it outside public repositories, limit filesystem access, and remove it according to the organization's retention policy.

## security boundaries

The script:

- uses the current Windows identity
- uses `Get-ADComputer` as its only Active Directory query
- retains and exports only computer names and Distinguished Names
- does not modify Active Directory
- does not connect to endpoint hosts
- does not accept or store credentials
- never contacts a real domain from public CI; the real-domain integration test requires explicit opt-in
