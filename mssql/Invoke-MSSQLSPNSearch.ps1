Function Invoke-MSSQLSPNSearch {

    <#
.SYNOPSIS
    Search for Microsoft SQL Servers by SPN (Service Principal Name) 
.DESCRIPTION
    It tries to find MSSQL services in Active Directory
.PARAMETER Method
    Raw Powershell (Powershell) with SETSPN.EXE (setspn)
.INPUTS
    None
.OUTPUTS
    Strings with MSSQL addresses
.NOTES
    Author: Pawel Maziarz <pawel.maziarz@immunity-systems.com>
.EXAMPLE
    Invoke-MSSQLSPNSearch -Method setspn
.EXAMPLE
    Invoke-MSSQLSPNSearch | Invoke-MSSQLBrute | Invoke-MSSQLExec -Command "whoami"
.LINK
https://blog.aptmasterclass.com/
#>

    [CmdletBinding()]
    Param(
        [Parameter()]
        [ValidateSet('Powershell','setspn')]
        [String]$Method = ("Powershell")
    )

    Begin {
        $Result = @()
    }

    Process {
        if ($Method -eq "setspn") {
            Write-Verbose "[*] Using setspn.exe"

            (setspn -Q MSSQLSvc/*) -match "MSSQL" | % { 
                $Result += $_.Trim().Split("/")[1] -Replace ':1433',''
            }
        }  elseif ($Method -eq  "Powershell") {
            Write-Verbose "[*] Using Powershell"

            $s = [ADSISearcher]([ADSI]"")
            $s.filter = "(servicePrincipalName=MSSQL*)"
            $s.FindAll() | % {
                $_.GetDirectoryEntry().servicePrincipalName -match "MSSQL" | % {
                    $Result += $_.Split("/")[1] -Replace ':1433',''
                }
            }
        }
    }

    End {
        $Result = $Result | select -uniq
        $Result
    }

}