# Core utilities and settings management
# utility.ps1

using namespace System.Security.Cryptography
using namespace System.IO

# Import required modules
Add-Type -AssemblyName System.Drawing

# Settings Management
$script:SettingsCache = $null
$script:SettingsSchema = @{
    # System Settings
    AutoBackup = @{
        Type = "bool"
        Default = $true
        Validate = { param($value) $value -is [bool] }
        Description = "Enable automatic backup of tree files"
    }
    BackupInterval = @{
        Type = "int"
        Default = 300
        Validate = { param($value) $value -is [int] -and $value -ge 60 -and $value -le 3600 }
        Description = "Backup interval in seconds (60-3600)"
    }
    
    # UI Settings
    Theme = @{
        Type = "string"
        Default = "Light"
        Validate = { param($value) $value -in @("Light", "Dark") }
        Description = "UI theme (Light/Dark)"
    }
    Language = @{
        Type = "string"
        Default = "English"
        Validate = { param($value) $value -in @("English", "Spanish", "French", "German") }
        Description = "Interface language"
    }
    
    # File Settings
    ImageFormat = @{
        Type = "string"
        Default = "jpg"
        Validate = { param($value) $value -in @("jpg", "png") }
        Description = "Default image format for saving"
    }
    HashLength = @{
        Type = "int"
        Default = 8
        Validate = { param($value) $value -in @(8, 16, 32) }
        Description = "Length of hash for file names"
    }
    
    # Image Settings
    MaxImageSize = @{
        Type = "int"
        Default = 1920
        Validate = { param($value) $value -in @(1280, 1920, 2560, 3840) }
        Description = "Maximum image dimension in pixels"
    }
    ImageQuality = @{
        Type = "int"
        Default = 95
        Validate = { param($value) $value -ge 70 -and $value -le 100 }
        Description = "JPEG quality (70-100)"
    }
    
    # Model Settings
    MaxContextSize = @{
        Type = "int"
        Default = 32768
        Validate = { param($value) $value -in @(8192, 16384, 32768, 65536, 131072) }
        Description = "Maximum context size for AI models"
    }
    MaxBatchSize = @{
        Type = "int"
        Default = 2048
        Validate = { param($value) $value -in @(2048, 4096) }
        Description = "Maximum batch size for AI models"
    }
    
    # Auto-save Settings
    AutoSaveInterval = @{
        Type = "int"
        Default = 300
        Validate = { param($value) $value -ge 60 -and $value -le 3600 }
        Description = "Auto-save interval in seconds (60-3600)"
    }
    MaxUndoStates = @{
        Type = "int"
        Default = 50
        Validate = { param($value) $value -ge 10 -and $value -le 100 }
        Description = "Maximum number of undo states (10-100)"
    }
}

# Settings Functions
function Get-Settings {
    if ($null -eq $script:SettingsCache) {
        $settingsPath = ".\data\persistent.psd1"
        try {
            if (Test-Path $settingsPath) {
                $settings = Import-PowerShellDataFile $settingsPath
                # Validate and apply defaults for missing settings
                foreach ($key in $script:SettingsSchema.Keys) {
                    if (-not $settings.ContainsKey($key)) {
                        $settings[$key] = $script:SettingsSchema[$key].Default
                    }
                    elseif (-not (& $script:SettingsSchema[$key].Validate $settings[$key])) {
                        Write-Warning "Invalid setting for $key, using default"
                        $settings[$key] = $script:SettingsSchema[$key].Default
                    }
                }
            }
            else {
                # Create default settings
                $settings = @{}
                foreach ($key in $script:SettingsSchema.Keys) {
                    $settings[$key] = $script:SettingsSchema[$key].Default
                }
            }
            $script:SettingsCache = $settings
        }
        catch {
            Write-Error "Failed to load settings: $_"
            # Return defaults if loading fails
            $settings = @{}
            foreach ($key in $script:SettingsSchema.Keys) {
                $settings[$key] = $script:SettingsSchema[$key].Default
            }
            $script:SettingsCache = $settings
        }
    }
    return $script:SettingsCache
}

