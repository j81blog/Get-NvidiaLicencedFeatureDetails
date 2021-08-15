<#
.SYNOPSIS
    Get the Nvidia License Feature Details
.DESCRIPTION
    Get the Nvidia License Feature Details
.EXAMPLE
    Get-NvidiaLicencedFeatureDetails.ps1
    View all license details 
.EXAMPLE
    Get-NvidiaLicencedFeatureDetails.ps1 | Where-Object {$_.FeatureName -eq "GRID-Virtual-PC" }
    View all GRID-Virtual-PC licenses
.NOTES
    File Name : Get-NvidiaLicencedFeatureDetails.ps1
    Version   : v1.1
    Author    : John Billekens
    Requires  : PowerShell v5 and up
                Nvidia License server
.PARAMETER URI
    Specify the License server URI
    Default Value: http://localhost:8080/
.PARAMETER MaxIDs
    Specify the Max number of IDs being scanned, if you miss licenses, try to enter an higher ID (only for large companies or with multiple licenses)
    Default Value: 20
.LINK
    https://blog.j81.nl
#>
[CmdletBinding(DefaultParameterSetName = "URI")]
param (
    [Parameter(ParameterSetName = "URI", Position = 0)]
    [ValidatePattern('^(http[s]?)(:\/\/)([^\s,]+)')]
    [System.URI]$URI = "http://localhost:8080/",

    [Parameter(ParameterSetName = "Other")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('http','https')]
    [String]$Protocol = "http",

    [Parameter(ParameterSetName = "Other")]
    [ValidateNotNullOrEmpty()]
    [string]$ServerFQDN = "localhost",

    [Parameter(ParameterSetName = "Other")]
    [ValidateNotNullOrEmpty()]
    [string]$ServerPort = "8080",

    [Parameter(ParameterSetName = "URI")]
    [Parameter(ParameterSetName = "Other")]
    [ValidateNotNullOrEmpty()]
    [Int]$MaxIDs = 20,

    [Parameter(ParameterSetName = "URI")]
    [Parameter(ParameterSetName = "Other")]
    [Switch]$Summary
)
#requires -version 5.0

