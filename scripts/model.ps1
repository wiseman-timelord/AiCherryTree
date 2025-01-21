# AI model management and initialization
# .\scripts\model.ps1

# Set strict mode for better error detection
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import required modules
using namespace System.Collections.Concurrent
Import-Module "$PSScriptRoot\utility.ps1"

# Resource cleanup handler
$global:ResourceCleanup = [hashtable]::Synchronized(@{
    Processes = [ConcurrentBag[System.Diagnostics.Process]]::new()
    Handles = [ConcurrentBag[System.Runtime.InteropServices.SafeHandle]]::new()
})

# Model state tracking with thread safety
$global:ModelState = [hashtable]::Synchronized(@{
    TextModel = @{
        Initialized = $false
        LastError = $null
        Config = $null
        Process = $null
        Handle = $null
        Context = $null
        LastUsed = [datetime]::MinValue
    }
    ImageModel = @{
        Initialized = $false
        LastError = $null
        Config = $null
        Process = $null
        Handle = $null
        Context = $null
        LastUsed = [datetime]::MinValue
    }
})

# GPU Device definition with resource monitoring
class GPUDevice {
    [string]$Name
    [int]$Index
    [long]$Memory
    [string]$ComputeCapability
    [bool]$IsAvailable
    [hashtable]$Usage
    [datetime]$LastChecked
    
    GPUDevice([string]$name, [int]$index, [long]$memory, [string]$computeCapability) {
        $this.Name = $name
        $this.Index = $index
        $this.Memory = $memory
        $this.ComputeCapability = $computeCapability
        $this.IsAvailable = $true
        $this.Usage = @{
            Memory = 0
            Compute = 0
            Temperature = 0
            Power = 0
        }
        $this.LastChecked = [datetime]::MinValue
    }
    
    [void]UpdateUsage() {
        try {
            $nvsmiArgs = "--query-gpu=temperature.gpu,utilization.gpu,utilization.memory,memory.used,power.draw --format=csv,noheader -i $($this.Index)"
            $stats = (nvidia-smi $nvsmiArgs) -split ','
            
            $this.Usage.Temperature = [int]($stats[0] -replace ' C')
            $this.Usage.Compute = [int]($stats[1] -replace ' %')
            $this.Usage.Memory = [int]($stats[2] -replace ' %')
            $this.Usage.Power = [double]($stats[3] -replace ' W')
            $this.LastChecked = [datetime]::Now
        }
        catch {
            Write-Warning "Failed to update GPU usage: $_"
        }
    }
}

# Enhanced GPU Environment with resource management
class GPUEnvironment {
    hidden [ConcurrentDictionary[int, GPUDevice]]$Devices
    [bool]$IsInitialized
    [string]$LastError
    [hashtable]$Config
    [System.Timers.Timer]$MonitorTimer
    
    GPUEnvironment() {
        $this.Devices = [ConcurrentDictionary[int, GPUDevice]]::new()
        $this.IsInitialized = $false
        $this.LastError = ""
        $this.Config = @{
            MinComputeCapability = "7.0"
            MinMemory = 4GB
            PreferredDevice = 0
            MaxBatchSize = 4096
            MaxContextSize = 131072
            MonitoringInterval = 5000  # 5 seconds
            MemoryThreshold = 0.9      # 90% utilization threshold
            TemperatureThreshold = 85  # Celsius
        }
        
        # Initialize monitoring
        $this.MonitorTimer = [System.Timers.Timer]::new()
        $this.MonitorTimer.Interval = $this.Config.MonitoringInterval
        $this.MonitorTimer.Elapsed += {
            foreach ($device in $this.Devices.Values) {
                $device.UpdateUsage()
                
                # Check thresholds
                if ($device.Usage.Memory / 100 -gt $this.Config.MemoryThreshold) {
                    Write-Warning "GPU $($device.Index) memory utilization high: $($device.Usage.Memory)%"
                }
                if ($device.Usage.Temperature -gt $this.Config.TemperatureThreshold) {
                    Write-Warning "GPU $($device.Index) temperature high: $($device.Usage.Temperature)°C"
                }
            }
        }
    }
    
