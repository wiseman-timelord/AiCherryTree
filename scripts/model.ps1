# AI model management and initialization
# .\scripts\model.ps1

# Import required modules
Import-Module "$PSScriptRoot\utility.ps1"

# Model state tracking
$global:ModelState = @{
    TextModel = @{
        Initialized = $false
        LastError = $null
        Config = $null
        Process = $null
    }
    ImageModel = @{
        Initialized = $false
        LastError = $null
        Config = $null
        Process = $null
    }
}

# GGUF Model Functions
function Get-GGUFInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        # Read first 8 bytes to verify GGUF magic
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $magic = [System.Text.Encoding]::ASCII.GetString($bytes[0..3])
        
        if ($magic -ne "GGUF") {
            throw "Not a valid GGUF model file"
        }
        
        # Parse version (next 4 bytes as uint32)
        $version = [BitConverter]::ToUInt32($bytes[4..7], 0)
        
        return @{
            Path = $Path
            Version = $version
            Size = (Get-Item $Path).Length
            Valid = $true
        }
    }
    catch {
        Write-Error "Failed to get GGUF info: $_"
        return $null
    }
}

function Invoke-FluxModel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [string]$ModelPath,
        [int]$Width = 512,
        [int]$Height = 512,
        [int]$Steps = 4,
        [float]$CFGScale = 7.5,
        [int]$Seed = -1,
        [int]$NumThreads = -1,
        [int]$BatchSize = 1
    )
    
    try {
        # Validate model
        if (-not (Test-GGUFModel -Path $ModelPath)) {
            throw "Invalid or missing GGUF model"
        }
        
        # Load CLBlast DLL for GPU acceleration
        $clblastPath = Join-Path $PSScriptRoot "..\data\clblast.dll"
        if (Test-Path $clblastPath) {
            Add-Type -Path $clblastPath
        }
        
        # Prepare model parameters
        $modelParams = @{
            prompt = $Prompt
            width = $Width
            height = $Height
            steps = $Steps
            cfg_scale = $CFGScale
            seed = $Seed
            threads = $NumThreads
            batch_size = $BatchSize
        }
        
        # Convert parameters to format expected by GGUF
        $jsonParams = ConvertTo-Json $modelParams -Compress
        
        # Allocate unmanaged memory for image generation
        $imageData = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($Width * $Height * 3)
        
        try {
            # Initialize model
            $handle = Initialize-GGUFModel -Path $ModelPath
            if (-not $handle) {
                throw "Failed to initialize GGUF model"
            }
            
            # Generate image
            $result = Generate-GGUFImage -Handle $handle -Params $jsonParams -Output $imageData
            if (-not $result) {
                throw "Image generation failed"
            }
            
            # Save image
            Save-ImageData -Data $imageData -Width $Width -Height $Height -Path $OutputPath
            
            return $true
        }
        finally {
            # Clean up
            if ($handle) {
                Close-GGUFModel -Handle $handle
            }
            if ($imageData) {
                [System.Runtime.InteropServices.Marshal]::FreeHGlobal($imageData)
            }
        }
    }
    catch {
        Write-Error "Failed to invoke Flux model: $_"
        return $false
    }
}

function Test-GGUFModel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        # Check file existence
        if (-not (Test-Path $Path)) {
            return $false
        }
        
        # Validate GGUF format
        $info = Get-GGUFInfo -Path $Path
        return $info -and $info.Valid
    }
    catch {
        Write-Error "Failed to test GGUF model: $_"
        return $false
    }
}

# Initialize GPU Environment
function Initialize-GPUEnvironment {
    param([hashtable]$CustomConfig = @{})
    
    try {
        Write-StatusMessage "Initializing GPU environment..." "Info"
        
        # Set environment variables
        $env:CUDA_VISIBLE_DEVICES = "0"
        $env:GGML_OPENCL_PLATFORM = "0"
        $env:GGML_OPENCL_DEVICE = "0"
        
        # Load settings
        $settings = Get-Settings
        $gpuConfig = $settings.GPU
        
        # Merge with custom config
        foreach ($key in $CustomConfig.Keys) {
            $gpuConfig[$key] = $CustomConfig[$key]
        }
        
        # Initialize OpenCL
        $clblastPath = Join-Path $PSScriptRoot "..\data\clblast.dll"
        if (Test-Path $clblastPath) {
            Add-Type -Path $clblastPath
            $gpuConfig.UseOpenCL = $true
        }
        else {
            Write-StatusMessage "OpenCL support not available" "Warning"
            $gpuConfig.UseOpenCL = $false
        }
        
        # Update settings
        $settings.GPU = $gpuConfig
        Set-Settings -Settings $settings
        
        Write-StatusMessage "GPU environment initialized" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to initialize GPU environment: $_" "Error"
        return $false
    }
}

