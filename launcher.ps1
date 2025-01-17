# .\launcher.ps1

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load global variables and paths
. ".\data\temporary.ps1"

# Import required modules
Import-Module "$PSScriptRoot\scripts\utility.ps1"
Import-Module "$PSScriptRoot\scripts\interface.ps1"
Import-Module "$PSScriptRoot\scripts\model.ps1"
Import-Module "$PSScriptRoot\scripts\internet.ps1"

# Functions
function Write-StatusMessage {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    $color = switch ($Type) {
        "Info" { "White" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
    }
    Write-Host "[$Type] $Message" -ForegroundColor $color
}

function Test-Prerequisites {
    # Check if ImageMagick is installed
    if (-not (Test-Path ".\data\ImageMagick\magick.exe")) {
        throw "ImageMagick not found. Please run installer first."
    }

    # Check if Llama binary exists
    if (-not (Test-Path ".\data\cudart-llama-bin-win-cu11.7")) {
        throw "Llama binary not found. Please run installer first."
    }

    # Check for required files
    foreach ($path in $global:PATHS.Values) {
        if (-not (Test-Path (Split-Path $path))) {
            throw "Required directory missing: $path"
        }
    }
}

function Test-TreeFileIntegrity {
    param (
        [string]$FilePath
    )
    try {
        $content = Get-Content $FilePath -Raw -ErrorAction Stop
        $json = $content | ConvertFrom-Json
        
        # Basic validation
        if (-not $json.version -or -not $json.root) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Initialize-TreeFile {
    if (Test-Path $global:PATHS.TreeFile) {
        if (Test-TreeFileIntegrity -FilePath $global:PATHS.TreeFile) {
            # Backup working tree file
            Copy-Item $global:PATHS.TreeFile $global:PATHS.BackupFile -Force
            Write-StatusMessage "Tree file loaded and backed up" "Success"
            return $true
        }
        else {
            Write-StatusMessage "Tree file corrupted, attempting recovery..." "Warning"
            if (Test-Path $global:PATHS.BackupFile) {
                Copy-Item $global:PATHS.BackupFile $global:PATHS.TreeFile -Force
                Write-StatusMessage "Recovered from backup file" "Success"
                return $true
            }
        }
    }
    
    # If no valid tree or backup exists, create from default
    if (Test-Path $global:PATHS.DefaultTree) {
        Copy-Item $global:PATHS.DefaultTree $global:PATHS.TreeFile -Force
        Write-StatusMessage "Created new tree file from default template" "Success"
        return $true
    }
    
    Write-StatusMessage "Unable to initialize tree file" "Error"
    return $false
}

function Initialize-Configuration {
    try {
        # Load configuration
        $config = Import-PowerShellData1 -Path ".\data\persistent.psd1"
        
        # Set environment variables
        $env:LLAMA_CUDA_UNIFIED_MEMORY = 1
        $env:PATH = ".\data\ImageMagick;" + $env:PATH
        
        # Update global settings
        $global:TempVars.IsInitialized = $true
        $global:TempVars.LastBackup = Get-Date
        
        return $config
    }
    catch {
        Write-StatusMessage "Failed to initialize configuration: $_" "Error"
        throw
    }
}

function Start-LightStone {
    Write-StatusMessage "Starting LightStone..." "Info"
    
    try {
        # Run initialization checks
        Test-Prerequisites
        
        # Initialize components
        if (-not (Initialize-TreeFile)) {
            throw "Failed to initialize tree file"
        }
        
        $config = Initialize-Configuration
        Write-StatusMessage "Initializing AI model..." "Info"
        Initialize-AIModel
        
        # Clean temp directory
        Get-ChildItem ".\temp" | Remove-Item -Force -Recurse
        
        # Start interface
        Write-StatusMessage "Launching interface..." "Info"
        Start-LightStoneInterface -Config $config
        
        Write-StatusMessage "LightStone started successfully" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to start LightStone: $_" "Error"
        return $false
    }
}

# Main execution
if (Start-LightStone) {
    exit 0
} else {
    exit 1
}