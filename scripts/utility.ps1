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
    Paths = @{
        Type = "hashtable"
        Default = @{
            TreeFile = ".\data\tree.json"
            BackupFile = ".\data\tree.backup.json"
            DefaultTree = ".\data\default.tree.json"
            ImagesDir = ".\data\images"
            TextsDir = ".\data\texts"
        }
        Validate = { param($value) $value -is [hashtable] }
        Description = "System paths configuration"
    }
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
    TextModel = @{
        Type = "hashtable"
        Default = @{
            Path = ".\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf"
            BinaryPath = ".\data\llama-box.exe"
            DefaultContextSize = 24576
            MinContextSize = 8192
            MaxContextSize = 131072
            DefaultBatchSize = 4096
            MinBatchSize = 1024
            MaxBatchSize = 5120
            Temperature = 0.8
            TopK = 40
            TopP = 0.9
            RepeatPenalty = 1.1
            MaxTokens = -1
            MaxChars = 2400
            ChatTemplate = "llama2"
            NumThreads = -1
        }
        Validate = { param($value) $value -is [hashtable] }
        Description = "Text model configuration"
    }
    ImageModel = @{
        Type = "hashtable"
        Default = @{
            Path = ".\models\FluxFusionV2-Q6_K.gguf"
            DefaultSizes = @{
                Scene = @(200, 200)
                Person = @(100, 200)
                Item = @(100, 100)
            }
        }
        Validate = { param($value) $value -is [hashtable] }
        Description = "Image model configuration"
    }
    GPU = @{
        Type = "hashtable"
        Default = @{
            MainGPU = 0
            SplitMode = "layer"
            DeviceList = @()
            CacheTypeK = "f16"
            CacheTypeV = "f16"
            DefragThreshold = 0.1
        }
        Validate = { param($value) $value -is [hashtable] }
        Description = "GPU configuration settings"
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
    if (-not $script:SettingsCache) {
        $settingsPath = ".\data\persistent.psd1"
        try {
            if (Test-Path $settingsPath) {
                $settings = Import-PowerShellDataFile $settingsPath
            }
            else {
                $settings = @{}
            }
            
            # Validate and apply defaults
            foreach ($key in $script:SettingsSchema.Keys) {
                if (-not $settings.ContainsKey($key) -or 
                    -not (& $script:SettingsSchema[$key].Validate $settings[$key])) {
                    $settings[$key] = $script:SettingsSchema[$key].Default
                }
            }
            $script:SettingsCache = $settings
        }
        catch {
            Write-Error "Settings load failed: $_"
            $script:SettingsCache = @{}
            foreach ($key in $script:SettingsSchema.Keys) {
                $script:SettingsCache[$key] = $script:SettingsSchema[$key].Default
            }
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
        Export-PowerShellData1 -Data $currentSettings -Path $settingsPath
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

function Convert-TreeNodeToViewModel {
    param([hashtable]$Node)
    return @{
        Id = $Node.Id
        Title = $Node.Title
        HasContent = (-not [string]::IsNullOrEmpty($Node.TextHash))
        Children = @()
    }
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
            $OutputPath = Join-Path $settings.Paths.ImagesDir "$hash.$($settings.ImageFormat)"
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