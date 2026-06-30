<#
.SYNOPSIS
    Tests TCP connectivity to each Private DNS endpoint listed in a CSV.

.DESCRIPTION
    Reads the CSV produced by Export-PrivateDNSRecords.ps1 and tests TCP connectivity
    to each endpoint's IP address on port 443 (HTTPS). Useful for verifying that
    network routing and firewall rules allow traffic to private endpoints.

.PARAMETER CsvPath
    Path to the CSV file produced by Export-PrivateDNSRecords.ps1.

.PARAMETER Port
    TCP port to test connectivity on. Defaults to 443.

.PARAMETER TimeoutMs
    Connection timeout in milliseconds. Defaults to 2000.

.EXAMPLE
    .\Test-PrivateDNSConnectivity.ps1 -CsvPath 'C:\temp\pdns.csv'

.EXAMPLE
    .\Test-PrivateDNSConnectivity.ps1 -CsvPath 'C:\temp\pdns.csv' -Port 1433 -TimeoutMs 5000
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string] $CsvPath,

    [int] $Port = 443,

    [int] $TimeoutMs = 2000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Verbose "Importing records from '$CsvPath'..."
$records = Import-Csv -Path $CsvPath

$results = foreach ($record in $records) {
    $ip   = $record.Value
    $zone = $record.Zone
    $name = $record.Name
    $fqdn = '{0}.{1}' -f $name, ($zone -replace '^privatelink\.', '')

    $connected = $false
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $task = $tcp.ConnectAsync($ip, $Port)
        $connected = $task.Wait($TimeoutMs) -and $tcp.Connected
        $tcp.Close()
    }
    catch {
        $connected = $false
    }

    [PSCustomObject]@{
        Status = if ($connected) { 'REACHABLE' } else { 'UNREACHABLE' }
        FQDN   = $fqdn
        IP     = $ip
        Port   = $Port
    }
}

$results | Format-Table -AutoSize

$ok   = ($results | Where-Object Status -eq 'REACHABLE').Count
$fail = ($results | Where-Object Status -eq 'UNREACHABLE').Count
Write-Host "`nResults — Reachable: $ok  Unreachable: $fail  Total: $($results.Count)"