    [void]StartMonitoring() {
        $this.MonitorTimer.Start()
    }
    
    [void]StopMonitoring() {
        $this.MonitorTimer.Stop()
    }
    
    [GPUDevice]GetBestDevice() {
        return ($this.Devices.Values | 
            Where-Object { $_.IsAvailable } | 
            Sort-Object { $_.Usage.Memory } | 
            Select-Object -First 1)
    }
}

$global:GPUState = [GPUEnvironment]::new()

# Enhanced resource management functions
function Register-Resource {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Resource,
        [ValidateSet("Process", "Handle")]
        [string]$Type
    )
    
    switch ($Type) {
        "Process" { $global:ResourceCleanup.Processes.Add($Resource) }
        "Handle" { $global:ResourceCleanup.Handles.Add($Resource) }
    }
}

function Invoke-ResourceCleanup {
    # Cleanup processes
    $global:ResourceCleanup.Processes | ForEach-Object {
        if (-not $_.HasExited) {
            try {
                $_.Kill()
                $_.WaitForExit(5000)
            }
            catch { }
            finally {
                $_.Dispose()
            }
        }
    }
    
    # Cleanup handles
    $global:ResourceCleanup.Handles | ForEach-Object {
        if (-not $_.IsClosed) {
            try {
                $_.Close()
                $_.Dispose()
            }
            catch { }
        }
    }
    
    # Clear collections
    $global:ResourceCleanup.Processes = [ConcurrentBag[System.Diagnostics.Process]]::new()
    $global:ResourceCleanup.Handles = [ConcurrentBag[System.Runtime.InteropServices.SafeHandle]]::new()
}

# Enhanced GPU initialization
function Initialize-GPUEnvironment {
    param(
        [hashtable]$CustomConfig = @{},
        [switch]$Force
    )
    
    try {
        if ($global:GPUState.IsInitialized -and -not $Force) {
            return $true
        }
        
        Write-StatusMessage "Initializing GPU environment..." "Info"
        
        # Update configuration if provided
        if ($CustomConfig) {
            foreach ($key in $CustomConfig.Keys) {
                $global:GPUState.Config[$key] = $CustomConfig[$key]
            }
        }
        
        # Check CUDA availability
        $cudaPath = Join-Path $PSScriptRoot "..\data\cudart-llama-bin-win-cu11.7\cudart64_11.dll"
        if (-not (Test-Path $cudaPath)) {
            throw "CUDA runtime not found"
        }
        
        # Load CUDA DLL
        try {
            Add-Type -Path $cudaPath
        }
        catch {
            throw "Failed to load CUDA runtime: $_"
        }
        
        # Query available GPUs with retry logic
        $maxRetries = 3
        $retryDelay = 1
        $attempt = 0
        $success = $false
        
        while (-not $success -and $attempt -lt $maxRetries) {
            try {
                $gpuInfo = @()
                $nvsmiPath = "nvidia-smi"
                
                # Get GPU list
                $gpuList = Invoke-Expression "$nvsmiPath --query-gpu=name,memory.total,gpu_uuid --format=csv,noheader" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "nvidia-smi command failed"
                }
                
                $gpuList = $gpuList -split "`n" | Where-Object { $_ }
                
                for ($i = 0; $i -lt $gpuList.Count; $i++) {
                    $gpu = $gpuList[$i].Trim() -split ','
                    
                    # Get compute capability
                    $ccInfo = Invoke-Expression "$nvsmiPath -i $i --query-gpu=compute_cap --format=csv,noheader" 2>&1
                    $computeCapability = $ccInfo.Trim()
                    
                    # Parse memory (convert from MiB to bytes)
                    $memoryStr = $gpu[1].Trim() -replace ' MiB',''
                    $memoryBytes = [long]$memoryStr * 1024 * 1024
                    
                    $device = [GPUDevice]::new(
                        $gpu[0].Trim(),
                        $i,
                        $memoryBytes,
                        $computeCapability
                    )
                    
                    # Validate against requirements
                    if ([version]$computeCapability -lt [version]$global:GPUState.Config.MinComputeCapability) {
                        $device.IsAvailable = $false
                        Write-StatusMessage "GPU $i: Insufficient compute capability ($computeCapability)" "Warning"
                    }
                    
                    if ($memoryBytes -lt $global:GPUState.Config.MinMemory) {
                        $device.IsAvailable = $false
                        Write-StatusMessage "GPU $i: Insufficient memory ($(($memoryBytes/1GB).ToString('N1'))GB)" "Warning"
                    }
                    
                    # Add to device collection
                    $global:GPUState.Devices.TryAdd($i, $device)
                }
                
                $success = $true
            }
            catch {
                $attempt++
                if ($attempt -lt $maxRetries) {
                    Write-StatusMessage "GPU query attempt $attempt failed, retrying in ${retryDelay}s..." "Warning"
                    Start-Sleep -Seconds $retryDelay
                    $retryDelay *= 2  # Exponential backoff
                }
                else {
                    throw "Failed to query GPUs after $maxRetries attempts: $_"
                }
            }
        }
        
        # Verify at least one usable GPU
        $availableGPUs = $global:GPUState.Devices.Values | Where-Object { $_.IsAvailable }
        if ($availableGPUs.Count -eq 0) {
            throw "No GPUs meeting minimum requirements found"
        }
        
        # Initialize CUDA context
        try {
            $bestDevice = $global:GPUState.GetBestDevice()
            $env:CUDA_VISIBLE_DEVICES = $bestDevice.Index
            
            # Test CUDA context
            $testModelPath = Join-Path $PSScriptRoot "..\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf"
            $llamaPath = Join-Path $PSScriptRoot "..\data\llama-box.exe"
            
            $args = @(
                "--model", $testModelPath,
                "--n-gpu-layers", "1",
                "--ctx-size", "512",
                "--batch-size", "512",
                "--prompt", "test",
                "--n-predict", "1"
            )
            
            $process = Start-Process -FilePath $llamaPath -ArgumentList $args -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                throw "CUDA context test failed"
            }
        }
        catch {
            throw "Failed to initialize CUDA context: $_"
        }
        
        $global:GPUState.IsInitialized = $true
        $global:GPUState.StartMonitoring()
        
        Write-StatusMessage "GPU environment initialized successfully" "Success"
        return $true
    }
    catch {
        $global:GPUState.IsInitialized = $false
        $global:GPUState.LastError = $_.Exception.Message
        Write-StatusMessage "GPU initialization failed: $_" "Error"
        return $false
    }
}