# Model Initialization
function Initialize-TextModel {
    param(
        [switch]$ForceReload,
        [hashtable]$CustomConfig = @{}
    )
    
    try {
        Write-StatusMessage "Initializing text model..." "Info"
        
        # Validate required files
        $modelPath = Join-Path $PSScriptRoot "..\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf"
        
        if (-not (Test-Path $modelPath)) {
            throw "Model file not found: $modelPath"
        }
        
        # Configure model parameters
        $config = @{
            Path = $modelPath
            ContextSize = 32768
            BatchSize = 4096
            Temperature = 0.8
            TopP = 0.9
            RepeatPenalty = 1.1
            NumThreads = -1
            NumGPULayers = 32
            RMSNormEps = 1e-5
            RopeFreqBase = 10000
            RopeFreqScale = 1.0
        }
        
        # Add custom config
        foreach ($key in $CustomConfig.Keys) {
            $config[$key] = $CustomConfig[$key]
        }
        
        # Validate model
        if (-not (Test-GGUFModel -Path $modelPath)) {
            throw "Invalid GGUF model file"
        }
        
        # Store config globally
        $global:ModelState.TextModel.Config = $config
        $global:ModelState.TextModel.Initialized = $true
        
        Write-StatusMessage "Text model initialized successfully" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to initialize text model: $_" "Error"
        $global:ModelState.TextModel.Initialized = $false
        $global:ModelState.TextModel.LastError = $_.Exception.Message
        return $false
    }
}

function Initialize-ImageModel {
    param(
        [switch]$ForceReload,
        [hashtable]$CustomConfig = @{}
    )
    
    try {
        Write-StatusMessage "Initializing image model..." "Info"
        
        # Validate required files
        $modelPath = Join-Path $PSScriptRoot "..\models\FluxFusionV2-Q6_K.gguf"
        
        if (-not (Test-Path $modelPath)) {
            throw "Model file not found: $modelPath"
        }
        
        # Configure model parameters
        $config = @{
            Path = $modelPath
            DefaultSize = @{
                Scene = @(200, 200)
                Person = @(100, 200)
                Item = @(100, 100)
            }
            Steps = 4
            CFGScale = 7.5
            NumThreads = -1
        }
        
        # Add custom config
        foreach ($key in $CustomConfig.Keys) {
            $config[$key] = $CustomConfig[$key]
        }
        
        # Validate model
        if (-not (Test-GGUFModel -Path $modelPath)) {
            throw "Invalid GGUF model file"
        }
        
        # Store config globally
        $global:ModelState.ImageModel.Config = $config
        $global:ModelState.ImageModel.Initialized = $true
        
        Write-StatusMessage "Image model initialized successfully" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to initialize image model: $_" "Error"
        $global:ModelState.ImageModel.Initialized = $false
        $global:ModelState.ImageModel.LastError = $_.Exception.Message
        return $false
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
        # Check model state
        if (-not $global:ModelState.ImageModel.Initialized) {
            throw "Image model not initialized"
        }
        
        # Validate type
        if (-not $global:ModelState.ImageModel.Config.DefaultSize.ContainsKey($Type)) {
            throw "Invalid image type: $Type. Must be Scene, Person, or Item."
        }
        
        # Generate output path if not provided
        if (-not $OutputPath) {
            $hash = Get-RandomHash
            $OutputPath = Join-Path $global:PATHS.ImagesDir "$hash.jpg"
        }
        
        # Get size configuration
        $size = $global:ModelState.ImageModel.Config.DefaultSize[$Type]
        
        # Prepare model parameters
        $modelParams = @{
            ModelPath = $global:ModelState.ImageModel.Config.Path
            Width = $size[0]
            Height = $size[1]
            Steps = $global:ModelState.ImageModel.Config.Steps
            CFGScale = $global:ModelState.ImageModel.Config.CFGScale
            NumThreads = $global:ModelState.ImageModel.Config.NumThreads
        }
        
        # Add custom options
        foreach ($key in $Options.Keys) {
            $modelParams[$key] = $Options[$key]
        }
        
        # Generate image
        $result = Invoke-FluxModel -Prompt $Prompt -OutputPath $OutputPath @modelParams
        
        if (-not $result) {
            throw "Image generation failed"
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

# Model Status Functions
function Get-ModelStatus {
    return $global:ModelState
}

function Test-ModelHealth {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Text", "Image")]
        [string]$ModelType
    )
    
    $state = $global:ModelState."${ModelType}Model"
    return $state.Initialized -and -not $state.LastError
}

function Reset-ModelState {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Text", "Image")]
        [string]$ModelType
    )
    
    $state = $global:ModelState."${ModelType}Model"
    $state.Initialized = $false
    $state.LastError = $null
    $state.Config = $null
    if ($state.Process) {
        try { $state.Process.Kill() } catch { }
        $state.Process = $null
    }
}

# Export functions
Export-ModuleMember -Function * -Variable ModelState