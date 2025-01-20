# Image generation module
# .\scripts\images.ps1

# Import required modules
Import-Module "$PSScriptRoot\utility.ps1"
Import-Module "$PSScriptRoot\model.ps1"
Import-Module "$PSScriptRoot\prompts.ps1"

function Get-ContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    
    # Create analysis prompt using prompts.ps1
    $prompt = New-ContentPrompt -Type "ImageGeneration" -Title "Content Type Analysis" -Context $Description `
        -Parameters @{
            Instructions = "Analyze this description and classify it as Scene, Person, or Item. Respond with only one word."
        }
    
    # Use text model to classify
    $result = Send-TextPrompt -Prompt $prompt -Options @{
        Temperature = 0.1
        MaxTokens = 10
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
        [string]$Type = "Scene",
        [string]$OutputPath = $null,
        [hashtable]$Options = @{}
    )
    
    try {
        # Check model health through model.ps1
        if (-not (Test-ModelHealth -ModelType "Image")) {
            throw "Image model not initialized or unhealthy"
        }
        
        # Generate output path if not provided
        if (-not $OutputPath) {
            $hash = Get-RandomHash
            $OutputPath = Join-Path $global:PATHS.ImagesDir "$hash.jpg"
        }
        
        # Prepare prompts and parameters
        $enhancedPrompt = New-ContentPrompt -Type "ImageGeneration" -Title $Type `
            -Context $Prompt -Parameters @{
                Style = "Detailed, high quality"
                Format = "Specific to $Type type"
            }
        
        # Get model config from global state
        $modelConfig = $global:ModelState.ImageModel.Config
        
        # Let model.ps1 handle the generation
        $result = New-AIImage -Prompt $enhancedPrompt -Type $Type -OutputPath $OutputPath `
            -Options $Options
        
        if (-not $result) {
            throw "Image generation failed"
        }
        
        # Optimize the generated image
        return Optimize-Image -InputPath $result
    }
    catch {
        Write-Error "Failed to generate image: $_"
        return $null
    }
}

function Optimize-Image {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [string]$OutputPath = $null,
        [int]$MaxSize = 1024,
        [int]$Quality = 85
    )
    
    try {
        # Get ImageMagick path
        $magick = Join-Path $PSScriptRoot "..\data\ImageMagick\magick.exe"
        if (-not (Test-Path $magick)) {
            throw "ImageMagick not found"
        }
        
        # Generate output path if not provided
        if (-not $OutputPath) {
            $extension = [System.IO.Path]::GetExtension($InputPath)
            $hash = Get-RandomHash
            $OutputPath = Join-Path $global:PATHS.ImagesDir "$hash$extension"
        }
        
        # Build optimization arguments
        $args = @(
            $InputPath,
            "-resize", "${MaxSize}x${MaxSize}>",  # Only shrink if larger
            "-quality", $Quality,
            "-strip",                             # Remove metadata
            "-interlace", "Plane",               # Progressive JPG
            "-auto-orient",                      # Fix orientation
            $OutputPath
        )
        
        # Run ImageMagick
        $process = Start-Process -FilePath $magick -ArgumentList $args `
            -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -ne 0) {
            throw "ImageMagick optimization failed"
        }
        
        return $OutputPath
    }
    catch {
        Write-Error "Failed to optimize image: $_"
        return $null
    }
}

function Get-ImageMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )
    
    try {
        # Check if file exists
        if (-not (Test-Path $ImagePath)) {
            throw "Image file not found"
        }
        
        # Get basic file info
        $fileInfo = Get-Item $ImagePath
        
        # Use ImageMagick to get detailed info
        $magick = Join-Path $PSScriptRoot "..\data\ImageMagick\magick.exe"
        $args = @(
            "identify",
            "-format", "%w|%h|%m|%Q|%[size]",
            $ImagePath
        )
        
        $result = & $magick $args
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get image metadata"
        }
        
        # Parse the result
        $parts = $result -split '\|'
        if ($parts.Count -ge 5) {
            return @{
                Path = $ImagePath
                Width = [int]$parts[0]
                Height = [int]$parts[1]
                Format = $parts[2]
                Quality = if ($parts[3] -eq '') { $null } else { [int]$parts[3] }
                Size = $parts[4]
                Created = $fileInfo.CreationTime
                Modified = $fileInfo.LastWriteTime
            }
        }
        
        throw "Invalid metadata format"
    }
    catch {
        Write-Error "Failed to get image metadata: $_"
        return $null
    }
}

# Export functions
Export-ModuleMember -Function *