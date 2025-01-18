# Text generation and processing module
# texts.ps1

# Configuration defaults
$global:TextModelConfig = @{
    Path = ".\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf"
    BinaryPath = ".\data\llama-box.exe"
    DefaultContextSize = 24576  # Default n_ctx
    MinContextSize = 8192      # Minimum allowed
    MaxContextSize = 131072    # Maximum allowed
    DefaultBatchSize = 4096    # Default n_batch
    MinBatchSize = 1024       # Minimum allowed
    MaxBatchSize = 5120       # Maximum allowed
    Temperature = 0.8
    TopK = 40
    TopP = 0.9
    RepeatPenalty = 1.1
    MaxTokens = -1            # -1 for dynamic based on context
    MaxChars = 2400          # Maximum characters per node
    ChatTemplate = "llama2"   # Default template
    NumThreads = -1           # Auto-detect
}

# Advanced sampler configuration
$global:SamplerConfig = @{
    PresencePenalty = 0.0
    FrequencyPenalty = 0.0
    DryMultiplier = 1.0
    DryBase = 1.75
    DryAllowedLength = 2
    MinP = 0.1
    TypicalP = 1.0
}

# GPU configuration
$global:GPUConfig = @{
    MainGPU = 0
    SplitMode = "layer"      # none, layer, row
    DeviceList = @()         # Populated during initialization
    CacheTypeK = "f16"
    CacheTypeV = "f16"
    DefragThreshold = 0.1
}

function Initialize-TextModel {
    param(
        [switch]$ForceReload,
        [hashtable]$CustomConfig = @{}
    )
    
    try {
        Write-StatusMessage "Initializing text model..." "Info"
        
        # Check binary existence
        if (-not (Test-Path $global:TextModelConfig.BinaryPath)) {
            throw "llama-box binary not found at $($global:TextModelConfig.BinaryPath)"
        }
        
        # Check model file
        if (-not (Test-Path $global:TextModelConfig.Path)) {
            throw "Model file not found at $($global:TextModelConfig.Path)"
        }

        # Get available GPUs
        $deviceList = Get-GPUDevices
        $global:GPUConfig.DeviceList = $deviceList

        # Test model loading with minimal context
        $testArgs = @(
            "--ctx-size", "2048",
            "--threads", "1",
            "--model", $global:TextModelConfig.Path,
            "--help"
        )
        
        $testProcess = Start-Process -FilePath $global:TextModelConfig.BinaryPath `
                                   -ArgumentList $testArgs `
                                   -Wait -PassThru -NoNewWindow
        
        if ($testProcess.ExitCode -ne 0) {
            throw "Model test failed with exit code $($testProcess.ExitCode)"
        }

        $global:TempVars.TextModelLoaded = $true
        Write-StatusMessage "Text model initialized successfully" "Success"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to initialize text model: $_" "Error"
        $global:TempVars.TextModelLoaded = $false
        return $false
    }
}

function Get-GPUDevices {
    $process = Start-Process -FilePath $global:TextModelConfig.BinaryPath `
                            -ArgumentList "--list-devices" `
                            -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\gpulist.txt"
    
    $devices = Get-Content "$env:TEMP\gpulist.txt" | Where-Object { $_ -match "GPU" }
    Remove-Item "$env:TEMP\gpulist.txt" -Force
    
    return $devices
}

function Get-ModelArgs {
    param(
        [hashtable]$Options = @{}
    )
    
    # Merge with defaults
    $config = @{} + $global:TextModelConfig
    foreach ($key in $Options.Keys) {
        $config[$key] = $Options[$key]
    }
    
    $args = @(
        "--model", $config.Path,
        "--ctx-size", $config.DefaultContextSize,
        "--threads", $config.NumThreads,
        "--temp", $config.Temperature,
        "--top-k", $config.TopK,
        "--top-p", $config.TopP,
        "--repeat-penalty", $config.RepeatPenalty,
        "--batch-size", $config.DefaultBatchSize,
        "--chat-template", $config.ChatTemplate,
        "--device", $global:GPUConfig.MainGPU,
        "--split-mode", $global:GPUConfig.SplitMode,
        "--cache-type-k", $global:GPUConfig.CacheTypeK,
        "--cache-type-v", $global:GPUConfig.CacheTypeV,
        "--defrag-thold", $global:GPUConfig.DefragThreshold
    )
    
    # Add advanced sampler options
    foreach ($key in $global:SamplerConfig.Keys) {
        $args += "--$($key.ToLower())", $global:SamplerConfig[$key]
    }
    
    return $args
}

