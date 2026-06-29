#Requires -Modules Az.PrivateDns, Az.Network, Az.Accounts
<#
.SYNOPSIS
    Creates /32 routes in an Azure Route Table for each Private Endpoint in a subscription.

.DESCRIPTION
    Enumerates all Private DNS A records across the subscription and ensures a corresponding
    /32 host route exists in the target Route Table, directing traffic to a next-hop IP
    (typically a firewall or NVA).

    Designed to run on a schedule (e.g. daily) to keep the Route Table in sync as new
    Private Endpoints are provisioned. Idempotent — skips routes that already exist.

    Assumes an existing Az context (run Connect-AzAccount before invoking this script).

.PARAMETER SubscriptionId
    The ID of the Azure subscription to enumerate Private DNS zones from.

.PARAMETER RouteTableResourceGroupName
    Resource group containing the target Route Table.

.PARAMETER RouteTableName
    Name of the Route Table to update.

.PARAMETER NextHopIpAddress
    IP address of the next hop (firewall or NVA) for the /32 routes.

.EXAMPLE
    .\Create-PrivateEndpointRoutes.ps1 `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -RouteTableResourceGroupName 'rg-networking' `
        -RouteTableName 'rt-hub' `
        -NextHopIpAddress '10.0.0.4'
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $RouteTableResourceGroupName,

    [Parameter(Mandatory)]
    [string] $RouteTableName,

    [Parameter(Mandatory)]
    [string] $NextHopIpAddress
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Verify Az context
if (-not (Get-AzContext)) {
    throw 'No Azure context found. Run Connect-AzAccount before invoking this script.'
}

Write-Verbose "Setting subscription context to '$SubscriptionId'..."
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

Write-Verbose 'Retrieving Private DNS zones...'
$zones = Get-AzPrivateDnsZone

# Build list of endpoint IPs and generated route names
$endpoints = foreach ($zone in $zones) {
    Write-Verbose "  Processing zone '$($zone.Name)'..."
    $recordSets = Get-AzPrivateDnsRecordSet -ZoneName $zone.Name -ResourceGroupName $zone.ResourceGroupName

    foreach ($rs in $recordSets) {
        if ($rs.RecordType -eq 'A') {
            foreach ($record in $rs.Records) {
                $routeName = 'pe-{0}-{1}' -f ($rs.Name -replace '\.', ''), $zone.Name
                if ($routeName.Length -gt 80) { $routeName = $routeName.Substring(0, 80) }

                [PSCustomObject]@{
                    RouteName = $routeName
                    IpAddress = $record.Ipv4Address
                    Zone      = $zone.Name
                    Name      = $rs.Name
                }
            }
        }
    }
}

Write-Verbose "Getting Route Table '$RouteTableName'..."
$routeTable = Get-AzRouteTable -Name $RouteTableName -ResourceGroupName $RouteTableResourceGroupName
$existingRouteNames = $routeTable.Routes | Select-Object -ExpandProperty Name

$created = 0
$skipped = 0

foreach ($ep in $endpoints) {
    if ($existingRouteNames -contains $ep.RouteName) {
        Write-Verbose "  Skipping '$($ep.RouteName)' — route already exists."
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($RouteTableName, "Add route '$($ep.RouteName)' → $($ep.IpAddress)/32 via $NextHopIpAddress")) {
        Add-AzRouteConfig `
            -Name            $ep.RouteName `
            -AddressPrefix   "$($ep.IpAddress)/32" `
            -NextHopType     VirtualAppliance `
            -NextHopIpAddress $NextHopIpAddress `
            -RouteTable      $routeTable | Out-Null
        $created++
        Write-Verbose "  Added route '$($ep.RouteName)'."
    }
}

if ($created -gt 0) {
    Write-Verbose 'Committing Route Table changes...'
    Set-AzRouteTable -RouteTable $routeTable | Out-Null
}

Write-Host "Route update complete — Created: $created  Skipped: $skipped  Total endpoints: $($endpoints.Count)"
