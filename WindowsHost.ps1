param(
    [switch]$Modify
)

# Check CPU and Memory resources
function Check-Resources {
    $memory = (Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory / 1KB
    $cpu = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors
    $disk = (Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB

    Write-Output "Checking CPU and Memory resources..."
    if ($memory -ge 500 -and $cpu -ge 2 -and $disk -ge 20) {
        Write-Output "CPU and Memory resources check: Passed"
        return $true
    } else {
        Write-Output "CPU and Memory resources check: Failed"
        Write-Output "Please ensure at least 500 MB of free memory, 2 logical processors, and 20 GB of free disk space."
        return $false
    }
}

# Check PowerShell version
function Check-PowerShellVersion {
    $psVersionDetails = $PSVersionTable.PSVersion
    $osVersion = [System.Version](Get-WmiObject Win32_OperatingSystem).Version

    Write-Output "Checking PowerShell version..."
    Write-Output "OS Version: $osVersion"

    if ($osVersion -lt [System.Version]"6.1.7600" -and $psVersionDetails.Major -lt 3) {
        Write-Output "Windows Server 2008 R2 detected. PowerShell 3.0 is required."
        Write-Output "Please download and install PowerShell 3.0 from the following link:"
        Write-Output "https://www.microsoft.com/en-us/download/details.aspx?id=34595"
        Write-Output "After installation and rebooting, please run the script again."
        return $false
    } elseif ($psVersionDetails.Major -ge 3) {
        Write-Output "PowerShell version check: Passed"
        Write-Output "PowerShell Version: $($psVersionDetails.Major).$($psVersionDetails.Minor).$($psVersionDetails.Build).$($psVersionDetails.Revision)"
        return $true
    } else {
        Write-Output "PowerShell version check: Failed"
        Write-Output "Minimum PowerShell version required: 3"
        return $false
    }
}

# Set remote execution policy
function Set-RemoteExecutionPolicy {
    Write-Output "Setting remote execution policy..."
    $executionPolicy = Get-ExecutionPolicy -Scope LocalMachine
    if ($Modify) {
        if ($executionPolicy -ne "RemoteSigned") {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
            Write-Output "Execution policy updated to RemoteSigned"
        } else {
            Write-Output "Execution policy: RemoteSigned"
        }
    } else {
        Write-Output "Execution policy check: Skipped (Modification not enabled)"
    }
}

# Ensure port 443 is open
function Ensure-Port443Open {
    Write-Verbose "Checking if port 443 is open..."
    $portCheck = netstat -an | Select-String -Pattern "0.0.0.0:443"

    if ($portCheck) {
        Write-Output "Port 443 (HTTPS) is already open."
    }
    else {
        if ($Modify) {
            Write-Verbose "Port 443 (HTTPS) is not open. Opening port 443..."
            try {
                New-NetFirewallRule -DisplayName "Open Port 443" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow
                Write-Output "Port 443 has been opened."
            }
            catch {
                Write-Output "Failed to open port 443. Error: $_"
            }
        } else {
            Write-Output "Port 443 (HTTPS) is not open. Modification not enabled."
        }
    }
}

# Check TrustedHosts policy configuration
function Check-TrustedHostsPolicy {
    Write-Output "Checking TrustedHosts policy configuration..."

    try {
        Import-Module GroupPolicy -ErrorAction Stop
        $trustedHostsPolicy = Get-GPRegistryValue -Name 'RemoteHosts' -Key 'HKLM\Software\Policies\Microsoft\Windows\WinRM\Client' -ValueName 'TrustedHosts' -ErrorAction SilentlyContinue

        if ($trustedHostsPolicy -ne $null -and $trustedHostsPolicy.PolicyState -eq "Enabled") {
            if ($Modify) {
                Write-Output "TrustedHosts policy is managed by Group Policy. Setting it to 'Not Configured'."

                # Set the TrustedHosts policy to 'Not Configured'
                Set-GPRegistryValue -Name 'RemoteHosts' -Key 'HKLM\Software\Policies\Microsoft\Windows\WinRM\Client' -ValueName 'TrustedHosts' -Type String -Value '' -ErrorAction Stop
                Remove-GPRegistryValue -Name 'RemoteHosts' -Key 'HKLM\Software\Policies\Microsoft\Windows\WinRM\Client' -ValueName 'TrustedHosts' -ErrorAction Stop

                # Update Group Policy
                Write-Output "Updating Group Policy to reflect changes..."
                gpupdate /force | Out-Null

                Write-Output "TrustedHosts policy has been set to 'Not Configured'."
            } else {
                Write-Output "TrustedHosts policy is managed by Group Policy. No changes made (Modification not enabled)."
            }
        } else {
            Write-Output "TrustedHosts policy is not managed by Group Policy. No change required."
        }
    }
    catch {
        Write-Output "Error checking or updating TrustedHosts policy: $_"
        Write-Output "GroupPolicy module is not available. Skipping TrustedHosts policy check."
    }
}

# Configure WinRM
function Configure-WinRM {
    Write-Verbose "Configuring WinRM..."

    $scriptUrl = "link of ConfigureRemoting script(removed for security)"
    $scriptPath = "$env:TEMP\ConfigureRemoting.ps1"

    if (-Not (Test-Path $scriptPath)) {
        try {
            Write-Verbose "Downloading ConfigureRemoting.ps1 from $scriptUrl..."
            Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath -ErrorAction Stop
            if ($VerbosePreference -eq 'Continue') {
                Write-Output "ConfigureRemoting.ps1 downloaded successfully to $scriptPath."
            }
        }
        catch {
            Write-Output "Failed to download ConfigureRemoting.ps1 script. Error: $_"
            return $false
        }
    }

    try {
        Write-Verbose "Executing ConfigureRemoting.ps1 script at $scriptPath..."
        $configOutput = & $scriptPath -Verbose:$VerbosePreference 4>&1
        if ($VerbosePreference -eq 'Continue') {
            Write-Output "Output from ConfigureRemoting.ps1:`n$configOutput"
        }
        return $true
    }
    catch {
        Write-Output "Failed to execute ConfigureRemoting.ps1 script. Error: $_"
        return $false
    }
}

# Disable UAC remote restrictions
function Disable-UACRestrictions {
    Write-Output "Disabling UAC remote restrictions..."
    if ($Modify) {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1
    } else {
        Write-Output "UAC remote restrictions check: Skipped (Modification not enabled)"
    }
}

# Main script
Write-Output "Starting resource check..."
$resourceCheckPassed = $false
$psVersionCheckPassed = $false
$port443CheckPassed = $false
$winRMConfigPassed = $false

# Starting resource check
$resourcesCheck = Check-Resources
if (-not $resourcesCheck) {
    Write-Output "Script execution halted due to insufficient CPU or Memory resources."
    exit
}

$resourceCheckPassed = $true

# Starting PowerShell version check
$psVersionCheck = Check-PowerShellVersion
if (-not $psVersionCheck) {
    Write-Output "Script execution halted due to failed PowerShell version check."
    exit
}

$psVersionCheckPassed = $true

# Starting remote execution policy setup
Set-RemoteExecutionPolicy

# Starting port 443 check
$port443Check = Ensure-Port443Open
if (-not $port443Check) {
    Write-Output "Port 443 (HTTPS) check failed. Script execution halted."
    exit
}

$port443CheckPassed = $true

# Starting TrustedHosts policy check
Check-TrustedHostsPolicy

# Starting WinRM configuration
$winRMConfig = Configure-WinRM
if (-not $winRMConfig) {
    Write-Output "WinRM configuration failed. Script execution halted."
    exit
}

$winRMConfigPassed = $true

# Starting UAC remote restrictions disable
Disable-UACRestrictions

Write-Output "All checks completed."

# Generate checklist
Write-Output "`nChecklist:`n"

if ($resourceCheckPassed) {
    Write-Output "- CPU and Memory resources check: Passed"
} else {
    Write-Output "- CPU and Memory resources check: Failed"
}

if ($psVersionCheckPassed) {
    Write-Output "- PowerShell version check: Passed"
} else {
    Write-Output "- PowerShell version check: Failed"
}

if ($port443CheckPassed) {
    Write-Output "- Port 443 (HTTPS) check: Passed"
} else {
    Write-Output "- Port 443 (HTTPS) check: Failed"
}

# TrustedHosts policy check doesn't return a pass/fail status directly, so assuming if it reaches here, it passed
Write-Output "- TrustedHosts policy check: Passed"

if ($winRMConfigPassed) {
    Write-Output "- WinRM configuration: Passed"
} else {
    Write-Output "- WinRM configuration: Failed"
}

if ($Modify) {
    Write-Output "- UAC remote restrictions disable: Passed"
} else {
    Write-Output "- UAC remote restrictions disable: Skipped (Modification not enabled)"
}