# Enhanced model initialization
function Initialize-Models {
    param([switch]$Force)
    
    try {
        Write-StatusMessage "Initializing AI models..." "Info"
        
        # Initialize GPU environment first
        if (-not (Initialize-GPUEnvironment -Force:$Force)) {
            Write-StatusMessage "GPU initialization failed, falling back to CPU" "Warning"
        }
        
        # Initialize text model
        $textModelPath = Join-Path $PSScriptRoot "..\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf"
        $textContext = Initialize-GGUFContext -ModelPath $textModelPath -Device Auto
        if (-not $textContext) {
            throw "Failed to initialize text model"
        }
        $global:ModelState.TextModel.Context = $textContext
        $global:ModelState.TextModel.Initialized = $true
        
        # Initialize image model
        $imageModelPath = Join-Path $PSScriptRoot "..\models\FluxFusionV2-Q6_K.gguf"
        $imageContext = Initialize-GGUFContext -ModelPath $imageModelPath -Device Auto -Config @{
            ContextSize = 8192  # Smaller context for image generation
            BatchSize = 32
            Temperature = 1.0
        }
        if (-not $imageContext) {
            throw "Failed to initialize image model"
        }
        $global:ModelState.ImageModel.Context = $imageContext
        $global:ModelState.ImageModel.Initialized = $true
        
        Write-StatusMessage "Models initialized successfully" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to initialize models: $_" "Error"
        return $false
    }
    finally {
        # Register cleanup handler
        $ExecutionContext.SessionState.Module.OnRemove = {
            Invoke-ResourceCleanup
            if ($global:GPUState.IsInitialized) {
                $global:GPUState.StopMonitoring()
            }
        }
    }
}

