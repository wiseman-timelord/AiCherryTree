# Image generation module
# images.ps1

# Configuration defaults
$settings = Get-Settings
$global:ImageModelConfig = $settings.ImageModel
$global:GPUConfig = $settings.GPU

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

# Add image generation function
function New-AIImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$Type = "Scene",
        [string]$OutputPath = $null,
        [hashtable]$Options = @{}
    )
    
    try {
        # Validate type
        if (-not $global:ImageModelConfig.DefaultSize.ContainsKey($Type)) {
            throw "Invalid image type: $Type. Must be Scene, Person, or Item."
        }
        
        # Generate output path if not provided
        if (-not $OutputPath) {
            $hash = Get-RandomHash
            $OutputPath = Join-Path $global:PATHS.ImagesDir "$hash.png"
        }
        
        # Get size configuration
        $size = $global:ImageModelConfig.DefaultSize[$Type]
        
        # Build arguments
        $args = @(
            "--model", $global:ImageModelConfig.Path,
            "--width", $size.Width,
            "--height", $size.Height,
            "--steps", $global:ImageModelConfig.Steps,
            "--temp", $global:ImageModelConfig.Temperature,
            "--cfg-scale", $global:ImageModelConfig.CFGScale,
            "--prompt", $Prompt,
            "--output", $OutputPath
        )
        
        # Add custom options
        foreach ($key in $Options.Keys) {
            $args += "--$($key.ToLower())", $Options[$key]
        }
        
        # Generate image
        $process = Start-Process -FilePath $global:ImageModelConfig.BinaryPath `
            -ArgumentList $args -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -ne 0) {
            throw "Image generation failed with exit code: $($process.ExitCode)"
        }
        
        # Optimize generated image
        $optimizedPath = Optimize-Image -InputPath $OutputPath
        
        return $optimizedPath
    }
    catch {
        Write-Error "Failed to generate image: $_"
        return $null
    }
}