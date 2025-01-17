# .\installer.ps1

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Global Variables
$global:ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:RequiredModules = @(
    "Microsoft.PowerShell.Management",
    "Microsoft.PowerShell.Utility"
)
$global:Directories = @(
    ".\data",
    ".\data\ImageMagick",
    ".\foliage",
    ".\foliage\images",
    ".\foliage\texts",
    ".\temp",
    ".\scripts"
)
$global:DefaultFiles = @{
    ".\data\defaul.ls0" = @"
{
    "version": "1.0",
    "created": "$(Get-Date -Format "yyyy-MM-dd")",
    "root": {
        "id": "root",
        "name": "Root",
        "children": [],
        "content": "Welcome to LightStone!\n\nThis is your first document tree. Here are some key features:\n..."
    }
}
"@
    ".\data\backup.ls0" = "{}"
    ".\data\persistent.psd1" = @"
@{
    Version = '1.0'
    LastModified = '$(Get-Date -Format "yyyy-MM-dd")'
    Settings = @{
        AutoBackup = `$true
        BackupInterval = 300
        Theme = 'Light'
        Language = 'English'
        ImageFormat = 'jpg'
        HashLength = 8
    }
}
"@
    ".\data\temporary.ps1" = @"
# LightStone Global Variables
`$global:TempVars = @{
    LastBackup = `$(Get-Date)
    SessionID = `$(New-Guid)
    IsInitialized = `$false
    CurrentNode = $null
    LoadedTree = $null
    ModelLoaded = `$false
    ImageCache = @{}
}

# Constants
`$global:CONSTANTS = @{
    HashLength = 8
    MaxImageSize = 1920
    ImageQuality = 95
    AutoSaveInterval = 300
    MaxUndoStates = 50
}

# File paths
`$global:PATHS = @{
    TreeFile = ".\foliage\tree.ls0"
    BackupFile = ".\data\backup.ls0"
    DefaultTree = ".\data\defaul.ls0"
    ImagesDir = ".\foliage\images"
    TextsDir = ".\foliage\texts"
    TempDir = ".\temp"
}
"@
}

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
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "PowerShell 7 or higher is required"
    }

    # Check admin privileges
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Administrator privileges required"
    }
}

function Initialize-Environment {
    # Create directories
    foreach ($dir in $global:Directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-StatusMessage "Created directory: $dir" "Success"
        }
    }

    # Create default files
    foreach ($file in $global:DefaultFiles.Keys) {
        if (-not (Test-Path $file)) {
            Set-Content -Path $file -Value $global:DefaultFiles[$file] -Force
            Write-StatusMessage "Created file: $file" "Success"
        }
    }
}

function Install-RequiredSoftware {
    # Install ImageMagick if not present
    if (-not (Test-Path ".\data\ImageMagick\magick.exe")) {
        Write-StatusMessage "Installing ImageMagick..." "Info"
        $url = "https://imagemagick.org/archive/binaries/ImageMagick-7.1.1-21-Q16-HDRI-x64-dll.exe"
        $outFile = ".\temp\imagemagick-installer.exe"
        
        try {
            Invoke-WebRequest -Uri $url -OutFile $outFile
            Start-Process -FilePath $outFile -ArgumentList "/DIR=`"$((Get-Location).Path)\data\ImageMagick`" /SILENT" -Wait
            Write-StatusMessage "ImageMagick installed successfully" "Success"
        }
        catch {
            Write-StatusMessage "Failed to install ImageMagick: $_" "Error"
            throw
        }
        finally {
            if (Test-Path $outFile) { Remove-Item $outFile }
        }
    }

    # Download and extract Llama model
    $llamaDir = ".\data\cudart-llama-bin-win-cu11.7"
    if (-not (Test-Path $llamaDir)) {
        Write-StatusMessage "Downloading Llama.cpp binary..." "Info"
        $url = "https://github.com/ggerganov/llama.cpp/releases/download/master/cudart-llama-bin-win-cu11.7-x64.zip"
        $outFile = ".\temp\llama.zip"
        
        try {
            Invoke-WebRequest -Uri $url -OutFile $outFile
            Expand-Archive -Path $outFile -DestinationPath $llamaDir -Force
            Write-StatusMessage "Llama.cpp binary installed successfully" "Success"
        }
        catch {
            Write-StatusMessage "Failed to install Llama.cpp binary: $_" "Error"
            throw
        }
        finally {
            if (Test-Path $outFile) { Remove-Item $outFile }
        }
    }
}

function Start-Installation {
    Write-StatusMessage "Starting LightStone installation..." "Info"
    
    try {
        Test-Prerequisites
        Initialize-Environment
        Install-RequiredSoftware
        
        Write-StatusMessage "Installation completed successfully!" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Installation failed: $_" "Error"
        return $false
    }
}

# Main execution
if (Start-Installation) {
    exit 0
} else {
    exit 1
}