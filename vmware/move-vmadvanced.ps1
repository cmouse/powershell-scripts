Function Get-Storage-Placement {
<#
.SYNOPSIS
Returns storage placement recommendation for VMWare datastore cluster.

.DESCRIPTION
Returns storage placement recommendation for VMWare datastore cluster. It use StorageResourceManager to determine
best datastore to use for placement type. 

.PARAMETER VM
Virtual machine

.PARAMETER DSCluster
Datastore Cluster

.PARAMETER Type
Type of placement, "relocate" or "initial". 

.EXAMPLE
Get-Storage-Placement -VM example-vm -DSCluster DatastoreCluster1 -Type relocate

.INPUTS
VirtualMachineImpl
StorageClusterImpl
String

.OUTPUTS
DataStoreImpl or $null

.COMPONENT
VMware vSphere PowerCLI

#>
  [cmdletbinding()]
  param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $VM,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $DSCluster,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $Type
  )

  begin {
     $DSCluster = Get-DatastoreCluster $DSCluster -ErrorAction Stop
     $VM = Get-VM $VM -ErrorAction Stop
  }

  process {
    $storMgr = Get-View StorageResourceManager
    $storageSpec = New-Object VMware.Vim.StoragePlacementSpec
    $storageSpec.type = $type
    $storageSpec.priority = "defaultPriority"
    $storageSpec.vm = $vm.ExtensionData.MoRef
    $pod = New-Object VMware.Vim.StorageDrsPodSelectionSpec
    $pod.storagePod = $DSCluster.ExtensionData.MoRef
    $storageSpec.podSelectionSpec += $pod
    try {
        $storPlacement = $storMgr.RecommendDatastores($storageSpec)
    } catch {
        return $null
    }
    return $storPlacement.Recommendations[0].Action[0].Destination
  }
}

Function Move-VMAdvanced {
<#
.SYNOPSIS
Performs advanced vMotion, allowing caller to choose new location for config files and each disk. 

.DESCRIPTION
Performs advanced vMotion, allowing caller to choose new location for config files and each disk. Datastores and datastore clusters are both supported. 

.PARAMETER VM
Virtual machine

.PARAMETER Datastore
One or more datastore cluster or datastore

.EXAMPLE
Move-VMAdvanced -VM example-vm -Datastore current,datastore-cluster1,datastore2

.INPUTS
VirtualMachineImpl
String[]

.OUTPUTS
Relocation summary

.COMPONENT
VMware vSphere PowerCLI

#>
   [CmdletBinding()]
   param(
     [parameter(Mandatory=$true, ValueFromPipeline=$true)] $VM,
     [parameter(Mandatory=$true)][string[]] $DataStore
   )

  begin {
    if ($VM.GetType().Name -ne "VirtualMachineImpl") {
      $VM = Get-VM $VM
    }
  }

  process {
    $summary = @()

    $vmdks = Get-HardDisk -VM $VM
    if ($vmdks.GetType().BaseType.Name -ne "System.Array") {
       $vmdks = @($vmdks)
    }
    # if the given datastore is actually a cluster, we need to get storageplacement
    if ($DataStore.Count -ne ($vmdks.Count + 1)) {
      Write-Error "The number of Datastores must be equal to number of hard disks + 1"
      return
    }

    $spec = New-Object VMware.Vim.VirtualMachineRelocateSpec
    if ($Datastore[0] -ne "current") {
      $tds = Get-Datastore $Datastore[0] -ErrorAction SilentlyContinue -ErrorVariable dserror
      if ($dserror) {
         $tds = Get-Storage-Placement -VM $VM -DSCluster $Datastore[0] -Type "relocate"
         if ($tds -eq $null) {
           Write-Error "Could not determine datastore or datastore cluster to use"
           return
         }
      } else {
        $tds = $tds.MoRef
      }
      $spec.Datastore = $tds
      $summaryObj = New-Object System.Object
      $summaryObj | Add-Member -Type NoteProperty -Name Disk -Value Config
      $summaryObj | Add-Member -Type NoteProperty -Name Source -Value ($VM.ExtensionData.Config.Files.VmPathName.Split("[]")[1])
      $summaryObj | Add-Member -Type NoteProperty -Name Destination -Value $Datastore[0]
      $summary += $summaryObj
    } else {
      $summaryObj = New-Object System.Object
      $summaryObj | Add-Member -Type NoteProperty -Name Disk -Value Config
      $summaryObj | Add-Member -Type NoteProperty -Name Source -Value ($VM.ExtensionData.Config.Files.VmPathName.Split("[]")[1])
      $summaryObj | Add-Member -Type NoteProperty -Name Destination -Value ($VM.ExtensionData.Config.Files.VmPathName.Split("[]")[1])
      $summary += $summaryObj
    }

    for ($i=0; $i -lt $vmdks.Count; $i++) {
      $diskSpec = New-Object VMware.Vim.VirtualMachineRelocateSpecDiskLocator
      $diskSpec.DiskId = $vmdks[$i].ExtensionData.Key
      if ($Datastore[$i+1] -eq "current") {
        $tds = $vmdks[$i].ExtensionData.Backing.Datastore
      } else {
        $tds = Get-Datastore -Name $Datastore[$i+1] -ErrorAction SilentlyContinue -ErrorVariable dserror
        if ($dserror) {
           $tds = Get-Storage-Placement -VM $VM -DSCluster $Datastore[$i+1] -Type "relocate"
           if ($tds -eq $null) {
             Write-Error "Could not determine datastore or datastore cluster to use"
             return
           }
        } else {
          $tds = $tds.ExtensionData.MoRef
        }
      }

      $summaryObj = New-Object System.Object
      $summaryObj | Add-Member -Type NoteProperty -Name Disk -Value "Disk-$($i)"
      $summaryObj | Add-Member -Type NoteProperty -Name Source -Value (Get-View $vmdks[$i].ExtensionData.Backing.Datastore).Name
      $summaryObj | Add-Member -Type NoteProperty -Name Destination -Value (Get-View $tds).Name
      $summary += $summaryObj

      $diskSpec.Datastore = $tds
      $spec.Disk += $diskSpec;

    }

    "Relocation summary for $($VM.Name)"
    "=================================="

    $summary | Format-Table -Property Disk,Source,Destination -AutoSize
    # perform task
    $task = $VM.ExtensionData.RelocateVM_Task($spec, "defaultPriority")
    New-Object PSObject -Property @{VM=$VM.Name;Task="$($task.Value)"}
  }
}
