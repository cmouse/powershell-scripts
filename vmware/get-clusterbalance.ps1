Function Get-ClusterBalance 
<#
.SYNOPSIS
Calculates the current workload balance between two or more HA availability groups. 

.DESCRIPTION
This commands calculates the workload balance for two or more HA availability groups. It is assumed that all hosts and guests are distributed to 
one DRS group with "should" or "must" rule. The name is split from first "-" to allow naming them per-datacenter style for prettier output. Workload 
balance is calculated simply by checking that each group has it's share of guests by count. CPU or Memory allocations are ignored, all workloads are
assumed same. 

.PARAMETER Cluster
DRS Cluster

.EXAMPLE
Get-ClusterBalance -Cluster Cluster1

.INPUTS
Cluster

.OUTPUTS
Current workload balance.

.COMPONENT
VMware vSphere PowerCLI

#>
{
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
    # workaround for not connected situation, as that is not deemeed as Error
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
