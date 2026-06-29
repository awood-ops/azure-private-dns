#Requires -Modules DnsServer
<#
.SYNOPSIS
    Imports Private DNS records from a CSV into a Windows DNS server.

.DESCRIPTION
    Reads the CSV produced by Export-PrivateDNSRecords.ps1 and creates the corresponding
    Forward Lookup Zones and A records on a Windows DNS server. Idempotent — skips zones
    and records that already exist.

    Requires the DnsServer PowerShell module (RSAT: DNS Server Tools).

.PARAMETER DnsServerName
    Name or IP address of the Windows DNS server to import records into.

.PARAMETER CsvPath
    Path to the CSV file produced by Export-PrivateDNSRecords.ps1.

.EXAMPLE
    .\Import-PrivateDNSRecords.ps1 -DnsServerName 'dns01' -CsvPath 'C:\temp\pdns.csv'
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string] $DnsServerName,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string] $CsvPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Verbose "Importing records from '$CsvPath'..."
$records = Import-Csv -Path $CsvPath

$created = 0
$skipped = 0
$errors  = 0

foreach ($record in $records) {
    $zone = $record.Zone
    $name = $record.Name
    $ip   = $record.Value

    try {
        # Create the Forward Lookup Zone if it doesn't exist
        $existingZone = Get-DnsServerZone -ComputerName $DnsServerName -Name $zone -ErrorAction SilentlyContinue
        if (-not $existingZone) {
            if ($PSCmdlet.ShouldProcess($DnsServerName, "Create zone '$zone'")) {
                Add-DnsServerPrimaryZone -ComputerName $DnsServerName -Name $zone -ReplicationScope 'Forest'
                Write-Verbose "  Created zone '$zone'."
            }
        }

        # Check for duplicate IP or name before creating
        $existingRecords = Get-DnsServerResourceRecord -ComputerName $DnsServerName -ZoneName $zone -RRType A -ErrorAction SilentlyContinue
        $duplicate = $existingRecords | Where-Object {
            $_.HostName -eq $name -or $_.RecordData.IPv4Address.IPAddressToString -eq $ip
        }

        if ($duplicate) {
            Write-Verbose "  Skipping '$name' in '$zone' — record already exists."
            $skipped++
        }
        else {
            if ($PSCmdlet.ShouldProcess($DnsServerName, "Add A record '$name' ($ip) in zone '$zone'")) {
                Add-DnsServerResourceRecordA -ComputerName $DnsServerName -ZoneName $zone -Name $name -IPv4Address $ip
                Write-Verbose "  Created A record '$name' ($ip) in zone '$zone'."
                $created++
            }
        }
    }
    catch {
        Write-Warning "  Failed to process '$name' in '$zone': $_"
        $errors++
    }
}

Write-Host "Import complete — Created: $created  Skipped: $skipped  Errors: $errors"
