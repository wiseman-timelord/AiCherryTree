# Text generation and processing module
# texts.ps1

$settings = Get-Settings
$global:TextModelConfig = $settings.TextModel
$global:GPUConfig = $settings.GPU

# GPU and model configurations
$global:ModelConfig = @{
    Text = @{
        Path = $global:TextModelConfig.Path
        ContextSize = $global:TextModelConfig.DefaultContextSize
        BatchSize = $global:TextModelConfig.DefaultBatchSize
        Temperature = $global:TextModelConfig.Temperature
    }
    Image = @{
        Path = ".\models\FluxFusionV2-Q6_K.gguf"
        DefaultSizes = @{
            Scene = @(200, 200)
            Person = @(100, 200)
            Item = @(100, 100)
        }
    }
    GPU = @{
        MainGPU = 0
        SplitMode = "layer"      # none, layer, row
        DeviceList = @()         # Populated during initialization
        CacheTypeK = "f16"
        CacheTypeV = "f16"
        DefragThreshold = 0.1
    }
}

# Update model initialization
function Initialize-TextModel {
    param(
        [switch]$ForceReload,
        [hashtable]$CustomConfig = @{}
    )
    
    try {
        Write-StatusMessage "Initializing text model..." "Info"
        
        # Validate required files
        $modelPath = Join-Path $PSScriptRoot "..\models\Llama-3.2-3b-NSFW_Aesir_Uncensored.gguf"
        $llamaPath = Join-Path $PSScriptRoot "..\data\llama-box.exe"
        
        if (-not (Test-Path $modelPath)) {
            throw "Model file not found: $modelPath"
        }
        if (-not (Test-Path $llamaPath)) {
            throw "llama-box not found: $llamaPath"
        }
        
        # Configure model parameters
        $config = @{
            Path = $modelPath
            BinaryPath = $llamaPath
            ContextSize = 32768
            BatchSize = 4096
            Temperature = 0.8
            TopP = 0.9
            RepeatPenalty = 1.1
        }
        
        # Add custom config
        foreach ($key in $CustomConfig.Keys) {
            $config[$key] = $CustomConfig[$key]
        }
        
        # Test model loading
        $testArgs = @(
            "--model", $config.Path,
            "--ctx-size", $config.ContextSize,
            "--help"
        )
        
        $process = Start-Process -FilePath $config.BinaryPath -ArgumentList $testArgs -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -ne 0) {
            throw "Model initialization failed with exit code: $($process.ExitCode)"
        }
        
        # Store config globally
        $global:TextModelConfig = $config
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

# Add completion function
function Get-TextCompletion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [hashtable]$Options = @{},
        [switch]$Stream
    )
    
    try {
        # Ensure model is initialized
        if (-not $global:TempVars.TextModelLoaded) {
            if (-not (Initialize-TextModel)) {
                throw "Failed to initialize text model"
            }
        }
        
        # Build arguments
        $args = @(
            "--model", $global:TextModelConfig.Path,
            "--ctx-size", $global:TextModelConfig.ContextSize,
            "--temp", $global:TextModelConfig.Temperature,
            "--top-p", $global:TextModelConfig.TopP,
            "--repeat-penalty", $global:TextModelConfig.RepeatPenalty,
            "--prompt", $Prompt
        )
        
        # Add custom options
        foreach ($key in $Options.Keys) {
            $args += "--$($key.ToLower())", $Options[$key]
        }
        
        if ($Stream) {
            $process = Start-Process -FilePath $global:TextModelConfig.BinaryPath `
                -ArgumentList $args -NoNewWindow -RedirectStandardOutput "$env:TEMP\stream.txt" -PassThru
            
            while (-not $process.HasExited) {
                Get-Content "$env:TEMP\stream.txt" -Wait
                Start-Sleep -Milliseconds 100
            }
            Remove-Item "$env:TEMP\stream.txt" -Force
        }
        else {
            $output = & $global:TextModelConfig.BinaryPath $args
            return $output
        }
    }
    catch {
        Write-Error "Text completion failed: $_"
        return $null
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

function Format-ChatPrompt {
    param(
        [string]$UserMessage,
        [hashtable]$Context = @{},
        [string]$SystemPrompt = ""
    )
    
    # Build context section
    $contextText = ""
    if ($Context.CurrentNode) {
        $contextText += "Current Node: $($Context.CurrentNode.Title)`n"
        if ($Context.CurrentNode.Content) {
            $contextText += "Node Content: $($Context.CurrentNode.Content)`n"
        }
    }
    
    # Default system prompt if none provided
    if (-not $SystemPrompt) {
        $SystemPrompt = @"
You are assisting with a document tree management system. You can:
1. Create new nodes
2. Update existing nodes
3. Generate content
4. Provide information about the system

Use commands like:
##COMMAND:CreateNode:Title## - Create a new node
##COMMAND:UpdateNode:Content## - Update current node
##COMMAND:GenerateContent:Type:Prompt## - Generate content

Always confirm actions before executing them.
"@
    }

    # Combine all parts
    $fullPrompt = @"
$SystemPrompt

Context:
$contextText

User Message:
$UserMessage

Provide a helpful response and include any necessary commands.
"@

    return $fullPrompt
}

function Process-ChatResponse {
    param(
        [string]$Response,
        [scriptblock]$CommandHandler
    )
    
    $result = @{
        Message = $Response
        Commands = @()
    }
    
    # Extract commands
    $pattern = '##COMMAND:([^#]+)##'
    $matches = [regex]::Matches($Response, $pattern)
    
    foreach ($match in $matches) {
        $command = $match.Groups[1].Value.Trim()
        $parts = $command -split ':'
        
        $commandInfo = @{
            Type = $parts[0]
            Parameters = $parts[1..$parts.Length]
        }
        
        $result.Commands += $commandInfo
    }
    
    # Clean response of command syntax
    $result.Message = $Response -replace $pattern, ''
    
    return $result
}

function Send-ChatPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [hashtable]$Context = @{},
        [hashtable]$Options = @{}
    )
    
    try {
        # Format prompt
        $prompt = Format-ChatPrompt -UserMessage $Message -Context $Context
        
        # Default options for chat
        $defaultOptions = @{
            Temperature = 0.7
            MaxTokens = 2000
            TopP = 0.95
        }
        
        # Merge with provided options
        $finalOptions = $defaultOptions + $Options
        
        # Get response
        $response = Send-TextPrompt -Prompt $prompt -Options $finalOptions
        
        # Process response
        $processed = Process-ChatResponse -Response $response
        
        return $processed
    }
    catch {
        Write-Error "Failed to process chat prompt: $_"
        return @{
            Message = "Error processing request: $_"
            Commands = @()
        }
    }
}

# Export functions
Export-ModuleMember -Function *