# Image generation and processing module
# .\scripts\images.ps1

# Import required modules
Import-Module "$PSScriptRoot\utility.ps1"
Import-Module "$PSScriptRoot\model.ps1"
Import-Module "$PSScriptRoot\prompts.ps1"

# Image Type Configuration
$global:ImageConfig = @{
    Sizes = @{
        Scene = @(200, 200)
        Person = @(100, 200)
        Item = @(100, 100)
    }
    Quality = @{
        Default = 85
        Minimum = 70
        Maximum = 100
    }
    Cache = @{
        Enabled = $true
        MaxAge = [TimeSpan]::FromHours(24)
        MaxSize = 100MB
    }
}

# Configuration
$global:ImageTypes = @{
    Scene = @{
        Width = 200
        Height = 200
        Prompt = "A complete scene with background and environment"
    }
    Person = @{
        Width = 100
        Height = 200
        Prompt = "A full-body character portrait"
    }
    Item = @{
        Width = 100
        Height = 100
        Prompt = "A centered object or item"
    }
}

# Image Generation Pipeline
class ImageGenerationPipeline {
    [string]$BasePrompt
    [string]$Type
    [hashtable]$Options
    [string]$OutputPath
    [object]$ProgressCallback

    ImageGenerationPipeline([string]$prompt, [string]$type, [hashtable]$options, [string]$outputPath) {
        $this.BasePrompt = $prompt
        $this.Type = $type
        $this.Options = $options
        $this.OutputPath = $outputPath
    }

    [void]SetProgressCallback([object]$callback) {
        $this.ProgressCallback = $callback
    }

