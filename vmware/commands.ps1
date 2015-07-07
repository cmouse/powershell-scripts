function AddSnapin
{
<#
.SYNOPSIS
Add new Snap-in to powershell if it's not already loaded
.DESCRIPTION
Add new Snap-in to powershell if it's not already loaded. If it's loaded, then no action is taken.
.PARAMETER Name
Name of Snapin to load
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Name
    )

    Process {
        foreach ($n in $name)
        {            
            if (!(Get-PSSnapin $n -ErrorAction SilentlyContinue)) {
                Add-PSSnapin $n
            }
            else {
                Write-Verbose "Skipping $n, already loaded."
            }
        }
    }
}

Function Verify-VAAI
{
<#
.SYNOPSIS
Verifies NetApp VAAI plugin installed on Host. 
 
.DESCRIPTION
Verifies NetApp VAAI plugin installed on Host. 
      
.PARAMETER VMHost
Virtual host to check
      
.INPUTS
VMHostImpl
 
.OUTPUTS
Nothing
 
.COMPONENT
VMware vSphere PowerCLI
#>

    [CmdletBinding()]
    param([parameter(Mandatory=$true, valueFromPipeline=$true)]$VMHost)
          
  begin {  
    if ($DefaultVIServers.Count -lt 1)  {  
       Throw [string]"You are not connected to any vCenter, please use Connect-VIServer cmdlet"
    }
  }
  
  process {
     $esxcli = Get-EsxCli -VMHost $VMHost
     # check that netapp vib is installed
     $plugin = $cli.software.vib.list() | Where-Object { $_.Name -eq "NetAppNasPlugin" }
     if ($plugin) {
        "Found " + $plugin.id + " from " + $vmhost.Name
     } else {
        "NetAppNasPlugin missing from " + $vmhost.Name
     }
  }
}

Function Get-VMDrsGroup {
<#
.SYNOPSIS
Retrieves VM's DRS groups from a cluster.
 
.DESCRIPTION
Retrieves VM's DRS groups from a cluster.
 
.PARAMETER Cluster
Specify the cluster for which you want to retrieve the DRS groups
      
.PARAMETER VM 
Specify the Virtual Machine you want to look for

.EXAMPLE
Get-VMDrsGroup -Cluster $Cluster -VM $vm
Retrieves the VM $vm DRS Group from cluster $Cluster.
      
.INPUTS
ClusterImpl
VMImpl
 
.OUTPUTS
ClusterVmGroup
 
.COMPONENT
VMware vSphere PowerCLI
#>
  [CmdletBinding()]
  param([parameter(Mandatory=$true)] $Cluster,
  [parameter(Mandatory=$true, ValueFromPipeline=$true)] $VM) 

  begin {
    if ($Cluster.GetType() -eq "".GetType()) {
       $Cluster = Get-Cluster -Name $Cluster 
    }
    if ($VM.GetType() -eq "".GetType()) {
        $VM = Get-VM -Location $Cluster -Name $VM 
    }
    
    if ($VM.GetType().Name -eq "VirtualMachine") {
      $ref = $VM.MoRef
    } else {
      $ref = $VM.ExtensionData.MoRef
    }
  }

  process {    
    if($Cluster) {
       foreach($DrsGroup in $Cluster.ExtensionData.ConfigurationEx.Group) { 
        if ($DrsGroup.GetType().Name -eq "ClusterVmGroup") { 
          if ($DrsGroup.Vm -contains $ref) {
            return $DrsGroup
          }
        }
      }
    }
  }
}

