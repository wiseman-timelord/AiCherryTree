# .\scripts\launcher.ps1

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import required modules
Import-Module "$PSScriptRoot\scripts\utility.ps1"
Import-Module "$PSScriptRoot\scripts\model.ps1"
Import-Module "$PSScriptRoot\scripts\interface.ps1"
Import-Module "$PSScriptRoot\scripts\texts.ps1"
Import-Module "$PSScriptRoot\scripts\images.ps1"
Import-Module "$PSScriptRoot\scripts\internet.ps1"
Import-Module "$PSScriptRoot\scripts\prompts.ps1"

# Initialize settings and paths
$settings = Get-Settings
$global:PATHS = $settings.Paths

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
    try {
        # Check required paths
        if (-not (Test-Path ".\data\ImageMagick\magick.exe")) {
            throw "ImageMagick not found. Please run installer first."
        }

        if (-not (Test-Path ".\data\clblast.dll")) {
            throw "CLBlast library not found. Please run installer first."
        }

        # Check model paths
        $settings = Get-Settings
        $textModelPath = Join-Path $PSScriptRoot "models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf"
        $imageModelPath = Join-Path $PSScriptRoot "models\FluxFusionV2-Q6_K.gguf"
        
        if (-not (Test-Path $textModelPath)) {
            throw "Text model not found: $textModelPath"
        }
        if (-not (Test-Path $imageModelPath)) {
            throw "Image model not found: $imageModelPath"
        }

        # Check directories exist
        foreach ($path in $settings.Paths.Values) {
            $dir = Split-Path $path
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force
            }
        }

        return $true
    }
    catch {
        Write-StatusMessage $_.Exception.Message "Error"
        return $false
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
    if ((Test-Path $global:PATHS.TreeFile) -and (Test-TreeFileIntegrity $global:PATHS.TreeFile)) {
        Copy-Item $global:PATHS.TreeFile $global:PATHS.BackupFile -Force
        Write-StatusMessage "Tree file loaded and backed up" "Success"
        return $true
    }
    
    if (Test-Path $global:PATHS.BackupFile) {
        Copy-Item $global:PATHS.BackupFile $global:PATHS.TreeFile -Force
        Write-StatusMessage "Recovered from backup file" "Success"
        return $true
    }
    
    if (Test-Path $global:PATHS.DefaultTree) {
        Copy-Item $global:PATHS.DefaultTree $global:PATHS.TreeFile -Force
        Write-StatusMessage "Created new tree from template" "Success"
        return $true
    }
    
    Write-StatusMessage "Tree initialization failed" "Error"
    return $false
}

function Initialize-Configuration {
    try {
        # Create required directories
        'temp', 'data', 'models', 'foliage' | ForEach-Object {
            if (-not (Test-Path ".\$_")) {
                New-Item -ItemType Directory -Path ".\$_" -Force
            }
        }

        # Initialize global state
        $global:TempVars = @{
            IsInitialized = $true
            LastBackup = Get-Date
            CurrentNode = $null
        }
        
        # Load and return settings
        $settings = Get-Settings
        
        # Create required directories if they don't exist
        foreach ($path in $settings.Paths.Values) {
            $dir = Split-Path $path
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }
        
        return $settings
    }
    catch {
        Write-StatusMessage "Configuration initialization failed: $_" "Error"
        throw
    }
}

function Initialize-AIEnvironment {
    try {
        Write-StatusMessage "Initializing AI environment..." "Info"

        # Initialize GPU environment first
        if (-not (Initialize-GPUEnvironment)) {
            Write-StatusMessage "GPU initialization failed, falling back to CPU" "Warning"
        }

        # Initialize models
        if (-not (Initialize-Models)) {
            throw "Failed to initialize AI models"
        }

        # Verify model health
        $textHealth = Test-ModelHealth -ModelType "Text"
        $imageHealth = Test-ModelHealth -ModelType "Image"

        if (-not ($textHealth -and $imageHealth)) {
            throw "Model health check failed"
        }

        Write-StatusMessage "AI environment initialized successfully" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to initialize AI environment: $_" "Error"
        return $false
    }
}

function Start-LightStone {
    Write-StatusMessage "Starting LightStone..." "Info"
    
    try {
        # Run initialization checks
        if (-not (Test-Prerequisites)) {
            throw "Prerequisites check failed"
        }
        
        # Initialize components
        if (-not (Initialize-TreeFile)) {
            throw "Failed to initialize tree file"
        }
        
        $config = Initialize-Configuration
        
        # Initialize AI environment
        if (-not (Initialize-AIEnvironment)) {
            throw "Failed to initialize AI environment"
        }
        
        # Clean temp directory
        if (Test-Path ".\temp") {
            Get-ChildItem ".\temp" | Remove-Item -Force -Recurse
        }
        
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