    [hashtable]Process() {
        try {
            # Report progress
            $this.ReportProgress(0, "Starting image generation")

            # Step 1: Validate and enhance prompt
            $this.ReportProgress(10, "Analyzing prompt")
            $enhancedPrompt = $this.EnhancePrompt()

            # Step 2: Generate base image
            $this.ReportProgress(20, "Generating base image")
            $baseImage = $this.GenerateImage($enhancedPrompt)
            if (-not $baseImage) {
                throw "Image generation failed"
            }

            # Step 3: Post-process image
            $this.ReportProgress(60, "Post-processing image")
            $processedImage = $this.PostProcessImage($baseImage)

            # Step 4: Validate result
            $this.ReportProgress(80, "Validating image")
            if (-not (Test-GeneratedImage -Path $processedImage)) {
                throw "Image validation failed"
            }

            # Step 5: Finalize
            $this.ReportProgress(90, "Finalizing image")
            $finalPath = $this.FinalizeImage($processedImage)

            $this.ReportProgress(100, "Image generation complete")

            return @{
                Success = $true
                Path = $finalPath
                Prompt = $enhancedPrompt
                Type = $this.Type
                Metadata = Get-ImageMetadata -Path $finalPath
            }
        }
        catch {
            Write-Error "Image generation pipeline failed: $_"
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }

    hidden [string]EnhancePrompt() {
        $typePrompt = $global:ImageTypes[$this.Type].Prompt
        $enhancedPrompt = @"
$typePrompt
Original request: $($this.BasePrompt)
Style requirements:
- High quality, detailed output
- Clear composition and focus
- Appropriate for $($this.Type.ToLower()) type image
- Size: $($global:ImageTypes[$this.Type].Width)x$($global:ImageTypes[$this.Type].Height)
"@
        return $enhancedPrompt
    }

    hidden [string]GenerateImage([string]$prompt) {
        # Get type configuration
        $typeConfig = $global:ImageTypes[$this.Type]
        
        # Setup temporary path
        $tempPath = New-TempFile -Extension ".png" -Prefix "gen_"
        
        # Configure model options
        $modelOptions = @{
            Width = $typeConfig.Width
            Height = $typeConfig.Height
            Steps = 4  # Flux specific
            Seed = -1
        }
        
        # Add custom options
        foreach ($key in $this.Options.Keys) {
            $modelOptions[$key] = $this.Options[$key]
        }
        
        # Generate through model
        $result = Invoke-GGUFModel -ModelContext $global:ModelState.ImageModel.Context `
            -Prompt $prompt -Options $modelOptions
        
        if ($result) {
            Move-Item $result $tempPath -Force
            return $tempPath
        }
        
        return $null
    }

    hidden [string]PostProcessImage([string]$imagePath) {
        # Setup paths
        $tempPath = New-TempFile -Extension ".png" -Prefix "proc_"
        
        # Get ImageMagick path
        $magick = Join-Path $PSScriptRoot "..\data\ImageMagick\magick.exe"
        
        # Basic enhancement arguments
        $args = @(
            $imagePath,
            "-quality", "95",
            "-normalize",
            "-unsharp", "0x0.75+0.75+0.008",
            "-strip",
            $tempPath
        )
        
        # Process image
        $process = Start-Process -FilePath $magick -ArgumentList $args -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) {
            throw "Post-processing failed"
        }
        
        return $tempPath
    }

    hidden [string]FinalizeImage([string]$processedPath) {
        # Copy to final location
        Copy-Item $processedPath $this.OutputPath -Force
        
        # Cleanup temporary files
        Remove-Item $processedPath -Force
        
        return $this.OutputPath
    }

    hidden [void]ReportProgress([int]$progress, [string]$status) {
        if ($this.ProgressCallback) {
            & $this.ProgressCallback $progress $status
        }
    }
}

# Image Validation
function Test-GeneratedImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        # Get image info
        $info = Get-ImageMetadata -Path $Path
        
        # Basic validation checks
        if ($info.Width -lt 50 -or $info.Height -lt 50) {
            return $false
        }
        
        # Check file size (shouldn't be too small)
        $minSize = 1KB
        if ($info.Size -lt $minSize) {
            return $false
        }
        
        # Validate format
        $validFormats = @('PNG', 'JPEG', 'JPG')
        if ($info.Format -notin $validFormats) {
            return $false
        }
        
        return $true
    }
    catch {
        Write-Error "Image validation failed: $_"
        return $false
    }
}

# Main Generation Function
function New-GeneratedImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [ValidateSet('Scene', 'Person', 'Item')]
        [string]$Type = 'Scene',
        [hashtable]$Options = @{},
        [string]$OutputPath = $null
    )
    
    try {
        # Validate model state
        if (-not (Test-ModelHealth -ModelType "Image")) {
            throw "Image model not initialized"
        }
        
        # Generate output path if not provided
        if (-not $OutputPath) {
            $hash = Get-RandomHash
            $OutputPath = Join-Path $global:PATHS.ImagesDir "$hash.png"
        }
        
        # Create pipeline
        $pipeline = [ImageGenerationPipeline]::new($Prompt, $Type, $Options, $OutputPath)
        
        # Set progress callback if UI is available
        if ($global:MainWindow.ProgressManager) {
            $taskId = $global:MainWindow.ProgressManager.StartTask("Generating image")
            $pipeline.SetProgressCallback({
                param($progress, $status)
                $global:MainWindow.ProgressManager.UpdateTask($taskId, $progress, $status)
            })
        }
        
        # Process pipeline
        $result = $pipeline.Process()
        
        # Complete progress task if used
        if ($taskId) {
            $global:MainWindow.ProgressManager.CompleteTask($taskId)
        }
        
        return $result
    }
    catch {
        Write-Error "Image generation failed: $_"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}


# Image Generation
function New-AIImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$Type = "Scene",
        [string]$OutputPath = $null,
        [hashtable]$Options = @{}
    )
    
    try {
        # Check model health
        if (-not (Test-ModelHealth -ModelType "Image")) {
            throw "Image model not initialized"
        }
        
        # Validate type and get size
        if (-not $global:ImageConfig.Sizes.ContainsKey($Type)) {
            throw "Invalid image type: $Type. Must be Scene, Person, or Item."
        }
        $size = $global:ImageConfig.Sizes[$Type]
        
        # Check cache if enabled
        if ($global:ImageConfig.Cache.Enabled) {
            $cachedImage = Get-ImageCache -Prompt $Prompt -Type $Type
            if ($cachedImage) {
                return $cachedImage
            }
        }
        
        # Generate output path if not provided
        if (-not $OutputPath) {
            $hash = Get-RandomHash
            $settings = Get-Settings
            $OutputPath = Join-Path $settings.Paths.ImagesDir "$hash.jpg"
        }
        
        # Process through model.ps1
        $result = Send-FluxPrompt `
            -Prompt $Prompt `
            -Width $size[0] `
            -Height $size[1] `
            -OutputPath $OutputPath `
            -Options $Options
        
        if (-not $result) {
            throw "Image generation failed"
        }
        
        # Optimize generated image
        $optimizedPath = Optimize-Image -InputPath $OutputPath
        
        # Cache result if enabled
        if ($global:ImageConfig.Cache.Enabled) {
            Add-ImageCache -Prompt $Prompt -Type $Type -Path $optimizedPath
        }
        
        return $optimizedPath
    }
    catch {
        Write-Error "Failed to generate image: $_"
        return $null
    }
}

function Send-FluxPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $true)]
        [int]$Width,
        [Parameter(Mandatory = $true)]
        [int]$Height,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [hashtable]$Options = @{}
    )
    
    try {
        # Default options for Flux v2
        $defaultOptions = @{
            Steps = 4
            CFGScale = 7.5
            Seed = -1
            NumThreads = -1
        }
        
        # Merge with provided options
        $finalOptions = $defaultOptions + $Options
        
        # Enhanced prompt for better quality
        $enhancedPrompt = New-ContentPrompt -Type "ImageGeneration" `
            -Title "Image Generation" `
            -Context $Prompt `
            -Parameters @{
                Quality = "High quality, detailed"
                Style = "Photorealistic"
            }
        
        # Get model config
        $modelConfig = $global:ModelState.ImageModel.Config
        
        # Set up parameters
        $params = @{
            ModelPath = $modelConfig.Path
            Width = $Width
            Height = $Height
            Steps = $finalOptions.Steps
            CFGScale = $finalOptions.CFGScale
            Seed = $finalOptions.Seed
            NumThreads = $finalOptions.NumThreads
            OutputPath = $OutputPath
        }
        
        # Generate through model.ps1
        return Invoke-FluxModel @params -Prompt $enhancedPrompt
    }
    catch {
        Write-Error "Failed to process Flux prompt: $_"
        return $null
    }
}

# Image Optimization
function Optimize-Image {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [string]$OutputPath = $null,
        [int]$Quality = $null,
        [int[]]$MaxSize = $null
    )
    
    try {
        # Get settings
        $settings = Get-Settings
        $quality = $Quality ?? $global:ImageConfig.Quality.Default
        
        # Validate quality
        if ($quality -lt $global:ImageConfig.Quality.Minimum -or 
            $quality -gt $global:ImageConfig.Quality.Maximum) {
            throw "Invalid quality value: $quality"
        }
        
        # Generate output path if not provided
        if (-not $OutputPath) {
            $hash = Get-RandomHash
            $OutputPath = Join-Path $settings.Paths.ImagesDir "$hash.jpg"
        }
        
        # Get ImageMagick path
        $magick = Join-Path $PSScriptRoot "..\data\ImageMagick\magick.exe"
        if (-not (Test-Path $magick)) {
            throw "ImageMagick not found"
        }
        
        # Build optimization arguments
        $args = @(
            $InputPath,
            "-strip",              # Remove metadata
            "-interlace", "Plane", # Progressive JPEG
            "-sampling-factor", "4:2:0",
            "-quality", $quality
        )
        
        # Add size constraint if provided
        if ($MaxSize) {
            $args += "-resize"
            $args += "${MaxSize[0]}x${MaxSize[1]}>"
        }
        
        $args += $OutputPath
        
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

# Image Analysis
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
        
        # Get ImageMagick path
        $magick = Join-Path $PSScriptRoot "..\data\ImageMagick\magick.exe"
        if (-not (Test-Path $magick)) {
            throw "ImageMagick not found"
        }
        
        # Build arguments
        $args = @(
            "identify",
            "-format", "%w|%h|%m|%Q|%[size]",
            $ImagePath
        )
        
        # Run ImageMagick
        $result = & $magick $args
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to get image metadata"
        }
        
        # Parse result
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
                Hash = (Get-FileHash $ImagePath -Algorithm SHA256).Hash.Substring(0, 8)
            }
        }
        
        throw "Invalid metadata format"
    }
    catch {
        Write-Error "Failed to get image metadata: $_"
        return $null
    }
}

# Cache Management
function Get-ImageCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $true)]
        [string]$Type
    )
    
    try {
        if (-not $global:ImageConfig.Cache.Enabled) {
            return $null
        }
        
        $cacheFile = Join-Path $global:PATHS.TempDir "image_cache.json"
        if (-not (Test-Path $cacheFile)) {
            return $null
        }
        
        # Load cache
        $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        
        # Generate hash for lookup
        $hash = Get-StringHash "$Prompt|$Type"
        
        # Check cache
        $entry = $cache.Images[$hash]
        if (-not $entry) {
            return $null
        }
        
        # Check age
        $age = [DateTime]::Now - [DateTime]::Parse($entry.Timestamp)
        if ($age -gt $global:ImageConfig.Cache.MaxAge) {
            return $null
        }
        
        # Verify file exists
        if (-not (Test-Path $entry.Path)) {
            return $null
        }
        
        return $entry.Path
    }
    catch {
        Write-Error "Failed to check image cache: $_"
        return $null
    }
}

function Add-ImageCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (-not $global:ImageConfig.Cache.Enabled) {
            return
        }
        
        $cacheFile = Join-Path $global:PATHS.TempDir "image_cache.json"
        
        # Load or create cache
        if (Test-Path $cacheFile) {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        }
        else {
            $cache = @{
                Version = "1.0"
                Images = @{}
                Size = 0
            }
        }
        
        # Generate hash
        $hash = Get-StringHash "$Prompt|$Type"
        
        # Add entry
        $cache.Images[$hash] = @{
            Path = $Path
            Timestamp = Get-Date -Format "o"
            Type = $Type
            Size = (Get-Item $Path).Length
        }
        
        # Update cache size
        $cache.Size = ($cache.Images.Values | Measure-Object Size -Sum).Sum
        
        # Prune if needed
        while ($cache.Size -gt $global:ImageConfig.Cache.MaxSize) {
            $oldest = $cache.Images.Values | 
                Sort-Object { [DateTime]::Parse($_.Timestamp) } |
                Select-Object -First 1
                
            $cache.Size -= $oldest.Size
            $cache.Images.Remove($oldest.Hash)
        }
        
        # Save cache
        $cache | ConvertTo-Json -Depth 10 | Set-Content $cacheFile
    }
    catch {
        Write-Error "Failed to add to image cache: $_"
    }
}

# Cache Management
function Clear-ImageCache {
    param(
        [switch]$Force,
        [int]$MaxAge = 24  # hours
    )
    
    try {
        $count = 0
        $maxTime = (Get-Date).AddHours(-$MaxAge)
        
        Get-ChildItem $global:PATHS.ImagesDir -File | ForEach-Object {
            if ($Force -or $_.LastWriteTime -lt $maxTime) {
                Remove-Item $_.FullName -Force
                $count++
            }
        }
        
        Write-StatusMessage "Cleared $count cached images" "Success"
        return $count
    }
    catch {
        Write-Error "Failed to clear image cache: $_"
        return -1
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-GeneratedImage',
    'Test-GeneratedImage',
    'Clear-ImageCache'
) -Variable 'ImageTypes'