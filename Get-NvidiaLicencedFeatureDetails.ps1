<#
.SYNOPSIS
	Get the Nvidia License Feature Details
.DESCRIPTION
	Get the Nvidia License Feature Details
.EXAMPLE
	Get-NvidiaLicencedFeatureDetails.ps1 | Where-Object {$_.FeatureName -eq "GRID-Virtual-PC" }
.NOTES
	File Name : Get-NvidiaLicencedFeatureDetails.ps1
	Version   : v0.3
	Author    : John Billekens
	Requires  : PowerShell v3 and up
	            Nvidia License server v5.1.0 (Limited tested, but no guarantees)
.PARAMETER ServerFQDN
	Specify the License server FQDN
.LINK
	https://blog.j81.nl
#>

[CmdletBinding()]
param (
	[string]$ServerFQDN = "localhost"
)
$LicencedFeatureDetails = @()
try {
	For ($i=1; $i -le 4; $i++) {
		$Uri = "http://$($ServerFQDN):8080/licserver/manageFeatureUsage_featureDetails.action?feature.featureId=$($i)"
		$WebResponse = Invoke-WebRequest -Uri $Uri
		$Data = ((((($WebResponse.AllElements | Where-Object {$_.TagName -eq "TR"})[1].outerText)`
			-replace(": `r`n     ",",")`
			-replace(":  ",",")`
			-replace("Client IDClient ID TypeClient TypeTotal Count ServedExpiry","ClientID,ClientIDType,ClientType,TotalCountServed,Expiry")`
			-replace("Feature Name","FeatureName")`
			-replace("Total count","TotalCount")`
			-replace("Current Usage","CurrentUsage")`
			-replace("Reserved Count","ReservedCount")`
			-replace("Vendor String","VendorString")`
			-replace("Feature Expiry","FeatureExpiry")`
			-replace("   ","")`
			-replace("      ","")`
			-replace(" Back","")`
			-replace(" `r`n","`r`n").Trim()`
			-replace("`r`n`r`n`r`n`r`nBack","`r`n")`
			-replace("`r`n`r`n","`r`n"))`
			-split "`r`n") | ? {$_.trim() -ne "" })`
			-replace(" ",",")
		
		$FeatureName = (($Data | Select-String -pattern "FeatureName")  -split ",")[1]
		if (-not ($FeatureName -eq "")) {
			$Version = (($Data | Select-String -pattern "Version")  -split ",")[1]
			$TotalCount = (($Data | Select-String -pattern "TotalCount")  -split ",")[1]
			$Available = (($Data | Select-String -pattern "Available")  -split ",")[1]
			$CurrentUsage = (($Data | Select-String -pattern "CurrentUsage")  -split ",")[1]
			$ReservedCount = (($Data | Select-String -pattern "ReservedCount")  -split ",")[1]
			$VendorString = (($Data | Select-String -pattern "VendorString")  -split ",")[1]
			$CurrentUsageClients = [PSCustomObject]@{
				ClientID = [string]""
				ClientIDType = [string]""
				ClientType = [string]""
				TotalCountServed = [Int32]0
				Expiry = [Nullable[DateTime]]$null 
			}
			if ($Data | Select-String 'ClientID' -Context 0,999999 -ErrorAction SilentlyContinue -Quiet) {
				$CurrentUsageClients = ($Data | Select-String 'ClientID' -Context 0,999999).ToString()`
				-replace("> C","C")`
				-Replace(" ","") | ConvertFrom-CSV -Delimiter "," | Select-Object ClientID,ClientIDType,ClientType,@{n='TotalCountServed'; e={$_.TotalCountServed -as [Int32]}},@{n='Expiry'; e={$_.Expiry -as [datetime]}}
				
			}
			$LicencedFeatureDetails += [PSCustomObject]@{
				ID = $i
				FeatureName = $FeatureName
				Version = $Version
				TotalCount = [int]::Parse($TotalCount)
				Available = [int]::Parse($Available)
				CurrentUsage = [int]::Parse($CurrentUsage)
				ReservedCount = [int]::Parse($ReservedCount)
				VendorString = $VendorString
				Uri = $Uri
				CurrentUsageClients = $CurrentUsageClients
			}
		}
	}
} catch {}
return $LicencedFeatureDetails
