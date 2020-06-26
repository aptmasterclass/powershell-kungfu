# aptm.in
function Test-Credentials {
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [String]$Username,
        [Parameter(Mandatory=$true, Position=1)]
        [String]$Password,
        [Parameter()]
        [ValidateSet('Domain', 'Machine')]
        [String]$Type = ('Machine')
    )

    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $o = New-Object System.DirectoryServices.AccountManagement.PrincipalContext($Type)
        $result = $o.ValidateCredentials($Username, $Password)
    } catch [Exception] {
        Write-Error "Whoops"
        Write-Host $_.Exception.Message
        return
    }

    return New-Object PSObject -Property @{Username=$Username; Password=$Password; Type=$Type; Valid=$result}
}