if (-Not ($PSCmdlet.ParameterSetName -eq "URI")) {
    Write-Warning "-Protocol, -ServerFQDN and -ServerPort are legacy parameters"
    $URI = [System.URI]"{0}://{1}:{2}/" -f $Protocol, $ServerFQDN, $ServerPort
}
$LicencedFeatureDetails = [PSCustomObject]@()
$ErrorLoopCount = 0
$DataFound = $false
for ($i = 1; $i -le $MaxIDs; $i++) {
    try {
        $URL = "{0}licserver/manageFeatureUsage_featureDetails.action?feature.featureId={1}&page=1" -f $URI.AbsoluteUri, $i
        $Response = Invoke-WebRequest -UseBasicParsing -Uri $URL
        $FeatureName = try { $Response.RawContent | Where-Object { $_ -match '(?:<span class="heading1"><a title=")(?<FeatureName>[a-zA-Z-]+?)"' } | ForEach { $matches['FeatureName'] } } catch { $null }
        if (-not [String]::IsNullOrEmpty($FeatureName)) {
            $Version  = try { $Response.RawContent | Where-Object { $_ -match '(?:.+?(?=Version).+?(?=;));(?<Version>.+?(?= <))' } | ForEach { $matches['Version'] } } catch { $null }
            $TotalCount = try { $Response.RawContent | Where-Object { $_ -match '(?:.+?(?=Total count).+?(?=;));(?<TotalCount>.+?(?= <))' } | ForEach { $matches['TotalCount'] } } catch { $null }
            $Available = try { $Response.RawContent | Where-Object { $_ -match '(?:.+?(?=Available).+?(?=;));(?<Available>.+?(?= <))' } | ForEach { $matches['Available'] } } catch { $null }
            $CurrentUsage = try { $Response.RawContent | Where-Object { $_ -match '(?:.+?(?=Current Usage).+?(?=;));(?<CurrentUsage>.+?(?= <))' } | ForEach { $matches['CurrentUsage'] } } catch { $null }
            $ReservedCount = try { $Response.RawContent | Where-Object { $_ -match '(?:.+?(?=Reserved Count).+?(?=;));(?<ReservedCount>.+?(?= <))' } | ForEach { $matches['ReservedCount'] } } catch { $null }
            $VendorString = try { $Response.RawContent | Where-Object { $_ -match '(?:.+?(?=Vendor String).+?(?=;));(?<VendorString>.+?(?= <))' } | ForEach { $matches['VendorString'] } } catch { $null }
            $FeatureExpiry = try { $Response.RawContent | Where-Object { $_ -match '(?:.+?(?=Feature Expiry).+?(?=;));(?<FeatureExpiry>.+?(?=\s))' } | ForEach { $matches['FeatureExpiry'] } } catch { $null }

            try {
                $FeatureExpiry = [DateTime]::Parse($FeatureExpiry)
                $FeaturesDaysLeft = (New-TimeSpan -Start $(Get-Date) -End $FeatureExpiry).Days
                if ($FeaturesDaysLeft -lt 1) {
                    Write-Warning "License `"$FeatureName`" (ID: $i) is expired!"
                } elseif ($FeaturesDaysLeft -lt 90) {
                    Write-Warning "The `"$FeatureName`" (ID: $i) license will expire in $FeaturesDaysLeft days!"
                }
            } catch {
                $FeatureExpiry = $FeatureExpiry
                $FeaturesDaysLeft = -1
            }
            
            $CurrentUsageClients = [PSCustomObject]@{
                ClientID         = [string]""
                ClientIDType     = [string]""
                ClientType       = [string]""
                TotalCountServed = [Int32]0
                Expiry           = [Nullable[DateTime]]$null 
            }

            $Pattern = '(?:.+?(?=TRTableBorderBottom)(?s:.)+?(?=<a title=).+?(?=>))>(?<ClientID>.+?(?=<))(?:(?s:.)+?(?=<a title=).+?(?=>))>(?<ClientIDType>.+?(?=<))(?:(?s:.)+?(?=<a title=).+?(?=>))>(?<ClientType>.+?(?=<))(?:(?s:.)+?(?=[0-9]))(?<TotalCountServed>[0-9])(?:(?s:.)+?(?=[0-9]))(?<Expiry>[a-zA-Z0-9-:.]*)'
            $RxMatches = Select-String -InputObject $Response.RawContent -Pattern $pattern -AllMatches
            
            try {
                $CurrentUsageClients = $RxMatches.Matches | ForEach-Object { [PSCustomObject]@{
                    ClientID         = $(try { $_.Groups["ClientID"].Value } catch { $null })
                    ClientIDType     = $(try { $_.Groups["ClientIDType"].Value } catch { $null })
                    ClientType       = $(try { $_.Groups["ClientType"].Value } catch { $null })
                    TotalCountServed = $(try { [Int32]::Parse($($_.Groups["TotalCountServed"].Value)) } catch { $($_.Groups["TotalCountServed"].Value) })
                    Expiry           = $(try { [DateTime]::Parse($($_.Groups["Expiry"].Value)) } catch { $($_.Groups["Expiry"].Value) })
                                }
                }
            } catch { }
            $LicencedFeatureDetails += [PSCustomObject]@{
                ID                  = $i
                FeatureName         = $FeatureName
                Version             = $Version
                TotalCount          = $(try { [int]::Parse($TotalCount) } catch { $TotalCount } )
                Available           = $(try { [int]::Parse($Available) } catch { $Available } )
                CurrentUsage        = $(try { [int]::Parse($CurrentUsage) } catch { $CurrentUsage } )
                ReservedCount       = $(try { [int]::Parse($ReservedCount) } catch { $ReservedCount } )
                VendorString        = $VendorString
                FeatureExpiry       = $FeatureExpiry
                FeatureDaysLeft     = $FeaturesDaysLeft
                Uri                 = $URL
                CurrentUsageClients = $CurrentUsageClients
            }
        } elseif ($Data -like "*Error:*") {
            if ($DataFound) {
                $ErrorLoopCount++
            }
            if ($ErrorLoopCount -ge 20) {
                break
            }
        } 
    } catch {
        $ErrorLoopCount++
        Write-Verbose "Error Message: $_.Exception.Message"
    }
}
if ($Summary) {
    $LicencedFeatureDetails | Format-Table -Property ID,FeatureName,FeatureExpiry,TotalCount,CurrentUsage -AutoSize
} else {
    return $LicencedFeatureDetails
}
