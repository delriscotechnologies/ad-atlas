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
                }
            )

            Export-DepartmentInventoryCsv -Rows $rows -Path $resolvedPath

            @(Get-ChildItem -LiteralPath (Split-Path $resolvedPath -Parent) -File).Count | Should-Be 1
            $csv = @(Import-Csv -LiteralPath $resolvedPath)
            $csv.Count | Should-Be 2
            @($csv[0].PSObject.Properties.Name) | Should-BeCollection @(
                'Department',
                'ComputerName',
                'OrganizationalUnitPath'
            )
        }

        It 'keeps a useful schema when the domain has no computers' {
            $outputPath = Join-Path $TestDrive 'empty.csv'
            Export-DepartmentInventoryCsv -Rows @() -Path $outputPath

            Get-Content -LiteralPath $outputPath -TotalCount 1 |
                Should-Be '"Department","ComputerName","OrganizationalUnitPath"'
        }

        It 'rejects non-filesystem output providers' {
            { Resolve-InventoryOutputPath -RequestedPath 'Variable:\AD-ATLAS.csv' } |
                Should-Throw -ExceptionMessage '*FileSystem provider*'
        }

        It 'neutralizes spreadsheet formula prefixes' {
            foreach ($value in @('=1+1', '+1+1', '-1+1', '@SUM(A1:A2)', "`t=1+1", "`r=1+1", "`n=1+1")) {
                Protect-CsvCell -Value $value | Should-Be "'$value"
            }
        }

        It 'does not collect removed endpoint metadata' {
            $source = Get-Content -LiteralPath $scriptPath -Raw

            $source.Contains('DNSHostName') | Should-BeFalse
            $source.Contains('OperatingSystem') | Should-BeFalse
            $source.Contains('LastLogonDate') | Should-BeFalse
            $source.Contains('DisabledComputerAccount') | Should-BeFalse
            $source.Contains('SignalSummary') | Should-BeFalse
        }
    }

    Context 'safety limit' {
        BeforeAll {
            function Get-ADComputer {
                [CmdletBinding()]
                param([string]$Filter)

                1..3 | ForEach-Object {
                    [pscustomobject]@{
                        Name = "HOST-$_"
                        DistinguishedName = "CN=HOST-$_,OU=Finance,DC=company,DC=com"
                    }
                }
            }
        }

        It 'stops before writing output when MaxComputers is exceeded' {
            { Get-DomainComputerInventory -MaxComputers 2 } | Should-Throw
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