function Set-Settings {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )
    
    $currentSettings = Get-Settings
    $settingsPath = ".\data\persistent.psd1"
    $backupPath = ".\data\persistent.psd1.bak"
    
    try {
        # Validate new settings
        foreach ($key in $Settings.Keys) {
            if (-not $script:SettingsSchema.ContainsKey($key)) {
                throw "Invalid setting key: $key"
            }
            if (-not (& $script:SettingsSchema[$key].Validate $Settings[$key])) {
                throw "Invalid value for setting $key"
            }
        }
        
        # Backup current settings
        if (Test-Path $settingsPath) {
            Copy-Item $settingsPath $backupPath -Force
        }
        
        # Update settings
        foreach ($key in $Settings.Keys) {
            $currentSettings[$key] = $Settings[$key]
        }
        
        # Save to file
        $content = "@{`n"
        foreach ($key in $currentSettings.Keys | Sort-Object) {
            $value = $currentSettings[$key]
            if ($value -is [string]) {
                $value = "'$value'"
            }
            elseif ($value -is [bool]) {
                $value = if ($value) { '$true' } else { '$false' }
            }
            $content += "    $key = $value`n"
        }
        $content += "}"
        
        Set-Content -Path $settingsPath -Value $content -Force
        $script:SettingsCache = $currentSettings
        
        # Remove backup if successful
        if (Test-Path $backupPath) {
            Remove-Item $backupPath
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to save settings: $_"
        # Restore from backup
        if (Test-Path $backupPath) {
            Copy-Item $backupPath $settingsPath -Force
            Remove-Item $backupPath
        }
        return $false
    }
}

function Reset-Settings {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Keys
    )
    
    $currentSettings = Get-Settings
    $defaults = @{}
    
    if ($Keys) {
        foreach ($key in $Keys) {
            if ($script:SettingsSchema.ContainsKey($key)) {
                $defaults[$key] = $script:SettingsSchema[$key].Default
            }
        }
    }
    else {
        foreach ($key in $script:SettingsSchema.Keys) {
            $defaults[$key] = $script:SettingsSchema[$key].Default
        }
    }
    
    return (Set-Settings -Settings $defaults)
}

function Get-SettingsSchema {
    return $script:SettingsSchema
}

# File Operations
function Get-RandomHash {
    param([int]$Length = (Get-Settings).HashLength)
    $bytes = [byte[]]::new([Math]::Ceiling($Length / 2))
    $rng = [RNGCryptoServiceProvider]::new()
    $rng.GetBytes($bytes)
    return ([Convert]::ToHexString($bytes)).ToLower().Substring(0, $Length)
}

function Test-FileHash {
    param(
        [string]$FilePath,
        [string]$ExpectedHash
    )
    $actualHash = Get-FileHash -Path $FilePath -Algorithm SHA256
    return $actualHash.Hash.Substring(0, (Get-Settings).HashLength).ToLower() -eq $ExpectedHash.ToLower()
}

# Image Processing
function Optimize-Image {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [string]$OutputPath,
        [int]$MaxWidth = $null,
        [int]$Quality = $null
    )
    
    try {
        # Get settings
        $settings = Get-Settings
        $maxWidth = $MaxWidth ?? $settings.MaxImageSize
        $quality = $Quality ?? $settings.ImageQuality
        
        # Ensure ImageMagick is in path
        $magickPath = ".\data\ImageMagick\magick.exe"
        if (-not (Test-Path $magickPath)) {
            throw "ImageMagick not found"
        }

        # Generate output path if not provided
        if (-not $OutputPath) {
            $hash = Get-RandomHash
            $OutputPath = Join-Path $global:PATHS.ImagesDir "$hash.$($settings.ImageFormat)"
        }

        # Process image
        $args = @(
            $InputPath,
            "-auto-orient",
            "-resize", "${maxWidth}x${maxWidth}>",
            "-quality", "$quality",
            "-strip",
            $OutputPath
        )

        $process = Start-Process -FilePath $magickPath -ArgumentList $args -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) {
            throw "Image processing failed"
        }

        return [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
    }
    catch {
        Write-Error "Failed to optimize image: $_"
        return $null
    }
}

# Data Import/Export
function Import-PowerShellData1 {
    param([string]$Path)
    $content = Get-Content -Path $Path -Raw
    $content = $content -replace '^(#.*[\r\n]*)+', ''
    $content = $content -replace '\bTrue\b', '$true' -replace '\bFalse\b', '$false'
    $scriptBlock = [scriptblock]::Create($content)
    return . $scriptBlock
}

function Export-PowerShellData1 {
    param(
        [hashtable]$Data,
        [string]$Path
    )
    $content = "@{`n"
    foreach ($key in $Data.Keys | Sort-Object) {
        $value = $Data[$key]
        $content += "    $key = $(ConvertTo-Psd1String $value)`n"
    }
    $content += "}"
    Set-Content -Path $Path -Value $content
}

# Helper Functions
function ConvertTo-Psd1String {
    param($Value)
    if ($Value -is [string]) {
        return "'$Value'"
    }
    elseif ($Value -is [bool]) {
        return if ($Value) { '$true' } else { '$false' }
    }
    elseif ($Value -is [array] -or $Value -is [System.Collections.ArrayList]) {
        return "@(" + ($Value -join ",") + ")"
    }
    elseif ($Value -is [hashtable]) {
        return "@{" + (($Value.GetEnumerator() | ForEach-Object { "$($_.Key)=$(ConvertTo-Psd1String $_.Value)" }) -join ";") + "}"
    }
    else {
        return $Value
    }
}

# Export functions
Export-ModuleMember -Function *