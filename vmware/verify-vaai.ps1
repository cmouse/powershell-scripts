Function Verify-NetApp-VAAI-Installed
{
<#
.SYNOPSIS
Verifies NetApp VAAI plugin installed on Host.

.DESCRIPTION
Verifies NetApp VAAI plugin installed on Host.

.PARAMETER Cluster
Cluster to operate on.

.PARAMETER VMHost
Virtual host to check

.EXAMPLE
Verify-NetApp-VAAI-Installed -Cluster $Cluster -VMHost $vmhost
Checks and outputs the VAAI plugin version on host

.INPUTS
ClusterImpl
VMHostImpl

.OUTPUTS
Status of NetApp VAAI plugin

.COMPONENT
VMware vSphere PowerCLI

#>
    [CmdletBinding()]
    param([parameter(Mandatory=$true)]$Cluster,
          [parameter(Mandatory=$true, valueFromPipeline=$true)]$VMHost)

  begin {
    if ($DefaultVIServers.Count -lt 1)  {
       Throw [string]"You are not connected to any vCenter, please use Connect-VIServer cmdlet"
    }
    Write-Verbose "Loading cluster"
    if ($Cluster.GetType() -eq "".GetType()) {
      $Cluster = Get-Cluster $Cluster
    }
    if ($Host.GetType() -eq "".GetType()) {
      $host = Get-VMHost -Name $Host
    }
  }

  process {
     $esxcli = Get-EsxCli -VMHost $vmhost
     # check that netapp vib is installed
     $plugin = $cli.software.vib.list() | Where-Object { $_.Name -eq "NetAppNasPlugin" }
     if ($plugin) {
        "Found " + $plugin.id + " from " + $vmhost.Name
     } else {
        "NetAppNasPlugin missing from " + $vmhost.Name
     }
  }
}
