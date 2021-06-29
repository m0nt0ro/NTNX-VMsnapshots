<#
.SYNOPSIS
    A scrip takes VM snapshots in Nutanix
.DESCRIPTION
    Input a file with list of VM names and the script will read the names and take snapshots of these VMs.
.NOTES
    Author         : Henry Tran
    
.UPDATE: June 29 2021
    
.EXAMPLE
    

#>


# Read the current location of the script
Function Get-PSScriptRoot {
    $ScriptRoot = ""

    Try
    {
        $ScriptRoot = Get-Variable -Name PSScriptRoot -ValueOnly -ErrorAction Stop
    }
    Catch
    {
        $ScriptRoot = Split-Path $script:MyInvocation.MyCommand.Path
    }

    Write-Output $ScriptRoot 
}



# Wait a task to complete before proceeding the next one
function Wait-NTNXTask {
    [cmdletbinding()]
    Param(
        # taskUuid returned from Nutanix commands
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$taskUuid,
        
        # If you don't want any data returned, specify this parameter
        [Parameter(Mandatory=$false)]
        [switch]$silent
    )
    Begin {
        if ([string]::IsNullOrEmpty($(Get-PSSnapin -Name NutanixCmdletsPSSnapin -Registered))) {
            Add-PSSnapin NutanixCmdletsPSSnapin
        }
        $task = [PSCustomObject]@{
            status = $null
            taskUuid = $taskUuid
        }
        try {
            [System.Guid]::Parse($taskUuid) | Out-Null
            $valid=$true
        } catch {
            $valid=$false
        }
 
        $notFinished = $true
        $i=0
    } Process {
        if($valid) {
            do {
                try {
                    $taskData = Get-NTNXTask -Taskid $task.taskUuid
                    $task.status = $taskData.progressStatus
                    Write-Verbose "Task: $($taskData | Format-List | Out-String)"
                    if ($taskData.progressStatus -eq "Queued") {
                        Write-Verbose "Waiting for task to complete. Status: $($taskData.progressStatus)"
                        Write-Progress -Activity "Waiting for task to complete" -Status "Task $($taskData.progressStatus)" -PercentComplete 1
                        Start-Sleep -Seconds 1
                    }
                    if ($taskData.progressStatus -eq "Running") {
                        Write-Verbose "Waiting for task to complete. Status: $($taskData.progressStatus)"
                        Write-Progress -Activity "Waiting for task to complete" -Status "Task $($taskData.progressStatus)" -PercentComplete 50
                        Start-Sleep -Seconds 1
                    }
                    if ($taskData.progressStatus -in "Succeeded","Aborted","Failed") {
                        Write-Verbose "Status: $($taskData.progressStatus)"
                        Write-Progress -Activity "Waiting for task to complete" -Status "Task $($taskData.progressStatus)" -PercentComplete 100 -Completed
                        $notFinished = $false
                    }
                    if ([string]::IsNullOrEmpty($taskData.progressStatus)) {
                        Write-Verbose "Unknown status. Status: `"$($taskData.progressStatus)`""
                        $task.status = "Unknown"
                        if($i -gt 10) { Break } else { $i++ }
                        Start-Sleep -Seconds 1
                    }
                } catch {
                    Write-Warning "Caught an error: $($_.Exception.Message | Out-String)"
                    Break
                }
            } while ($notFinished)
        }
    } End {
        if (-Not $Silent) {
            Return $task
        }
    }
}

###############################################################################3

if ([string]::IsNullOrEmpty($(Get-PSSnapin -Name NutanixCmdletsPSSnapin -Registered -ErrorAction SilentlyContinue))) {
    if (Test-Path "C:\Program Files (x86)\Nutanix Inc\NutanixCmdlets\powershell\import_modules\ImportModules.PS1") {

        . "C:\Program Files (x86)\Nutanix Inc\NutanixCmdlets\powershell\import_modules\ImportModules.PS1"

    } else {

        Write-Error "Could not load NutanixCmdletsPSSnapin"

    }

} else {

    if ([string]::IsNullOrEmpty($(Get-PSSnapin -Name NutanixCmdletsPSSnapin -ErrorAction SilentlyContinue))) {

        Add-PSSnapin NutanixCmdletsPSSnapin

    }

}

#Read the list of VM names from the file

$scriptPath = Get-PSScriptRoot
#$listVM = Get-Content "$scriptPath\test.txt"


#Disconnect all previous NTNX sessions
Disconnect-NTNXCluster *

#Connect to the cluster
$NutanixClusterUsername = (Read-Host "Username for $NutanixCluster")
$NutanixClusterPassword = (Read-Host "Password for $NutanixCluster" -AsSecureString)
$NutanixCluster = (Read-Host "Nutanix Cluster")
$connection = Connect-NutanixCluster -server $NutanixCluster -username $NutanixClusterUsername -password $NutanixClusterPassword -AcceptInvalidSSLCerts -ForcedConnection
 if ($connection.IsConnected){
            #connection success
            Write-Host "Connected to $($connection.server)" -ForegroundColor Green
        }
        else{
            #connection failure, stop script
            Write-Warning "Failed to connect to $NutanixCluster"
            Break
        }

#Get-NTNXClusterInfo

#Get VMs info
#Get-NTNXVM  | Select @{Expression={$_.vmname};Label=”VMName”},@{Expression={$_.uuid};Label=”UUID”},@{Expression={$_.powerstate};Label=”PowerState”},@{Expression={$_.hostname};Label=”Hostname”},@{Name=’ipAddresses’;Expression={[string]::join(“ - ”, ($_.ipAddresses))}} 

#Take VM snapshots
foreach ($line in [System.IO.File]::ReadLines("$scriptPath\test.txt"))
{
    
    #Write-Host "VM name is:", $line

    $vm = Get-NTNXVM -SearchString $line
    
    if ($vm.powerState -eq "on")
    {
        # Take snapshot
        $snapshotName = "before-patching-" + (Get-Date).ToShortDateString()
        $newSnapshot = New-NTNXObject -Name SnapshotSpecDTO
        $newSnapshot.vmuuid = $vm.uuid
        $newSnapshot.snapshotname = $snapshotName
        #The UUID of this task object is returned as the response of this operation.
        $task = New-NTNXSnapshot -SnapshotSpecs $newSnapshot
        #Write-Host "Task is: ", $task
        Wait-NTNXTask -taskUuid $task.taskUuid -silent
    }
}


#List all snapshots
#$snapshots = Get-NTNXSnapshot | Where-Object {$_.vmUuid -eq $vm.uuid}
#$snapshots