Function Get-DrsGroup {
<#
.SYNOPSIS
Retrieves DRS groups from a cluster.
 
.DESCRIPTION
Retrieves DRS groups from a cluster.
 
.PARAMETER Cluster
Specify the cluster for which you want to retrieve the DRS groups
 
.PARAMETER Name
Specify the name of the DRS group you want to retrieve.
 
.EXAMPLE
Get-DrsGroup -Cluster $Cluster -Name "VMs DRS Group"
Retrieves the DRS group "Vms DRS Group" from cluster $Cluster.
 
.EXAMPLE
Get-Cluster | Get-DrsGroup
Retrieves all the DRS groups for all clusters.
 
.INPUTS
ClusterImpl
 
.OUTPUTS
ClusterVmGroup
ClusterHostGroup
 
.COMPONENT
VMware vSphere PowerCLI
#>
  [CmdletBinding()]
  param([parameter(Mandatory=$true, ValueFromPipeline=$true)]$Cluster,
        [string] $Name="*")

  begin {
    if ($Cluster.GetType() -eq "".GetType()) {
       $Cluster = Get-Cluster -Name $Cluster
    }
  }
 
  process {
    $Cluster = Get-Cluster -Name $Cluster
    if($Cluster) {
      $Cluster.ExtensionData.ConfigurationEx.Group | `
      Where-Object {$_.Name -like $Name}
    }
  }
}

Function Add-VMToDrsGroup {
<#
.SYNOPSIS
Adds a virtual machine to a cluster VM DRS group.
 
.DESCRIPTION
Adds a virtual machine to a cluster VM DRS group.
 
.PARAMETER Cluster
Specify the cluster for which you want to retrieve the DRS groups
 
.PARAMETER DrsGroup
Specify the DRS group you want to retrieve.
 
.PARAMETER VM
Specify the virtual machine you want to add to the DRS Group.
 
.EXAMPLE
Add-VMToDrsGroup -Cluster $Cluster -DrsGroup "VM DRS Group" -VM $VM
Adds virtual machine $VM to the DRS group "VM DRS Group" of cluster $Cluster.
 
.EXAMPLE
Get-Cluster MyCluster | Get-VM "A*" | Add-VMToDrsGroup -Cluster MyCluster -DrsGroup $DrsGroup
Adds all virtual machines with a name starting with "A" in cluster MyCluster to the DRS group $DrsGroup of cluster MyCluster.
 
.INPUTS
VirtualMachineImpl
 
.OUTPUTS
Task
 
.COMPONENT
VMware vSphere PowerCLI
#>
  [CmdletBinding()]
  param([parameter(Mandatory=$true)] $Cluster,
        [parameter(Mandatory=$true)] $DrsGroup,
        [parameter(Mandatory=$true, ValueFromPipeline=$true)] $VM)
       
  begin {
    if ($Cluster.GetType() -eq "".GetType()) {
       $Cluster = Get-Cluster -Name $Cluster
    }
  }
 
  process {
    if ($Cluster) {
      if ($DrsGroup.GetType().Name -eq "string") {
        $DrsGroupName = $DrsGroup
        $DrsGroup = Get-DrsGroup -Cluster $Cluster -Name $DrsGroup
      }
      if (-not $DrsGroup) {
        Write-Error "The DrsGroup $DrsGroupName was not found on cluster $($Cluster.name)."
      }
      else {
        if ($DrsGroup.GetType().Name -ne "ClusterVmGroup") {
          Write-Error "The DrsGroup $DrsGroupName on cluster $($Cluster.Name) doesn't have the required type ClusterVmGroup."
        }
        else {
          $VM = $Cluster | Get-VM -Name $VM
          If ($VM) {
            $spec = New-Object VMware.Vim.ClusterConfigSpecEx
            $spec.groupSpec = New-Object VMware.Vim.ClusterGroupSpec[] (1)
            $spec.groupSpec[0] = New-Object VMware.Vim.ClusterGroupSpec
            $spec.groupSpec[0].operation = "edit"
            $spec.groupSpec[0].info = $DrsGroup
            $spec.groupSpec[0].info.vm += $VM.ExtensionData.MoRef
 
            $Cluster.ExtensionData.ReconfigureComputeResource_Task($spec, $true)
          }
        }
      }
    }
  }
}

Function Get-ClusterBalance 
{
<#
.SYNOPSIS 
Calculates balance of a metrocluster. Will not work unless you modify this to your purposes
.DESCRIPTION
Calculates balance of a metrocluster. Will not work unless you modify this to your purposes
.PARAMETER Cluster
Cluster name to check
#>


  [CmdletBinding()]
  param([parameter(Mandatory=$true, ValueFromPipeline=$true)] $Cluster)
  
  begin {  
  }

  process {
    if ($Cluster.GetType() -eq "".GetType()) {
      $Cluster = Get-Cluster $Cluster -ErrorAction Stop
      if ($Cluster -eq $null) {
        return
      }
    }    
    if ($DefaultVIServers -eq $null -or $DefaultVIServers.Count -eq 0) {
       return 
    }
    # discover cluster sides
    Write-Verbose "Discovering cluster DRS groups"
    $groups = @{}
    $totalHosts = 0
    $totalVms = 0
    foreach($DrsGroup in $Cluster.ExtensionData.ConfigurationEx.Group) {
       Write-Debug "Discovered DRS $($DrsGroup.GetType().Name) $($groupName)"
       # initialize whatever the type is
       $groupName = $DrsGroup.Name.Split("-")[0]
       if (!$groups.ContainsKey($groupName)) {
          $groups.Set_Item($groupName, @{"hosts"=0;"vms"=0})
       }
       if ($DrsGroup.GetType().Name -eq 'ClusterHostGroup') {
          $groups[$groupName]["hosts"] += $DrsGroup.Host.Length
          $totalHosts += $DrsGroup.Host.Length
       }
       if ($DrsGroup.GetType().Name -eq 'ClusterVmGroup') {
          $groups[$groupName]["vms"] += $DrsGroup.Vm.Length
          $totalVms += $DrsGroup.Vm.Length
       }
    }
    "Current cluster balance"
    "-----------------------"
    $perHost = $totalVms / $totalHosts
    foreach($group in $groups.GetEnumerator()) {
        # check how much over / below the calculated workload we are
        $target = [int]($perHost * $group.Value["hosts"])
        $devi = ([float]($group.Value["vms"] - $target)/[float]$target)*100
        
        "{0} deviates {1:F2}% ({4}) from target ( current: {2}, target: {3} )" -f $group.Name, $devi, $group.Value["vms"], [int]$target, ($group.Value["vms"] - $target)
    }
  }
}

Function ResourcePoolPath {
   param(
      [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
      [AllowNull()]
      $pool
   )
   
   process {
      if ($pool -eq $null) {
         return "<null>"
      }
   
      $path = [System.Collections.ArrayList]@()
      while($pool.parent) {
        #$pool.Name
        $path.insert(0, $pool.Name)
        $pool = $pool.parent
      }
      $path.insert(0, $pool.Name)
      return [system.String]::join("\", $path)
   }
}

Function Search-VM {
<#
.SYNOPSIS
Searches for a given VM with partial name.
.DESCRIPITION
Searches the given name partial from all virtual machine names. It returns name, host, location and current IP address(es) of all matched machines.
.PARAMETER NamePartial
Partial name to match for
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $NamePartial
    )
    
    begin {
      if ($DefaultVIServers.Count -lt 1)  {  
        Write-Error "You are not connected to any vCenter, please use Connect-VIServer cmdlet"
        return 
      }
    }
    
    process {
      Write-Verbose ("Search for {0}" -f $NamePartial)
      Get-VM | % {
        if ($_.Name -ilike ("*{0}*" -f $NamePartial)) {
          $vmg = Get-VMGuest $_
          if ($_.ResourcePoolId -Match "VirtualApp-*") {
             $objData = @{"Name"=$_.Name;"vApp"=(Get-vApp -ID $_.ResourcePoolId).Name;"IP"=[system.String]::Join(", ", $vmg.IPAddress);"Host"=$_.VMHost}
          } else {
             $objData = @{"Name"=$_.Name;"Location"=(ResourcePoolPath -pool $_.Folder);"IP"=[system.String]::Join(", ", $vmg.IPAddress);"Host"=$_.VMHost;"ResourcePool"=(ResourcePoolPath -Pool $_.ResourcePool)}
          }
          $objData | Format-Table -Autosize
        }
      }
    }
}

Function Fix-Rogue-VM {
<#
.SYNOPSIS
Searches and assings all non-assigned VM's to a DRS group.
.DESCRIPTION
Searches and assings all non-assigned VM's to a DRS group. Will only work if you modify it to your purposes
.PARAMETER Cluster 
Cluster to operate on
#>
  param([parameter(Mandatory=$true,ValueFromPipeline=$true)] $Cluster)

  begin {
    if ($Cluster.GetType() -eq "".GetType()) {
       $Cluster = Get-Cluster -Name $Cluster
    }
  }
  
  process {
     $groups = @()
     # get all DRS Groups from Cluster
     foreach($DrsGroup in $Cluster.ExtensionData.ConfigurationEx.Group) { 
       if ($DrsGroup.GetType().Name -eq "ClusterVmGroup") { 
          $groups += $DrsGroup
        }
     }
     
     # then process all VMs
     Get-VM -Location $Cluster | ForEach-Object -Process {
       $vmref = $_.ExtensionData.MoRef
       $found = $false
       
       $groups | ForEach-Object -Process {
         if ($found -Eq $false -And $_.Vm -contains $vmref) {
           $found = $true
        }
       }
         
       if ($found -eq $false) {
         "Rogue VM " + $_.Name + " found - Fixing"
         $storage = ($_ | get-datastore | select-object -index 0).name
         if (-not ($storage -match "dcright_" -or $storage -match "dcleft_")) {
           $storage = ($_ | get-datastore | select-object -Index 1).name
         }
         if ($storage -Match "dcright_") {
           # this should go into dcright-drsgroup
           "Add to dcright-group"
           Add-VMToDrsGroup -Cluster $Cluster -DrsGroup "dcright-group" -VM $_
         } elseif ($storage -Match "dcleft_") {
           "Add to dcleft-group"
           Add-VMToDrsGroup -Cluster $Cluster -DrsGroup "dcleft-group" -VM $_
         }
       }
     }
  }
}

Function Download-File {
   [CmdletBinding()]
   Param (
     [parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)][string] $url,
     [parameter(Mandatory=$false,Position=1,ValueFromPipeline=$true)][string] $file
   )
   
   process {
      $client = New-Object System.Net.WebClient
      if ($file) {
        return $client.DownloadFile($url, $file)
      } else {
        return $client.DownloadString($url)
      }
   }  
}

Function Find-Storage-Mismatch {
<#
.SYNOPSIS
Searches any virtual machines with disks cross data center border.
.DESCRIPTION
Searches any virtual machines with disks cross data center border. Only works if you modify it to your purposes
.PARAMETER Cluster
Cluster to operate on
#>
   [CmdletBinding()]
   param(
     [parameter(Mandatory=$true, ValueFromPipeline=$true)] $Cluster
   )

   begin {
    if ($Cluster.GetType() -eq "".GetType()) {
      $Cluster = Get-Cluster $Cluster -ErrorAction Stop
    }
   }

   process {
     Get-VM -Location $Cluster | % {
        $VM = $_
        $group = (Get-VMDrsGroup -Cluster $cluster -VM $vm).Name.Split("-")[0]
        # then we look at storage
        # check configuration location
        $ds = Get-Datastore -Name ($vm.ExtensionData.Config.Files.VmPathName.Split("[]")[1])
        if ($ds.ParentFolderId -Match "StoragePod") {
          $ds = Get-DatastoreCluster -ID $ds.ParentFolderId
          $dscluster = $true
        }
        $dsname = $ds.Name.Split("_")[0]
        # then we check the name prefix, if it's wrong, remediate
        if ($dsname -ne $group -and ($dsname -eq "dcleft" -or $dsname -eq "dcright")) {
             "Guest " + $VM.name + " storage location " + $ds.Name + " does not match with location in " + $group
        }        
        $VM.HardDisks | % {
          $dscluster = $false
          $ds = Get-Datastore -ID $_.ExtensionData.Backing.DataStore
          if ($ds.ParentFolderId -Match "StoragePod") {
            $ds = Get-DatastoreCluster -ID $ds.ParentFolderId
            $dscluster = $true
          }
          $dsname = $ds.Name.Split("_")[0]
          # then we check the name prefix, if it's wrong, remediate
          if ($dsname -ne $group -and ($dsname -eq "dcleft" -or $dsname -eq "dcright")) {
             "Guest " + $VM.name + " storage location " + $ds.Name + " does not match with location in " + $group
          }
        }
     }
   }
}

Function Get-Storage-Placement {
<#
.SYNOPSIS
Returns storage placement object for given VM and datastore cluster. 
.DESCRIPTION
This command asks Datastore Cluster to return storage placement for this VM when moved into the given datastore cluster. 
.PARMETER VM
Virtual machine
.PARAMETER DSCluster
Datastore cluster
.PARAMETER Type
relocate, clone, create, reconfigure
.SEE
https://pubs.vmware.com/vsphere-55/index.jsp#com.vmware.wssdk.apiref.doc/vim.storageDrs.StoragePlacementSpec.PlacementType.html
#>
  [cmdletbinding()]
  param(
    [parameter(Mandatory=$true,ValueFromPipeline=$true)]
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
    #try {
        $storPlacement = $storMgr.RecommendDatastores($storageSpec) 
    #} catch {
    #    return $null
    #}
    return $storPlacement.Recommendations[0].Action[0].Destination
  }
}

Function Move-VMAdvanced {
<#
.SYNOPSIS 
Performes advanced datastore movement. 
.DESCRIPTION
Performes advanced Move-VM allowing you to specify per-disk datastores. 
.PARAMETER VM
Virtual machine
.PARAMETER DataStore
Array of datastore(s) to set for the machine. You need to specify at least two. First datastore is for configuration files. 
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
           $tds = GetStoragePlacement -VM $VM -DSCluster $Datastore[$i+1] -Type "relocate"
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

Function Fix-Storage-Mismatch {
<#
.SYNOPSIS
Fixes virtual machines with disks cross data center border.
.DESCRIPTION
Fixes virtual machines with disks cross data center border. Only works if you modify it to your purposes
.PARAMETER VM
Virtual machine(s) to operate on
#>
   [CmdletBinding()]
   param(
     [parameter(Mandatory=$true, ValueFromPipeline=$true)][string[]] $VM
   )
      
   process {
     # relocate storage if necessary
     # first, we need to figure out DRS group
     $VM | % {
         $virt = Get-VM -Name $_
         $cluster = $virt | Get-Cluster
         $group = (Get-VMDrsGroup -Cluster $cluster -VM $virt).Name
         if ($group -eq $null) {
            Write-Warning "Cannot fix $($virt.Name) - not in any DRS group"
            return
         }
         $group = $group.Split("_-")[0]
         $locations = @()
         $doit = $false
         $ds = Get-Datastore -Name ($virt.ExtensionData.Config.Files.VmPathName.Split("[]")[1])
         if ($ds.ParentFolderId -Match "StoragePod") {
            $ds = Get-DatastoreCluster -ID $ds.ParentFolderId
            $dscluster = $true
         }
         $dsname = $ds.Name.Split("_")[0]
         if ($dsname -ne $group -and ($dsname -eq "dcleft" -or $dsname -eq "dcright")) {
           # relocate this
           $locations += $ds.Name -Replace $dsname, $group
           $doit = $true
         } else {
           $locations += "current"
         }
         # then we look at storage
         $virt.HardDisks | % {
            $dscluster = $false
            $ds = $ds = Get-Datastore -ID $_.ExtensionData.Backing.DataStore
            if ($ds.ParentFolderId -Match "StoragePod") {
                $ds = Get-DatastoreCluster -ID $ds.ParentFolderId
                $dscluster = $true
            }
            $dsname = $ds.Name.Split("_")[0]
            # then we check the name prefix, if it's wrong, remediate
            if ($dsname -ne $group -and ($dsname -eq "dcleft" -or $dsname -eq "dcright")) {
               # remediate
               $dsname = $ds.Name -Replace $dsname, $group
               $locations += $dsname
               $doit = $true
            } else {
               $locations += "current"
            }
         }
        
         if ($doit) {
           "$($virt.Name) needs relocation"
           # apply changes
           Move-VMAdvanced -VM $virt -DataStore $locations
         }
       }
   }    
}

Function Create-Standard-Network {
<#
.SYNOPSIS
Creates a standard network on all cluster members
.DESCRIPTION
Creates a standard network on all cluster members. It takes a list of vlans and names and creates one network per pair. 
.PARAMETER Cluster
Cluster to operate on
.PARAMETER vSwitch
Virtual switch to use
.PARAMETER VLAN
List of VLANs to create
.PARAMETER Name
List of VLAN names
.EXAMPLE
Get-Datacenter hel6 | Get-Cluster Cluster1 | Create-Standard-Network -VLAN 1,2,3 -Name alpha,beta,ceta
#>
   [CmdletBinding()]
   param(
     [parameter(Mandatory=$true, ValueFromPipeline=$true)]
     [ValidateNotNullOrEmpty()]
     $Cluster,
     [parameter(Mandatory=$true, ValueFromPipeline=$false)][string]$vSwitch,
     [parameter(Mandatory=$true, ValueFromPipeline=$false)][int[]]$VLAN,
     [parameter(Mandatory=$true, ValueFromPipeline=$false)][string[]]$Name
    )
    begin {
        if ($VLAN.Count -ne $Name.Count) {
            Write-Error -Message "VLAN count does not match Name count"
        }
    }

    process {
        $Cluster | Get-VMHost | foreach { 
            $target = $_ | Get-VirtualSwitch -Name $vSwitch
            for($i=0; $i -le $VLAN.Count; $i++) {
                if ($Name[$i] -eq $null) { continue; }
                New-VirtualPortGroup -VirtualSwitch $target -Name $Name[$i] -VLanId $VLAN[$i]                
            }
        }
    }
 }

    
function Migrate-VM
{
<#
.SYNOPSIS
Relocates Virtual Machine from one Data Center to another (across virtual centers)
.DESCRIPTION
This command relocates virtual machine between two data centers. It will allow you to reregister disks and change network adapters. Please note that the virtual machine
is unregisterd from source cluster and registered to target cluster as new virtual machine. VM must be shut down during the operation or it will fail and cause damage. 
.PARAMETER VM
Virtual machine(s) to relocate. 
.PARAMETER DestinationCluster
Destination cluster for the migration
.PARAMETER Folder
Destination folder 
.PARAMETER Network
New virtual network(s) to use. 
.PARAMETER RegisterDisks
Readd hard disks after migration
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$VM,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $DestinationCluster,
        [Parameter(Mandatory=$false)]
        [string]
        $Folder,
        [Parameter(Mandatory=$false)]
        [string[]]
        $Network,
        [Parameter(Mandatory=$false)]
        [switch]$RegisterDisks
    )

    process {
        # locate VM
        $ret = @()
        $VM | foreach {
            $victim = Get-VM $_
            $disks = @()
            $victim | Get-HardDisk | foreach {
                $disks += $_.Filename
            }
            
             
            $config = $victim.ExtensionData.LayoutEx.File | Where-Object { $_.Name -match ".vmx$" }
               
            if ($config -eq "") {
                return
            } 

            $src = ($victim | Get-Cluster)

            $srcdc = (Get-DataCenter -Cluster $src)

            if ([VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl] -eq $DestinationCluster.GetType()) {
               $dstdc = Get-DataCenter -Cluster $DestinationCluster
            } else {
               $dstdc = (Get-DataCenter -Cluster ($DestinationCluster | Get-Cluster)) # in case the target is actually a ResourcePool
            } 

            "Moving " + $victim.Name + " from " + $srcdc.Name + "/" + $src.Name + " to " + $dstdc.Name + "/" + $DestinationCluster.Name +" with config file " + $config.Name | Write-Verbose

            $vmname = $victim.Name
            $configname = $config.Name
            $scsiType = ($victim | Get-ScsiController).Type

            # lets try it
            Remove-VM $victim -Confirm:$false 

            # I suppose it would not hurt to wait here for a little while
            Start-Sleep 10

            $victim2 = New-VM -VMFilePath $configname -Name $vmname -ResourcePool $DestinationCluster
            if ($Folder) {
                Move-VM -VM $victim2 -Location (Get-Folder $Folder)
            }

            # repair disks
            if ($RegisterDisks -and $disks.Count -gt 1) {
                $victim2 | Get-HardDisk | foreach {
                    $_ | Remove-HardDisk -Confirm:$false 
                }
                $disks | foreach {
                    $victim2 | New-HardDisk -DiskPath $_ -Confirm:$false | Out-Null
                }
            }
            # repair SCSI controller

            $victim2 | Get-ScsiController | Set-ScsiController -Type $scsiType -Confirm:$false

            if ($Network.Count -gt 0) {
                $idx = 0
                $victim2 | Get-NetworkAdapter | foreach {
                    "Setting interface " + $idx + " to " + $Network[$idx] | Write-Verbose
                    $_ | Set-NetworkAdapter -NetworkName $Network[$idx] -Confirm:$false | Out-Null
                    $idx = $idx+1
                }
            }

            $ret += $victim2 
        }

        $ret
    }
}

Function ConvertVMTo-Hashtable {
<#
.Synopsis
converts VM to hash table using select entries
.Description
Converts VM to an hash table using various pre-selected attributes. 
.Parameter VM
Virtual machines to convert
#>

[cmdletbinding()]
Param(
  [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
  [ValidateNotNullorEmpty()]
  [object[]]$VM
)

Process {
  $ret = @()
  $VM | ForEach-Object {
    $hash = New-Object -TypeName PSObject
    $VMobj = Get-VM -Name $_

    $hash | Add-Member -MemberType NoteProperty -Name Folder -Value $VMobj.Folder.Name
    $hash | Add-Member -MemberType NoteProperty -Name Name -Value $VMobj.Name
    $hash | Add-Member -MemberType NoteProperty -Name GuestOS -Value $VMobj.Guest.OSFullName
    $hash | Add-Member -MemberType NoteProperty -Name Hostname -Value $VMobj.Guest.HostName
    $hash | Add-Member -MemberType NoteProperty -Name IPAddress -Value $VMobj.Guest.IPAddress[0]
    $hash | Add-Member -MemberType NoteProperty -Name MemoryGB -Value $VMobj.MemoryGB
    $hash | Add-Member -MemberType NoteProperty -Name DiskGB -Value $VMobj.ProvisionedSpaceGB
    $hash | Add-Member -MemberType NoteProperty -Name NumCpu -Value $VMobj.NumCpu

    $ret += $hash
  }

  Write-Output $ret
}

}

AddSnapin VMware.VimAutomation.Core
AddSnapin VMware.VimAutomation.Vds
#AddSnapin VMware.VumAutomation
AddSnapin VMware.VimAutomation.License
AddSnapin VMware.DeployAutomation
AddSnapin VMware.ImageBuilder
