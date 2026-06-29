#Requires -Modules Az.PrivateDns, Az.Accounts
<#
.SYNOPSIS
    Exports all Azure Private DNS A records from a subscription to a CSV file.

.DESCRIPTION
    Connects to an Azure subscription, retrieves all Private DNS zones and their A records,
    and exports them to a CSV file for use with Import-PrivateDNSRecords.ps1.

    Assumes an existing Az context (run Connect-AzAccount before invoking this script).

.PARAMETER SubscriptionId
    The ID of the Azure subscription containing the Private DNS zones.

.PARAMETER CsvPath
    Output path for the CSV file. Must not already exist unless -Force is specified.

.PARAMETER Force
    Overwrite the CSV file if it already exists.

.EXAMPLE
    .\Export-PrivateDNSRecords.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -CsvPath 'C:\temp\pdns.csv'

.EXAMPLE
    .\Export-PrivateDNSRecords.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -CsvPath 'C:\temp\pdns.csv' -Force
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $CsvPath,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Verify Az context
if (-not (Get-AzContext)) {
    throw 'No Azure context found. Run Connect-AzAccount before invoking this script.'
}

if ((Test-Path $CsvPath) -and -not $Force) {
    throw "Output file '$CsvPath' already exists. Use -Force to overwrite."
}

Write-Verbose "Setting subscription context to '$SubscriptionId'..."
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

Write-Verbose 'Retrieving Private DNS zones...'
$zones = Get-AzPrivateDnsZone

$records = foreach ($zone in $zones) {
    Write-Verbose "  Processing zone '$($zone.Name)'..."
    $recordSets = Get-AzPrivateDnsRecordSet -ZoneName $zone.Name -ResourceGroupName $zone.ResourceGroupName

    foreach ($rs in $recordSets) {
        if ($rs.RecordType -eq 'A') {
            foreach ($record in $rs.Records) {
                [PSCustomObject]@{
                    Zone  = $zone.Name
                    Name  = $rs.Name
                    Value = $record.Ipv4Address
                }
            }
        }
    }
}

$count = ($records | Measure-Object).Count
Write-Verbose "Exporting $count record(s) to '$CsvPath'..."
$records | Export-Csv -Path $CsvPath -NoTypeInformation -Force:$Force

Write-Host "Exported $count Private DNS A record(s) to '$CsvPath'."