# Optimized model interaction
function Invoke-GGUFModel {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ModelContext,
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [hashtable]$Options = @{},
        [switch]$Stream
    )
    
    $process = $null
    
    try {
        # Validate context
        if (-not $ModelContext -or -not $ModelContext.Path) {
            throw "Invalid model context"
        }
        if (-not (Test-Path $ModelContext.Path)) {
            throw "Model file not found: $($ModelContext.Path)"
        }

        # Get best GPU if available
        $device = if ($global:GPUState.IsInitialized) {
            $global:GPUState.GetBestDevice()
        }

        # Prepare command arguments with optimized defaults
        $llamaPath = Join-Path $PSScriptRoot "..\data\llama-box.exe"
        $args = [System.Collections.ArrayList]@(
            "--model", $ModelContext.Path,
            "--ctx-size", $ModelContext.Config.ContextSize,
            "--batch-size", $ModelContext.Config.BatchSize,
            "--threads", $ModelContext.Config.ThreadCount,
            "--temp", $ModelContext.Config.Temperature,
            "--top-k", $ModelContext.Config.TopK,
            "--top-p", $ModelContext.Config.TopP,
            "--repeat-penalty", $ModelContext.Config.RepeatPenalty
        )

        # Add GPU configuration if available
        if ($device) {
            $args.AddRange(@(
                "--n-gpu-layers", "32",
                "--gpu-device", $device.Index
            ))
        }

        # Add prompt
        $args.AddRange(@("--prompt", $Prompt))

        # Process options
        foreach ($key in $Options.Keys) {
            switch ($key) {
                "MaxTokens" { $args.AddRange(@("--n-predict", $Options[$key])) }
                "Seed" { $args.AddRange(@("--seed", $Options[$key])) }
                "Grammar" { $args.AddRange(@("--grammar", $Options[$key])) }
                "MMProj" { $args.AddRange(@("--mmproj", $Options[$key])) }
                "ImagePath" { $args.AddRange(@("--image", $Options[$key])) }
            }
        }

        # Create process with optimized settings
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $llamaPath
        $processInfo.Arguments = $args -join " "
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8

        # Start process with timeout monitoring
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        Register-Resource -Resource $process -Type "Process"

        # Handle output with buffering for better performance
        if ($Stream) {
            $buffer = [System.Text.StringBuilder]::new()
            while (-not $process.StandardOutput.EndOfStream) {
                $line = $process.StandardOutput.ReadLine()
                $buffer.AppendLine($line)
                
                # Flush buffer periodically
                if ($buffer.Length > 8192) {
                    Write-Output $buffer.ToString()
                    $buffer.Clear()
                }
            }
            # Flush remaining content
            if ($buffer.Length > 0) {
                Write-Output $buffer.ToString()
            }
        } else {
            $output = $process.StandardOutput.ReadToEnd()
            $process.WaitForExit(30000) # 30 second timeout

            if (-not $process.HasExited) {
                $process.Kill()
                throw "Model execution timed out"
            }

            if ($process.ExitCode -ne 0) {
                $error = $process.StandardError.ReadToEnd()
                throw "Model execution failed: $error"
            }

            return $output.Trim()
        }
    }
    catch {
        Write-Error "Failed to execute GGUF model: $_"
        return $null
    }
    finally {
        if ($process -and -not $process.HasExited) {
            try { $process.Kill() } catch { }
        }
    }
}

# Enhanced token management with caching
$global:TokenCache = [ConcurrentDictionary[string, int]]::new()

function Get-TokenCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [switch]$NoCache
    )
    
    try {
        # Check cache first
        $hash = Get-StringHash $Text
        if (-not $NoCache -and $global:TokenCache.ContainsKey($hash)) {
            return $global:TokenCache[$hash]
        }

        # Approximate token count based on character count
        # This is a rough estimation: ~4 characters per token on average
        $tokenCount = [math]::Ceiling($Text.Length / 4)
        
        # Cache result
        if (-not $NoCache) {
            $global:TokenCache.TryAdd($hash, $tokenCount)
        }

        return $tokenCount
    }
    catch {
        Write-Error "Failed to estimate token count: $_"
        return 0
    }
}

