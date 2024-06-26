#usage
#.\Test-PrivateDNSConnectivity.ps1 -csvPath "c:\temp\pdns.csv"

param
(
    [Parameter(Mandatory = $true)]
    [string]$csvPath
)

# Import the CSV
Write-output "Importing CSV"
$csv = Import-Csv -Path $csvPath

# Check the DNS Records from CSV and put them into a table
Write-Output "Testing Endpoint Connectivity"

foreach ($record in $csv)
{
    $recordName = $record.Name
    $recordZone = $record.Zone

    # Remove the privatelink. prefix from the zone
    if ($recordZone -eq "privatelink.vaultcore.azure.net") {
        $recordZone = "vault.azure.net"
    } elseif ($recordZone -ne "privatelink.adf.azure.com" -and $recordZone -ne "privatelink.purviewstudio.azure.com" -and $recordName -notlike "*ab-pod01*") {
        $recordZone = $recordZone.Replace("privatelink.", "")
    }

    if ($recordZone -eq "privatelink.database.windows.net") {
        Test-NetConnection -ComputerName "$recordName.$recordZone" -Port 1433
    } else {
        Test-NetConnection -ComputerName "$recordName.$recordZone" -Port 443
    }
}

