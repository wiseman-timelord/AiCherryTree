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
        Handle = $null
    }
    ImageModel = @{
        Initialized = $false
        LastError = $null
        Config = $null
        Process = $null
        Handle = $null
    }
}

# LlamaBox Integration
function Initialize-LlamaBox {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelPath,
        [hashtable]$Config
    )
    
    try {
        $settings = Get-Settings
        $llamaBoxPath = Join-Path $PSScriptRoot "..\data\llama-box.exe"
        
        if (-not (Test-Path $llamaBoxPath)) {
            throw "LlamaBox executable not found: $llamaBoxPath"
        }
        
        if (-not (Test-Path $ModelPath)) {
            throw "Model file not found: $ModelPath"
        }
        
        # Default configuration
        $defaultConfig = @{
            ThreadCount = -1  # Auto-detect
            ContextSize = 32768
            BatchSize = 4096
            Temperature = 0.8
            TopK = 40
            TopP = 0.9
            RepeatPenalty = 1.1
            GpuLayers = 32
        }
        
        # Merge with provided config
        $finalConfig = $defaultConfig
        if ($Config) {
            foreach ($key in $Config.Keys) {
                $finalConfig[$key] = $Config[$key]
            }
        }
        
        # Build arguments
        $args = @(
            "--model", $ModelPath,
            "--ctx-size", $finalConfig.ContextSize,
            "--batch-size", $finalConfig.BatchSize,
            "--threads", $finalConfig.ThreadCount,
            "--gpu-layers", $finalConfig.GpuLayers,
            "--temp", $finalConfig.Temperature,
            "--top-k", $finalConfig.TopK,
            "--top-p", $finalConfig.TopP,
            "--repeat-penalty", $finalConfig.RepeatPenalty,
            "--interactive"  # Enable interactive mode for continuous use
        )
        
        # Start LlamaBox process
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $llamaBoxPath
        $processInfo.Arguments = $args -join " "
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardInput = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start()
        
        # Wait for initialization
        $ready = $false
        $timeout = [DateTime]::Now.AddSeconds(30)
        while (-not $ready -and [DateTime]::Now -lt $timeout) {
            $line = $process.StandardOutput.ReadLine()
            if ($line -match "Interactive mode") {
                $ready = $true
            }
            if ($line -match "error|fatal|failed") {
                throw "LlamaBox initialization failed: $line"
            }
        }
        
        if (-not $ready) {
            throw "LlamaBox initialization timed out"
        }
        
        return @{
            Process = $process
            Config = $finalConfig
        }
    }
    catch {
        Write-Error "Failed to initialize LlamaBox: $_"
        return $null
    }
}

function Send-LlamaBoxPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [hashtable]$Options = @{},
        [switch]$Stream
    )
    
    try {
        # Ensure process is running
        if ($Process.HasExited) {
            throw "LlamaBox process has exited"
        }
        
        # Send prompt
        $Process.StandardInput.WriteLine($Prompt)
        $Process.StandardInput.WriteLine("<|end|>")  # Signal end of prompt
        
        # Read response
        $response = ""
        $reading = $true
        
        while ($reading) {
            $line = $Process.StandardOutput.ReadLine()
            
            # Check for end marker or error
            if ($line -eq "<|end|>") {
                $reading = $false
            }
            elseif ($line -match "^error:|^fatal:") {
                throw "LlamaBox error: $line"
            }
            else {
                if ($Stream) {
                    Write-Output $line
                }
                else {
                    $response += "$line`n"
                }
            }
        }
        
        if (-not $Stream) {
            return $response.Trim()
        }
    }
    catch {
        Write-Error "Failed to send prompt to LlamaBox: $_"
        return $null
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
        
        # If already initialized and not forced reload
        if ($global:ModelState.TextModel.Initialized -and -not $ForceReload) {
            return $true
        }
        
        # Clean up existing process if any
        if ($global:ModelState.TextModel.Process) {
            try { 
                $global:ModelState.TextModel.Process.Kill()
                $global:ModelState.TextModel.Process.Dispose()
            }
            catch { }
        }
        
        # Initialize new model
        $modelPath = Join-Path $PSScriptRoot "..\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf"
        $result = Initialize-LlamaBox -ModelPath $modelPath -Config $CustomConfig
        
        if (-not $result) {
            throw "Failed to initialize LlamaBox"
        }
        
        # Update global state
        $global:ModelState.TextModel.Process = $result.Process
        $global:ModelState.TextModel.Config = $result.Config
        $global:ModelState.TextModel.Initialized = $true
        $global:ModelState.TextModel.LastError = $null
        
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

# Text Generation
function Send-TextPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [hashtable]$Options = @{},
        [switch]$Stream
    )
    
    try {
        # Check model state
        if (-not $global:ModelState.TextModel.Initialized) {
            throw "Text model not initialized"
        }
        
        # Send prompt to LlamaBox
        $result = Send-LlamaBoxPrompt -Process $global:ModelState.TextModel.Process `
            -Prompt $Prompt -Options $Options -Stream:$Stream
            
        if ($null -eq $result) {
            throw "Failed to get response from model"
        }
        
        return $result
    }
    catch {
        Write-Error "Failed to process text prompt: $_"
        return $null
    }
}

# Token Management
function Get-TokenCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    
    try {
        # Approximate token count based on character count
        # This is a rough estimation: ~4 characters per token on average
        return [math]::Ceiling($Text.Length / 4)
    }
    catch {
        Write-Error "Failed to estimate token count: $_"
        return 0
    }
}

function Test-ContextLimit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [int]$MaxTokens = 0
    )
    
    try {
        $settings = Get-Settings
        if ($MaxTokens -eq 0) {
            $MaxTokens = $settings.TextModel.DefaultContextSize
        }
        
        $tokenCount = Get-TokenCount -Text $Text
        return $tokenCount -le $MaxTokens
    }
    catch {
        Write-Error "Failed to test context limit: $_"
        return $false
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
    
    try {
        $state = $global:ModelState."${ModelType}Model"
        
        # Basic health check
        if (-not $state.Initialized) {
            return $false
        }
        
        # Check process health for text model
        if ($ModelType -eq "Text" -and $state.Process) {
            if ($state.Process.HasExited) {
                $state.Initialized = $false
                $state.LastError = "Process has exited"
                return $false
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to test model health: $_"
        return $false
    }
}

function Reset-ModelState {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Text", "Image")]
        [string]$ModelType
    )
    
    try {
        $state = $global:ModelState."${ModelType}Model"
        
        # Clean up process if exists
        if ($state.Process) {
            try {
                $state.Process.Kill()
                $state.Process.Dispose()
            }
            catch { }
        }
        
        # Reset state
        $state.Initialized = $false
        $state.LastError = $null
        $state.Config = $null
        $state.Process = $null
        $state.Handle = $null
        
        return $true
    }
    catch {
        Write-Error "Failed to reset model state: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function * -Variable ModelState