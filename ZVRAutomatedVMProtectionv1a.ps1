#requires -Version 5
#requires -RunAsAdministrator
<#
.SYNOPSIS
   This script automates the protection of VMs using vSphere folders, a CSV containing VPG settings and Zerto Service profiles from a ZCM
.DESCRIPTION
   This is the A version of this script for ZVM sites managed by a ZCM where the use of a service profile is a requirement for the Create/Edit VPG API
.EXAMPLE
   Examples of script execution
.VERSION 
   Applicable versions of Zerto Products script has been tested on.  Unless specified, all scripts in repository will be 5.0u3 and later.  If you have tested the script on multiple
   versions of the Zerto product, specify them here.  If this script is for a specific version or previous version of a Zerto product, note that here and specify that version 
   in the script filename.  If possible, note the changes required for that specific version.  
.LEGAL
   Legal Disclaimer:

----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.

In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without 
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability 
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages.  The entire risk arising out of the use or 
performance of the sample scripts and documentation remains with you.
----------------------
#>
#------------------------------------------------------------------------------#
# Declare variables
#------------------------------------------------------------------------------#
#Examples of variables:

##########################################################################################################################
#Any section containing a "GOES HERE" should be replaced and populated with your site information for the script to work.#  
##########################################################################################################################
#------------------------------------------------------------------------------#
# Configure the variables below using the Production vCenter & ZVM
#------------------------------------------------------------------------------#
$LogDataDir = "EnterLogDir"
$ProfileCSV = "EnterProfileCSVLocation"
$ZertoServer = "EnterZVMIP"
$ZertoPort = "9669"
$ZertoUser = "EnterZVMUser"
$ZertoPassword = "EnterZVMPassword"
$vCenterServer = "EntervCenterIP"
$vCenterUser = "EntervCenterUser"
$vCenterPassword = "EntervCenterPassword"
$VPGProfileNo = "EnterProfileNumber"
$VMsToProtectvCenterFolderName = "EnterVMstoProtectFolder"
$ProtectedVMvCenterFolderName = "EnterProtectedVMsFolder"
$NextVPGCreationDelay = "60"
#------------------------------------------------------------------------------#
# Nothing to configure below this line - Starting the main function of the script
#------------------------------------------------------------------------------#
Write-Host -ForegroundColor Yellow "Informational line denoting start of script GOES HERE." 
Write-Host -ForegroundColor Red "   Legal Disclaimer:

----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.

In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without 
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability 
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages.  The entire risk arising out of the use or 
performance of the sample scripts and documentation remains with you.
----------------------
"
#------------------------------------------------------------------------------#
# Setting log directory for engine and current month
#------------------------------------------------------------------------------#
$CurrentMonth = get-date -format MM.yy
$CurrentLogDataDir = $LogDataDir + $CurrentMonth
$CurrentTime = get-date -format hh.mm.ss
# Testing path exists to engine logging, if not creating it
$ExportDataDirTestPath = test-path $CurrentLogDataDir
$CurrentLogDataFile = $LogDataDir + $CurrentMonth + "\VPGCreationLog-" + $CurrentTime + ".txt"
if ($ExportDataDirTestPath -eq $False)
{
New-Item -ItemType Directory -Force -Path $CurrentLogDataDir
}
start-transcript -path $CurrentLogDataFile -NoClobber
#------------------------------------------------------------------------------#
# Importing PowerCLI snap-in required for successful authentication with Zerto API
#------------------------------------------------------------------------------#
function LoadSnapin{
  param($PSSnapinName)
  if (!(Get-PSSnapin | where {$_.Name   -eq $PSSnapinName})){
    Add-pssnapin -name $PSSnapinName
  }
}
# Loading snapins and modules
LoadSnapin -PSSnapinName   "VMware.VimAutomation.Core"
#------------------------------------------------------------------------------#
# Connecting to vCenter - required for successful authentication with Zerto API
#------------------------------------------------------------------------------#
connect-viserver -Server $vCenterServer -User $vCenterUser -Password $vCenterPassword
#------------------------------------------------------------------------------#
# Building Zerto API string and invoking API
#------------------------------------------------------------------------------#
$baseURL = "https://" + $ZertoServer + ":"+$ZertoPort+"/v1/"
# Authenticating with Zerto APIs
$xZertoSessionURI = $baseURL + "session/add"
$authInfo = ("{0}:{1}" -f $ZertoUser,$ZertoPassword)
$authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
$authInfo = [System.Convert]::ToBase64String($authInfo)
$headers = @{Authorization=("Basic {0}" -f $authInfo)}
$sessionBody = '{"AuthenticationMethod": "1"}'
$TypeJSON = "application/json"
$TypeXML = "application/xml"

$xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURI -Headers $headers -Method POST -Body $sessionBody -ContentType $TypeJSON
#Extracting x-zerto-session from the response, and adding it to the actual API
$xZertoSession = $xZertoSessionResponse.headers.get_item("x-zerto-session")
$zertoSessionHeader_json = @{"Accept"="application/json"
"x-zerto-session"=$xZertoSession}

# URL to create VPG settings
$CreateVPGURL = $BaseURL+"vpgSettings"
#------------------------------------------------------------------------------#
# Importing the CSV of Profiles to use for VM Protection
#------------------------------------------------------------------------------#
$ProfileCSVImport = Import-Csv $ProfileCSV
#------------------------------------------------------------------------------#
# Building an Array of all VMs to protect from the vSphere folder and setting the boot group ID
#------------------------------------------------------------------------------#
# Getting a list of all VMs
$VMsToProtect = get-vm * -Location $VMsToProtectvCenterFolderName | Select-Object Name -ExpandProperty Name
# Getting VM boot group info
$VMBootGroup1List = get-vm * -Location "ZVRBootGroup1" | Select-Object Name 
$VMBootGroup2List = get-vm * -Location "ZVRBootGroup2" | Select-Object Name 
# Setting VM boot group IDs
$VMBootGroup1ID = "00000000-0000-0000-0000-000000000001"
$VMBootGroup2ID = "00000000-0000-0000-0000-000000000002"
# Creating Tag array
$ZVRArray = @()
# Building Array of VMs with boot groups
foreach ($VM in $VMsToProtect)
{
$CurrentVM = $VM.Name
$VPGName = $CurrentVM -replace "-.*"
# Setting VM boot group info
$VMBootGroup1 = $VMBootGroup1List | where {$_.Name -eq "$CurrentVM"} | Select-Object Name -ExpandProperty Name
$VMBootGroup2 = $VMBootGroup2List | where {$_.Name -eq "$CurrentVM"} | Select-Object Name -ExpandProperty Name
# Using IF stattement to set correct boot group ID
if ($VMBootGroup1 -ccontains $CurrentVM)
{
$VMBootGroupID = $VMBootGroup1ID
}
if ($VMBootGroup2 -ccontains $CurrentVM)
{
$VMBootGroupID = $VMBootGroup2ID
}
# Creating Array and adding info for the current VM
$ZVRArrayLine = new-object PSObject
$ZVRArrayLine | Add-Member -MemberType NoteProperty -Name "VMName" -Value $CurrentVM
$ZVRArrayLine | Add-Member -MemberType NoteProperty -Name "VPGName" -Value $VPGName
$ZVRArrayLine | Add-Member -MemberType NoteProperty -Name "BootGroupID" -Value $VMBootGroupID
$ZVRArray += $ZVRArrayLine
# End of for each VM below
}
#------------------------------------------------------------------------------#
# Loading the VPG settings from the CSV, including the ZertoServiceProfile to use
#------------------------------------------------------------------------------#
$ProfileSettings = $ProfileCSVImport | where {$_.ProfileNo -eq "$VPGProfileNo"}
$ServiceProfile = $ProfileSettings.ZertoServiceProfile
$ReplicationPriority = $ProfileSettings.ReplicationPriority
$RecoverySiteName = $ProfileSettings.RecoverySiteName
$ClusterName = $ProfileSettings.ClusterName
$FailoverNetwork = $ProfileSettings.FailoverNetwork
$TestNetwork = $ProfileSettings.TestNetwork
$DatastoreName = $ProfileSettings.DatastoreName
$JournalDatastore = $ProfileSettings.JournalDatastore
$vCenterFolder = $ProfileSettings.vCenterFolder
$BootGroupDelay = $ProfileSettings.BootGroupDelay
#------------------------------------------------------------------------------#
# Creating List of VMs to Protect and profile settings from the Array then selecting unique VPG names
#------------------------------------------------------------------------------#
$VPGsToCreate = $ZVRArray | select VPGName -Unique
# Writing output of VMs to protect
if ($VMsToProtect -eq $null)
{
write-host "No VMs found to protect in vCenter folder:$VMsToProtectvCenterFolderName"
}
else
{
# Writing output of VMs to protect
write-host "Found the below VMs in the vCenter folder to protect:
$VMsToProtect"
}
#------------------------------------------------------------------------------#
# Running the creation process by VPGs to create from the $VPGsToCreate variable, as a VPG can contain multiple VMs
#------------------------------------------------------------------------------#
foreach ($VPG in $VPGsToCreate)
{
$VPGName = $VPG.VPGName
$VPGVMs = $ZVRArray | Where {$_.VPGName -Match "$VPGName"}
$VPGVMNames = $VPGVMs.VMName
# Need to get Zerto Identifier for each VM here
write-host "Creating Protection Group:$VPGName for VMs:$VPGVMNames"
#------------------------------------------------------------------------------#
# Getting the Zerto VM Identifiers for all the VMs to be created in this VPG
#------------------------------------------------------------------------------#
# Get SiteIdentifier for getting Local Identifier later in the script
$SiteInfoURL = $BaseURL+"localsite"
$SiteInfoCMD = Invoke-RestMethod -Uri $SiteInfoURL -TimeoutSec 100 -Headers $zertosessionHeader_json -ContentType $TypeJSON
$LocalSiteIdentifier = $SiteInfoCMD | Select SiteIdentifier -ExpandProperty SiteIdentifier
# Reseting VM identifier list and creating array, needed as this could be executed for multiple VPGs
$VMIdentifierList = $null
$VMIDArray = @()
# Performing for each VM to protect action
foreach ($VMLine in $VPGVMNames)
{
write-host "$VMLine"
# Getting VM IDs
$VMInfoURL = $BaseURL+"virtualizationsites/$LocalSiteIdentifier/vms"
$VMInfoCMD = Invoke-RestMethod -Uri $VMInfoURL -TimeoutSec 100 -Headers $zertosessionHeader_json -ContentType $TypeJSON
$VMIdentifier = $VMInfoCMD | Where-Object {$_.VmName -eq $VMLine} | select VmIdentifier -ExpandProperty VmIdentifier
$VMBootID = $ZVRArray | Where {$_.VMName -Match $VMLine } | Select-Object BootGroupID -ExpandProperty BootGroupID
# Adding VM ID and boot group to array for the API
$VMIDArrayLine = new-object PSObject
$VMIDArrayLine | Add-Member -MemberType NoteProperty -Name "VMID" -Value $VMIdentifier
$VMIDArrayLine | Add-Member -MemberType NoteProperty -Name "VMBootID" -Value $VMBootID
$VMIDArray += $VMIDArrayLine
}
#------------------------------------------------------------------------------#
# Getting Zerto identifiers based on the friendly names in the CSV to use for VPG creation
#------------------------------------------------------------------------------#
# Get SiteIdentifier for getting Identifiers
$TargetSiteInfoURL = $BaseURL+"virtualizationsites"
$TargetSiteInfoCMD = Invoke-RestMethod -Uri $TargetSiteInfoURL -TimeoutSec 100 -Headers $zertosessionHeader_json -ContentType $TypeJSON
$TargetSiteIdentifier = $TargetSiteInfoCMD | Where-Object {$_.VirtualizationSiteName -eq $RecoverySiteName} | select SiteIdentifier -ExpandProperty SiteIdentifier 
# Get NetworkIdentifiers for API
$VISiteInfoURL1 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/networks"
$VISiteInfoCMD1 = Invoke-RestMethod -Uri $VISiteInfoURL1 -TimeoutSec 100 -Headers $zertosessionHeader_json -ContentType $TypeJSON
$FailoverNetworkIdentifier = $VISiteInfoCMD1 | Where-Object {$_.VirtualizationNetworkName -eq $FailoverNetwork}  | Select NetworkIdentifier -ExpandProperty NetworkIdentifier 
$TestNetworkIdentifier = $VISiteInfoCMD1 | Where-Object {$_.VirtualizationNetworkName -eq $TestNetwork}  | Select NetworkIdentifier -ExpandProperty NetworkIdentifier 
# Get ClusterIdentifier for API
$VISiteInfoURL2 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/hostclusters"
$VISiteInfoCMD2 = Invoke-RestMethod -Uri $VISiteInfoURL2 -TimeoutSec 100 -Headers $zertosessionHeader_json -ContentType $TypeJSON
$ClusterIdentifier = $VISiteInfoCMD2 | Where-Object {$_.VirtualizationClusterName -eq $ClusterName}  | Select ClusterIdentifier -ExpandProperty ClusterIdentifier 
# Get ServiceProfileIdenfitifer for API
$VISiteServiceProfileURL = $BaseURL+"serviceprofiles"
$VISiteServiceProfileCMD = Invoke-RestMethod -Uri $VISiteServiceProfileURL -TimeoutSec 100 -Headers $zertosessionHeader_json -ContentType $TypeJSON
$ServiceProfileIdentifier = $VISiteServiceProfileCMD | Where-Object {$_.Description -eq $ServiceProfile}  | Select ServiceProfileIdentifier -ExpandProperty ServiceProfileIdentifier 
# Get DatastoreIdentifiers for API
$VISiteInfoURL3 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/datastores"
$VISiteInfoCMD3 = Invoke-RestMethod -Uri $VISiteInfoURL3 -TimeoutSec 100 -Headers $zertosessionHeader_json -ContentType $TypeJSON
$DatastoreIdentifier = $VISiteInfoCMD3 | Where-Object {$_.DatastoreName -eq $DatastoreName}  | Select DatastoreIdentifier -ExpandProperty DatastoreIdentifier 
$JournalDatastoreIdentifier = $VISiteInfoCMD3 | Where-Object {$_.DatastoreName -eq $JournalDatastore}  | Select DatastoreIdentifier -ExpandProperty DatastoreIdentifier 
# Get Folders for API
$VISiteInfoURL4 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/folders"
$VISiteInfoCMD4 = Invoke-RestMethod -Uri $VISiteInfoURL4 -TimeoutSec 100 -Headers $zertosessionHeader_json -ContentType $TypeJSON
$FolderIdentifier = $VISiteInfoCMD4 | Where-Object {$_.FolderName -eq $vCenterFolder}  | Select FolderIdentifier -ExpandProperty FolderIdentifier
# Outputting API results for easier troubleshooting
write-host "ZVR API Output:
$TargetSiteInfoCMD
$VISiteServiceProfileCMD
$VISiteInfoCMD1
$VISiteInfoCMD2
$VISiteInfoCMD3
$VISiteInfoCMD4"
# DatastoreClusters for API - not used in this example
# $VISiteInfoURL5 = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/datastoreclusters"
# $VISiteInfoCMD5 = Invoke-RestMethod -Uri $VISiteInfoURL5 -TimeoutSec 100 -Headers $zertosessionHeader -ContentType "application/JSON"
# $DataStoreClusterIdentifier = $VISiteInfoCMD5 | Where-Object {$_.FolderName -eq $vCenterFolder}  | Select FolderIdentifier -ExpandProperty FolderIdentifier
# Get HostIdentifier for API - not used in this example as using target cluster (which uses simple round robin)
# $VISiteHostURL = $BaseURL+"virtualizationsites/$TargetSiteIdentifier/hosts"
# $VISiteHostCMD = Invoke-RestMethod -Uri $VISiteHostURL -TimeoutSec 100 -Headers $zertosessionHeader -ContentType "application/JSON"
# $HostIdentifier = $VISiteHostCMD | Where-Object {$_.VirtualizationHostName -eq "Host name here"}  | Select HostIdentifier -ExpandProperty HostIdentifier 
#------------------------------------------------------------------------------#
# Building JSON Request for posting VPG settings to API
#------------------------------------------------------------------------------#
$JSONMain = 
"{
  ""Backup"": null,
  ""Basic"": {
    ""JournalHistoryInHours"": null,
    ""Name"": ""$VPGName"",
    ""Priority"": ""$ReplicationPriority"",
    ""ProtectedSiteIdentifier"": ""$LocalSiteIdentifier"",
    ""RecoverySiteIdentifier"": ""$TargetSiteIdentifier"",
    ""RpoInSeconds"": null,
    ""ServiceProfileIdentifier"": ""$ServiceProfileIdentifier"",
    ""TestIntervalInMinutes"": null,
    ""UseWanCompression"": true,
    ""ZorgIdentifier"": null
  },
  ""BootGroups"": {
    ""BootGroups"": [
      {
        ""BootDelayInSeconds"": 0,
        ""BootGroupIdentifier"": ""00000000-0000-0000-0000-000000000001"",
        ""Name"": ""Web""
      },
      {
        ""BootDelayInSeconds"": ""$BootGroupDelay"",
        ""BootGroupIdentifier"": ""00000000-0000-0000-0000-000000000002"",
        ""Name"": ""Database""
      }
    ]
  },
  ""Journal"": {
    ""DatastoreClusterIdentifier"":null,
    ""DatastoreIdentifier"":""$DatastoreIdentifier"",
    ""Limitation"":{
      ""HardLimitInMB"":null,
      ""HardLimitInPercent"":null,
      ""WarningThresholdInMB"":null,
      ""WarningThresholdInPercent"":null
    }
  },
  ""Networks"": {
    ""Failover"":{
      ""Hypervisor"":{
        ""DefaultNetworkIdentifier"":""$FailoverNetworkIdentifier""
      }
    },
    ""FailoverTest"":{
      ""Hypervisor"":{
        ""DefaultNetworkIdentifier"":""$TestNetworkIdentifier""
      }
    }
  },
  ""Recovery"": {
    ""DefaultDatastoreIdentifier"":""$DatastoreIdentifier"",
    ""DefaultFolderIdentifier"":""$FolderIdentifier"",
    ""DefaultHostClusterIdentifier"":""$ClusterIdentifier"",
    ""DefaultHostIdentifier"":null,
    ""ResourcePoolIdentifier"":null
  },
  ""Scripting"": {
    ""PostBackup"": null,
    ""PostRecovery"": {
      ""Command"": null,
      ""Parameters"": null,
      ""TimeoutInSeconds"": 0
    },
    ""PreRecovery"": {
      ""Command"": null,
      ""Parameters"": null,
      ""TimeoutInSeconds"": 0
    }
  },
  ""Vms"": ["
# Resetting VMs if a previous VPG was created in this run of the script
$JSONVMs = $null
# Creating JSON VM array for all the VMs in the VPG
foreach ($VM in $VMIDArray)
{
$VMID = $VM.VMID
$VMBootID = $VM.VMBootID
$JSONVMsLine = "{""VmIdentifier"":""$VMID"",""BootGroupIdentifier"":""$VMBootID""}"
# Running if statement to check if this is the first VM in the array, if not then a comma is added to string
if ($JSONVMs -ne $null)
{
$JSONVMsLine = "," + $JSONVMsLine
}
$JSONVMs = $JSONVMs + $JSONVMsLine
}
# Creating the end of the JSON request
$JSONEnd = "]
}"
# Putting the JSON request together and outputting the request
$JSON = $JSONMain + $JSONVMs + $JSONEnd
write-host "Running JSON request below:
$JSON"
#------------------------------------------------------------------------------#
# Posting the VPG JSON Request to the API
#------------------------------------------------------------------------------#
Try 
{
$VPGSettingsIdentifier = Invoke-RestMethod -Method Post -Uri $CreateVPGURL -Body $JSON -ContentType $TypeJSON -Headers $zertoSessionHeader_json 
write-host "VPGSettingsIdentifier: $VPGSettingsIdentifier" 
}
Catch {
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
#------------------------------------------------------------------------------#
# Confirming VPG settings from API
#------------------------------------------------------------------------------#
$ConfirmVPGSettingURL = $BaseURL+"vpgSettings/"+"$VPGSettingsIdentifier"
$ConfirmVPGSettingCMD = Invoke-RestMethod -Uri $ConfirmVPGSettingURL -Headers $zertosessionHeader_json -ContentType $TypeJSON
#------------------------------------------------------------------------------#
# Commiting the VPG settings to be created
#------------------------------------------------------------------------------#
$CommitVPGSettingURL = $BaseURL+"vpgSettings/"+"$VPGSettingsIdentifier"+"/commit"
write-host "CommitVPGSettingURL:$CommitVPGSettingURL"
Try 
{
Invoke-RestMethod -Method Post -Uri $CommitVPGSettingURL -ContentType $TypeJSON -Headers $zertosessionHeader_json -TimeoutSec 100
$VPGCreationStatus = "PASSED"
}
Catch {
$VPGCreationStatus = "FAILED"
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
#------------------------------------------------------------------------------#
# Performing vSphere folder change operation to indicate protected VM, only if succesfully protected
#------------------------------------------------------------------------------#
if ($VPGCreationStatus -eq "PASSED")
{
foreach ($_ in $VPGVMNames)
{
# Setting VM name
$VMName = $_
# Changing VM to new folder
write-host "Moving VM $VMName to Folder $ProtectedVMvCenterFolderName"
Move-VM -VM $VMName -Destination $ProtectedVMvCenterFolderName
# End of per VM folder change below
}
# End of per VM folder change below
#
# End of per VM folder action if protection suceeded below
}
# End of per VM folder action if protection suceeded above
#
#------------------------------------------------------------------------------#
# Waiting xx minute/s before creating the next VPG
#------------------------------------------------------------------------------#
write-host "Waiting $NextVPGCreationDelay seconds before processing next VPG or finishing script"
sleep $NextVPGCreationDelay
# End of per VPG actions below
}
# End of per VPG actions above
#------------------------------------------------------------------------------#
# Stopping logging
#------------------------------------------------------------------------------#
stop-transcript
#------------------------------------------------------------------------------#
# Disconnecting from vCenter
#------------------------------------------------------------------------------#
disconnect-viserver $vCenterServer -Force -Confirm:$false