# Optimized model initialization with retries
function Initialize-LlamaBox {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelPath,
        [hashtable]$Config,
        [int]$MaxRetries = 3
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $MaxRetries) {
        try {
            $settings = Get-Settings
            $llamaBoxPath = Join-Path $PSScriptRoot "..\data\llama-box.exe"
            
            # Validate paths
            if (-not (Test-Path $llamaBoxPath)) {
                throw "LlamaBox executable not found: $llamaBoxPath"
            }
            if (-not (Test-Path $ModelPath)) {
                throw "Model file not found: $ModelPath"
            }
            
            # Optimized default configuration
            $defaultConfig = @{
                ThreadCount = [Environment]::ProcessorCount
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
                "--interactive"
            )
            
            # Create process with optimized settings
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $llamaBoxPath
            $processInfo.Arguments = $args -join " "
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardInput = $true
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true
            $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start()
            
            # Register for cleanup
            Register-Resource -Resource $process -Type "Process"
            
            # Wait for initialization with timeout
            $ready = $false
            $timeout = [DateTime]::Now.AddSeconds(30)
            while (-not $ready -and [DateTime]::Now -lt $timeout) {
                if ($process.HasExited) {
                    throw "Process exited during initialization"
                }
                
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
            $lastError = $_
            $attempt++
            
            if ($attempt -lt $MaxRetries) {
                Write-StatusMessage "Initialization attempt $attempt failed, retrying..." "Warning"
                Start-Sleep -Seconds ($attempt * 2)
            }
        }
    }
    
    Write-Error "Failed to initialize LlamaBox after $MaxRetries attempts: $lastError"
    return $null
}

# Enhanced model status monitoring
function Test-ModelHealth {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Text", "Image")]
        [string]$ModelType,
        [switch]$Detailed
    )
    
    try {
        $state = $global:ModelState."${ModelType}Model"
        $health = @{
            IsHealthy = $true
            Status = "OK"
            Details = @{}
            LastChecked = Get-Date
            Issues = @()
        }
        
        # Check initialization
        if (-not $state.Initialized) {
            $health.IsHealthy = $false
            $health.Status = "Not Initialized"
            $health.Issues += "Model not initialized"
            return $health
        }
        
        # Check process health for text model
        if ($ModelType -eq "Text" -and $state.Process) {
            if ($state.Process.HasExited) {
                $health.IsHealthy = $false
                $health.Status = "Process Exited"
                $health.Issues += "Model process has exited"
            }
            else {
                $health.Details["ProcessId"] = $state.Process.Id
                $health.Details["WorkingSet"] = $state.Process.WorkingSet64
                $health.Details["CpuTime"] = $state.Process.TotalProcessorTime
            }
        }
        
        # Check GPU status if using GPU
        if ($state.Config -and $state.Config.GpuLayers -gt 0 -and $global:GPUState.IsInitialized) {
            $gpuHealth = Test-GPUHealth -Detailed:$Detailed
            $health.Details["GPU"] = $gpuHealth
            
            # Check for GPU issues
            $gpuIssues = $gpuHealth | Where-Object { -not $_.IsHealthy } | ForEach-Object { $_.Issues }
            if ($gpuIssues) {
                $health.IsHealthy = $false
                $health.Status = "GPU Issues"
                $health.Issues += $gpuIssues
            }
        }
        
        # Check memory usage
        $memory = [System.GC]::GetTotalMemory($false)
        $health.Details["ManagedMemory"] = $memory
        if ($memory -gt 2GB) {
            $health.Issues += "High memory usage"
        }
        
        return $health
    }
    catch {
        Write-Error "Failed to test model health: $_"
        return @{
            IsHealthy = $false
            Status = "Error"
            Issues = @("Health check failed: $_")
            LastChecked = Get-Date
        }
    }
}

# Export finalized functions
Export-ModuleMember -Function @(
    # Model Management
    'Initialize-Models',
    'Initialize-LlamaBox',
    'Invoke-GGUFModel',
    'Test-ModelHealth',
    'Get-TokenCount',
    
    # GPU Management
    'Initialize-GPUEnvironment',
    'Get-GPUState',
    'Test-GPUHealth',
    'Reset-GPUState'
) -Variable @(
    'ModelState',
    'GPUState'
)