function Send-TextPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [hashtable]$Options = @{},
        [switch]$Stream,
        [switch]$AllowWebResearch
    )
    
    try {
        # Check if web research is needed
        if ($AllowWebResearch) {
            # Use text model to check if research needed
            $needsResearch = Test-NeedsResearch -Prompt $Prompt
            
            if ($needsResearch) {
                # Get web research results
                $webResults = Get-WebResearch -Query $Prompt
                
                # Enhance prompt with research
                $Prompt = @"
Context from web research:
$webResults

Original prompt:
$Prompt
"@
            }
        }
        
        # Get base arguments
        $args = Get-ModelArgs -Options $Options
        
        # Add prompt-specific arguments
        $args += @(
            "--prompt", $Prompt
        )
        
        if ($Stream) {
            # Implement streaming output handler
            $process = Start-Process -FilePath $global:TextModelConfig.BinaryPath `
                                   -ArgumentList $args `
                                   -NoNewWindow `
                                   -RedirectStandardOutput "$env:TEMP\output.txt" `
                                   -PassThru
            
            # Monitor output file
            while (-not $process.HasExited) {
                if (Test-Path "$env:TEMP\output.txt") {
                    $newContent = Get-Content "$env:TEMP\output.txt" -Tail 1
                    if ($newContent) {
                        Write-Output $newContent
                    }
                }
                Start-Sleep -Milliseconds 100
            }
            
            Remove-Item "$env:TEMP\output.txt" -Force
        }
        else {
            # Regular output
            $process = Start-Process -FilePath $global:TextModelConfig.BinaryPath `
                                   -ArgumentList $args `
                                   -Wait -PassThru -NoNewWindow `
                                   -RedirectStandardOutput "$env:TEMP\response.txt"
            
            if ($process.ExitCode -ne 0) {
                throw "Text generation failed with exit code $($process.ExitCode)"
            }
            
            $response = Get-Content "$env:TEMP\response.txt" -Raw
            Remove-Item "$env:TEMP\response.txt" -Force
            
            return Format-ModelResponse $response
        }
    }
    catch {
        Write-Error "Failed to process text prompt: $_"
        return $null
    }
}

function Get-NodeContext {
    param(
        [string]$NodeId,
        [int]$MaxDepth = 3,
        [int]$MaxChars = 2400
    )
    
    $tree = Get-TreeData
    $node = Find-TreeNode -Tree $tree -NodeId $NodeId
    $context = @()
    
    # Get parent context
    $parent = $node
    $depth = 0
    while ($parent -and $depth -lt $MaxDepth) {
        if ($parent.TextHash) {
            $content = Get-TreeNodeContent -TextHash $parent.TextHash
            if ($content.Length -gt $MaxChars) {
                $content = $content.Substring(0, $MaxChars)
            }
            $context += @{
                Title = $parent.Title
                Content = $content
                Relation = if ($depth -eq 0) { "current" } else { "parent" }
            }
        }
        $parent = Find-TreeNode -Tree $tree -NodeId $parent.ParentId
        $depth++
    }
    
    # Get immediate children context
    foreach ($child in $node.Children) {
        if ($child.TextHash) {
            $content = Get-TreeNodeContent -TextHash $child.TextHash
            if ($content.Length -gt $MaxChars) {
                $content = $content.Substring(0, $MaxChars)
            }
            $context += @{
                Title = $child.Title
                Content = $content
                Relation = "child"
            }
        }
    }
    
    return $context
}

function Format-ModelResponse {
    param(
        [string]$Response,
        [string]$Format = "text"
    )
    
    $cleaned = $Response.Trim()
    
    switch ($Format) {
        "text" { 
            # Ensure response doesn't exceed max chars
            if ($cleaned.Length -gt $global:TextModelConfig.MaxChars) {
                $cleaned = $cleaned.Substring(0, $global:TextModelConfig.MaxChars)
            }
            return $cleaned 
        }
        "json" {
            try {
                return $cleaned | ConvertFrom-Json
            }
            catch {
                Write-Error "Failed to parse JSON response"
                return $null
            }
        }
        default {
            return $cleaned
        }
    }
}

# Web research integration
function Test-NeedsResearch {
    param([string]$Prompt)
    
    $analysisPrompt = @"
Analyze this prompt and determine if it requires factual information that would benefit from web research.
Consider things like:
- Specific people, places, or events
- Technical or scientific information
- Current events or recent developments
- Statistical data or facts

Prompt: $Prompt

Answer with just 'yes' or 'no'.
"@

    $result = Send-TextPrompt -Prompt $analysisPrompt -Options @{
        Temperature = 0.1
        MaxTokens = 10
    }
    
    return $result.Trim().ToLower() -eq 'yes'
}

function Get-WebResearch {
    param([string]$Query)
    
    # Import internet module functions
    . "$PSScriptRoot\internet.ps1"
    
    # Get search results
    $results = Search-Web -Query $Query -MaxResults 3
    
    # Extract content from top results
    $content = @()
    foreach ($result in $results) {
        $text = Get-WebContent -Url $result.Url
        if ($text) {
            $content += $text
        }
    }
    
    return ($content -join "`n`n")
}

# Export functions
Export-ModuleMember -Function *