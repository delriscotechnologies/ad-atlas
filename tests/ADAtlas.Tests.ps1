BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\Get-AD-ATLAS.ps1'
    . $scriptPath
}

Describe 'AD ATLAS' {
    Context 'OU classification' {
        It 'selects the closest relevant OU by default' {
            $result = Resolve-DepartmentOU `
                -DistinguishedName 'CN=FIN-LAP-001,OU=Laptops,OU=Finance,OU=Devices,DC=company,DC=com' `
                -IgnoreOUs @('Laptops', 'Devices') `
                -Strategy ClosestRelevant

            $result.DepartmentOU | Should-Be 'Finance'
            $result.OUPath | Should-Be 'Laptops / Finance / Devices'
        }

        It 'can select the highest relevant OU' {
            $result = Resolve-DepartmentOU `
                -DistinguishedName 'CN=HOST-01,OU=Tier 2,OU=Security Operations,OU=North America,OU=Devices,DC=company,DC=com' `
                -IgnoreOUs @('Tier 2', 'Devices') `
                -Strategy TopRelevant

            $result.DepartmentOU | Should-Be 'North America'
        }

        It 'preserves escaped commas and hexadecimal DN escapes' {
            $escaped = Resolve-DepartmentOU `
                -DistinguishedName 'CN=HOST-01,OU=Workstations,OU=Research\, Development,OU=Devices,DC=company,DC=com' `
                -IgnoreOUs @('Workstations', 'Devices') `
                -Strategy ClosestRelevant
            $hex = Resolve-DepartmentOU `
                -DistinguishedName 'CN=HOST-02,OU=Laptops,OU=Research\2C Development,OU=Devices,DC=company,DC=com' `
                -IgnoreOUs @('Laptops', 'Devices') `
                -Strategy ClosestRelevant

            $escaped.DepartmentOU | Should-Be 'Research, Development'
            $hex.DepartmentOU | Should-Be 'Research, Development'
        }

        It 'preserves escaped leading and trailing spaces in OU values' {
            $leading = Resolve-DepartmentOU `
                -DistinguishedName 'CN=HOST-01,OU=\ Finance,OU=Devices,DC=company,DC=com' `
                -IgnoreOUs @('Devices') `
                -Strategy ClosestRelevant
            $trailing = Resolve-DepartmentOU `
                -DistinguishedName 'CN=HOST-02,OU=Finance\ ,OU=Devices,DC=company,DC=com' `
                -IgnoreOUs @('Devices') `
                -Strategy ClosestRelevant
            $hexSpaces = Resolve-DepartmentOU `
                -DistinguishedName 'CN=HOST-03,OU=\20Finance\20,OU=Devices,DC=company,DC=com' `
                -IgnoreOUs @('Devices') `
                -Strategy ClosestRelevant

            $leading.DepartmentOU | Should-Be ' Finance'
            $leading.OUPath | Should-Be ' Finance / Devices'
            $trailing.DepartmentOU | Should-Be 'Finance '
            $trailing.OUPath | Should-Be 'Finance  / Devices'
            $hexSpaces.DepartmentOU | Should-Be ' Finance '
        }

        It 'marks computers outside an OU as unclassified' {
            $row = ConvertTo-DepartmentInventoryRow `
                -Computer ([pscustomobject]@{
                    Name = 'HOST-01'
                    DistinguishedName = 'CN=HOST-01,CN=Computers,DC=company,DC=com'
                }) `
                -Strategy ClosestRelevant `
                -IgnoreOUs @('Computers')

            $row.Department | Should-Be '[Unclassified]'
            $row.OrganizationalUnitPath | Should-Be ''
        }
    }

    Context 'minimal output' {
        It 'creates one CSV with exactly three columns' {
            $outputPath = Join-Path $TestDrive 'reports\inventory.csv'
            $resolvedPath = Resolve-InventoryOutputPath -RequestedPath $outputPath
            $rows = @(
                [pscustomobject]@{
                    Department = 'Finance'
                    ComputerName = 'FIN-LAP-001'
                    OrganizationalUnitPath = 'Laptops / Finance / Devices'
                },
                [pscustomobject]@{
                    Department = 'Human Resources'
                    ComputerName = 'HR-WS-002'
                    OrganizationalUnitPath = 'Workstations / Human Resources / Devices'
                },
                [pscustomobject]@{
                    Department = '[Unclassified]'
                    ComputerName = 'KIOSK-004'
                    OrganizationalUnitPath = ''
                }
            )

            Export-DepartmentInventoryCsv -Rows $rows -Path $resolvedPath

            @(Get-ChildItem -LiteralPath (Split-Path $resolvedPath -Parent) -File).Count | Should-Be 1
            @(Get-ChildItem -LiteralPath (Split-Path $resolvedPath -Parent) -Filter '.AD-ATLAS-*.tmp' -File).Count |
                Should-Be 0
            $csv = @(Import-Csv -LiteralPath $resolvedPath)
            $csv.Count | Should-Be 3
            @($csv[0].PSObject.Properties.Name) | Should-BeCollection @(
                'Department',
                'ComputerName',
                'OrganizationalUnitPath'
            )
            $csv[2].Department | Should-Be '[Unclassified]'
            $csv[2].ComputerName | Should-Be 'KIOSK-004'
        }

        It 'keeps a useful schema when the domain has no computers' {
            $outputPath = Join-Path $TestDrive 'empty.csv'
            Export-DepartmentInventoryCsv -Rows @() -Path $outputPath

            Get-Content -LiteralPath $outputPath -TotalCount 1 |
                Should-Be '"Department","ComputerName","OrganizationalUnitPath"'
        }

        It 'does not overwrite a file created after path validation' {
            $outputPath = Join-Path $TestDrive 'race\inventory.csv'
            $resolvedPath = Resolve-InventoryOutputPath -RequestedPath $outputPath
            Set-Content -LiteralPath $resolvedPath -Value 'SENTINEL'

            $rows = @(
                [pscustomobject]@{
                    Department = 'Finance'
                    ComputerName = 'FIN-LAP-001'
                    OrganizationalUnitPath = 'Finance / Devices'
                }
            )

            { Export-DepartmentInventoryCsv -Rows $rows -Path $resolvedPath } |
                Should-Throw
            (Get-Content -LiteralPath $resolvedPath -Raw).Trim() | Should-Be 'SENTINEL'
            @(Get-ChildItem -LiteralPath (Split-Path $resolvedPath -Parent) -File).Count |
                Should-Be 1
        }

        It 'throws instead of reporting success when the CSV cannot be written' {
            $blockedParent = Join-Path $TestDrive 'not-a-directory'
            Set-Content -LiteralPath $blockedParent -Value 'BLOCKER'
            $outputPath = Join-Path $blockedParent 'inventory.csv'

            { Export-DepartmentInventoryCsv -Rows @() -Path $outputPath } |
                Should-Throw
            Test-Path -LiteralPath $outputPath | Should-BeFalse
        }

        It 'rejects non-filesystem output providers' {
            { Resolve-InventoryOutputPath -RequestedPath 'Variable:\AD-ATLAS.csv' } |
                Should-Throw -ExceptionMessage '*FileSystem provider*'
        }

        It 'rejects direct UNC output unless explicitly allowed' {
            { Resolve-InventoryOutputPath -RequestedPath '\\server\share\AD-ATLAS.csv' } |
                Should-Throw -ExceptionMessage '*-AllowNetworkOutput*'
        }

        It 'mitigates common spreadsheet formula prefixes' {
            foreach ($value in @(
                '=1+1', '+1+1', '-1+1', '@SUM(A1:A2)',
                "`t=1+1", "`r=1+1", "`n=1+1", '  =1+1',
                (([char]0xFF1D).ToString() + '1+1'),
                (([char]0xFF0B).ToString() + '1+1'),
                (([char]0xFF0D).ToString() + '1+1'),
                (([char]0xFF20).ToString() + 'SUM(A1:A2)')
            )) {
                Protect-CsvCell -Value $value | Should-Be "'$value"
            }

            Protect-CsvCell -Value 'Finance' | Should-Be 'Finance'
            Protect-CsvCell -Value '  Finance' | Should-Be '  Finance'
        }

        It 'does not count unclassified rows as departments' {
            $rows = @(
                [pscustomobject]@{ Department = 'Finance' },
                [pscustomobject]@{ Department = 'Finance' },
                [pscustomobject]@{ Department = 'Human Resources' },
                [pscustomobject]@{ Department = '[Unclassified]' }
            )

            Get-ClassifiedDepartmentCount -Rows $rows | Should-Be 2
        }
    }

    Context 'safety limit and AD data minimization' {
        BeforeAll {
            $script:lastADFilter = $null
            $script:lastADResultSetSize = $null

            function Get-ADComputer {
                [CmdletBinding()]
                param(
                    [string]$Filter,
                    [int]$ResultSetSize
                )

                $script:lastADFilter = $Filter
                $script:lastADResultSetSize = $ResultSetSize

                1..3 | ForEach-Object {
                    [pscustomobject]@{
                        Name = "HOST-$_"
                        DistinguishedName = "CN=HOST-$_,OU=Finance,DC=company,DC=com"
                        DNSHostName = "host-$_.company.com"
                        OperatingSystem = 'Windows'
                    }
                }
            }
        }

        It 'requests one extra result and retains only required AD properties' {
            $computers = @(Get-DomainComputerInventory -MaxComputers 3)

            $script:lastADFilter | Should-Be '*'
            $script:lastADResultSetSize | Should-Be 4
            $computers.Count | Should-Be 3
            @($computers[0].PSObject.Properties.Name) | Should-BeCollection @(
                'Name',
                'DistinguishedName'
            )
        }

        It 'stops before writing output when MaxComputers is exceeded' {
            { Get-DomainComputerInventory -MaxComputers 2 } | Should-Throw
            $script:lastADResultSetSize | Should-Be 3
        }

        It 'explains how to increase the limit' {
            try {
                $null = Get-DomainComputerInventory -MaxComputers 2
                throw 'Expected the safety limit to stop the query.'
            }
            catch {
                $_.Exception.Message | Should-MatchString '-MaxComputers 50000'
            }
        }
    }
}
