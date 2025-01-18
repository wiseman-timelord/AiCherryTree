# Image generation module
# images.ps1

# Configuration defaults
$global:ImageModelConfig = @{
    Path = ".\models\FluxFusionV2-Q6_K.gguf"
    BinaryPath = ".\data\llama-box.exe"
    Steps = 4
    Temperature = 0.7
    CFGScale = 7.0
    RepeatPenalty = 1.1
    NumThreads = -1
}

# Image size presets with aspect ratios
$global:ImageSizePresets = @{
    Scene = @{
        Width = 200
        Height = 200
        Description = "Full scene or landscape"
    }
    Person = @{
        Width = 100
        Height = 200
        Description = "Character or portrait"
    }
    Item = @{
        Width = 100
        Height = 100
        Description = "Object or item"
    }
}

# GPU configuration (shared with text model)
$global:ImageGPUConfig = @{
    MainGPU = 0
    SplitMode = "layer"
    CacheTypeK = "f16"
    CacheTypeV = "f16"
    DefragThreshold = 0.1
}

function Initialize-ImageModel {
    param([switch]$ForceReload)
    
    try {
        Write-StatusMessage "Initializing image model..." "Info"
        
        # Check binary and model existence
        if (-not (Test-Path $global:ImageModelConfig.BinaryPath)) {
            throw "llama-box binary not found"
        }
        if (-not (Test-Path $global:ImageModelConfig.Path)) {
            throw "Image model not found"
        }
        
        # Test model with minimal generation
        $testArgs = @(
            "--model", $global:ImageModelConfig.Path,
            "--threads", "1",
            "--help"
        )
        
        $testProcess = Start-Process -FilePath $global:ImageModelConfig.BinaryPath `
                                   -ArgumentList $testArgs `
                                   -Wait -PassThru -NoNewWindow
        
        if ($testProcess.ExitCode -ne 0) {
            throw "Image model test failed"
        }

        $global:TempVars.ImageModelLoaded = $true
        Write-StatusMessage "Image model initialized successfully" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to initialize image model: $_" "Error"
        $global:TempVars.ImageModelLoaded = $false
        return $false
    }
}

function Get-ContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    
    # Create analysis prompt
    $prompt = @"
Analyze the following description and classify it as one of these types:
- Scene: Full environment, landscape, or location
- Person: Character, portrait, or figure
- Item: Single object, item, or detail

Description: $Description

Respond with only one word: Scene, Person, or Item.
"@
    
    # Use text model to classify
    $result = Send-TextPrompt -Prompt $prompt -Options @{
        Temperature = 0.1  # Low temperature for consistent results
        MaxTokens = 10    # Only need a single word
    }
    
    # Clean and validate response
    $type = $result.Trim()
    if ($type -in @("Scene", "Person", "Item")) {
        return $type
    }
    
    # Default to Scene if unclear
    return "Scene"
}

function New-AIImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$OutputPath,
        [string]$ContentType = "Scene",
        [hashtable]$Options = @{},
        [switch]$AllowWebImages
    )
    
    try {
        # Check if we should use web image
        if ($AllowWebImages) {
            $needsWebImage = Test-NeedsWebImage -Prompt $Prompt
            
            if ($needsWebImage) {
                return Get-WebImage -Query $Prompt -OutputPath $OutputPath
            }
        }
        
        # Get size preset
        $sizePreset = $global:ImageSizePresets[$ContentType]
        if (-not $sizePreset) {
            throw "Invalid content type: $ContentType"
        }
        
        # Generate output path if not provided
        if (-not $OutputPath) {
            $hash = Get-RandomHash
            $OutputPath = Join-Path $global:PATHS.ImagesDir "$hash.png"
        }
        
        # Build arguments
        $args = @(
            "--model", $global:ImageModelConfig.Path,
            "--steps", $global:ImageModelConfig.Steps,
            "--temp", $global:ImageModelConfig.Temperature,
            "--threads", $global:ImageModelConfig.NumThreads,
            "--width", $sizePreset.Width,
            "--height", $sizePreset.Height,
            "--repeat-penalty", $global:ImageModelConfig.RepeatPenalty,
            "--device", $global:ImageGPUConfig.MainGPU,
            "--split-mode", $