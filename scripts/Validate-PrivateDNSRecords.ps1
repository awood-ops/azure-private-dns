<#
.SYNOPSIS
    Validates that DNS records in the CSV resolve to the expected IP addresses.

.DESCRIPTION
    Reads the CSV produced by Export-PrivateDNSRecords.ps1 and checks that each record
    resolves to its expected IP via public DNS (which returns CNAMEs for privatelink zones)
    or via the local DNS resolver.

    For privatelink zones, the public DNS name is constructed by stripping the 'privatelink.'
    prefix from the zone name.

.PARAMETER CsvPath
    Path to the CSV file produced by Export-PrivateDNSRecords.ps1.

.PARAMETER DnsServer
    Optional DNS server to query. Defaults to the system resolver.

.EXAMPLE
    .\Validate-PrivateDNSRecords.ps1 -CsvPath 'C:\temp\pdns.csv'

.EXAMPLE
    .\Validate-PrivateDNSRecords.ps1 -CsvPath 'C:\temp\pdns.csv' -DnsServer '10.0.0.4' -Verbose
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string] $CsvPath,

    [string] $DnsServer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Verbose "Importing records from '$CsvPath'..."
$records = Import-Csv -Path $CsvPath

$results = foreach ($record in $records) {
    $zone  = $record.Zone
    $name  = $record.Name
    $ip    = $record.Value

    # Strip 'privatelink.' prefix to get the public FQDN
    $publicZone = $zone -replace '^privatelink\.', ''
    $fqdn = '{0}.{1}' -f $name, $publicZone

    try {
        $resolveParams = @{ Name = $fqdn; ErrorAction = 'Stop' }
        if ($DnsServer) { $resolveParams['Server'] = $DnsServer }

        $resolved = Resolve-DnsName @resolveParams
        $resolvedIps = $resolved | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress

        if ($resolvedIps -contains $ip) {
            $status = 'PASS'
        }
        elseif ($resolvedIps) {
            $status = 'MISMATCH'
        }
        else {
            $status = 'NO_A_RECORD'
        }
    }
    catch {
        $resolvedIps = @()
        $status = 'FAIL'
    }

    [PSCustomObject]@{
        Status      = $status
        FQDN        = $fqdn
        ExpectedIP  = $ip
        ResolvedIPs = $resolvedIps -join ', '
    }
}

$results | Format-Table -AutoSize

$pass    = ($results | Where-Object Status -eq 'PASS').Count
$fail    = ($results | Where-Object Status -in 'FAIL','NO_A_RECORD','MISMATCH').Count
Write-Host "`nResults — Pass: $pass  Fail: $fail  Total: $($results.Count)"
