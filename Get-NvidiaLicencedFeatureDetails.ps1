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
	Version   : v1.0
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
	[Parameter(ParameterSetName = "URI", Position = 0, Mandatory = $false)]
	[ValidatePattern('^(http[s]?)(:\/\/)([^\s,]+)')]
	[System.URI]$URI = "http://localhost:8080/",

	[Parameter(ParameterSetName = "Other", Mandatory = $false)]
	[ValidateNotNullOrEmpty()]
	[String]$Protocol = "http",

	[Parameter(ParameterSetName = "Other", Mandatory = $false)]
	[ValidateNotNullOrEmpty()]
	[string]$ServerFQDN = "localhost",

	[Parameter(ParameterSetName = "Other", Mandatory = $false)]
	[ValidateNotNullOrEmpty()]
	[string]$ServerPort = "8080",

	[Parameter(Mandatory = $false)]
	[ValidateNotNullOrEmpty()]
    [Int]$MaxIDs = 20
)
#requires -version 5.0

if (-Not ($PSCmdlet.ParameterSetName -eq "URI")) {
	Write-Warning "-Protocol, -ServerFQDN and -ServerPort are legacy parameters"
    $URI = [System.URI]"{0}://{1}:{2}/" -f $Protocol, $ServerFQDN, $ServerPort
}
$LicencedFeatureDetails = @()
$ErrorLoopCount = 0
$DataFound = $false
For ($i = 1; $i -le $MaxIDs; $i++) {
	try {
		$URL = "{0}licserver/manageFeatureUsage_featureDetails.action?feature.featureId={1}&page=1" -f $URI.AbsoluteUri, $i
		$Response = Invoke-WebRequest -UseBasicParsing -Uri $URL
		$FeatureName = try { ($Response.RawContent | Select-String -Pattern '(.+?(?=<a title=))(.+?(?==))=(.+?(?=>))').Matches.Groups[3].Value.Trim('"').Trim(' ') } catch { $null }
		if (-not [String]::IsNullOrEmpty($FeatureName)) {
			$Version = try { ($Response.RawContent | Select-String -Pattern '(.+?(?=Version))(.+?(?=;));(.+?(?=<))').Matches.Groups[3].Value.Trim(' ') } catch { $null }
			$TotalCount = try { ($Response.RawContent | Select-String -Pattern '(.+?(?=Total count))(.+?(?=;));(.+?(?=<))').Matches.Groups[3].Value.Trim(' ') } catch { $null }
			$Available = try { ($Response.RawContent | Select-String -Pattern '(.+?(?=Available))(.+?(?=;));(.+?(?=<))').Matches.Groups[3].Value.Trim(' ') } catch { $null }
			$CurrentUsage = try { ($Response.RawContent | Select-String -Pattern '(.+?(?=Current Usage))(.+?(?=;));(.+?(?=<))').Matches.Groups[3].Value.Trim(' ') } catch { $null }
			$ReservedCount = try { ($Response.RawContent | Select-String -Pattern '(.+?(?=Reserved Count))(.+?(?=;));(.+?(?=<))').Matches.Groups[3].Value.Trim(' ') } catch { $null }
			$VendorString = try { ($Response.RawContent | Select-String -Pattern '(.+?(?=Vendor String))(.+?(?=;));(.+?(?=<))').Matches.Groups[3].Value.Trim(' ') } catch { $null }
			$FeatureExpiry = try { ($Response.RawContent | Select-String -Pattern '(.+?(?=Feature Expiry))(.+?(?=;));(.+?(?= ))').Matches.Groups[3].Value.Trim(' ') } catch { $null }
			try {
				$FeatureExpiry = [DateTime]::Parse($FeatureExpiry)
				$FeaturesDaysLeft = (New-TimeSpan –Start $(get-date) –End $FeatureExpiry).Days
				if ($FeaturesDaysLeft -lt 1) {
					Write-Warning "License `"$FeatureName`" (ID: $i) is expired!"
				} elseif ($FeaturesDaysLeft -lt 90) {
					Write-Warning "The `"$FeatureName`" (ID: $i) license will expire in $FeaturesDaysLeft days!"
				}
			} catch {
				$FeaturesDaysLeft = -1
			}
			
			$CurrentUsageClients = [PSCustomObject]@{
				ClientID         = [string]""
				ClientIDType     = [string]""
				ClientType       = [string]""
				TotalCountServed = [Int32]0
				Expiry           = [Nullable[DateTime]]$null 
			}
			$Data = $Response.RawContent | Select-String -Pattern '(.+?(?=TRTableBorderBottom))((?s:.)+?(?=<a title=))(.+?(?=>))>(.+?(?=<))((?s:.)+?(?=<a title=))(.+?(?=>))>(.+?(?=<))((?s:.)+?(?=<a title=))(.+?(?=>))>(.+?(?=<))((?s:.)+?(?=[0-9]))([0-9])((?s:.)+?(?=[0-9]))([a-zA-Z0-9-:.]*)' -AllMatches -ErrorAction SilentlyContinue
			$CurrentUsageClients = $Data | ForEach-Object { $_.Matches.Captures } | ForEach-Object { [PSCustomObject]@{
					ClientID         = $_.groups[4].Value
					ClientIDType     = $_.groups[7].Value
					ClientType       = $_.groups[10].Value
					TotalCountServed = $(try { [Int32]::Parse($($_.groups[12].Value)) } catch { $($_.groups[12].Value) })
					Expiry           = $(try { [DateTime]::Parse($($_.groups[14].Value)) } catch { $($_.groups[14].Value) })
				} 
			}
			$LicencedFeatureDetails += [PSCustomObject]@{
				ID                  = $i
				FeatureName         = $FeatureName
				Version             = $Version
				TotalCount          = [int]::Parse($TotalCount)
				Available           = [int]::Parse($Available)
				CurrentUsage        = [int]::Parse($CurrentUsage)
				ReservedCount       = [int]::Parse($ReservedCount)
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
	}
}
return $LicencedFeatureDetails
