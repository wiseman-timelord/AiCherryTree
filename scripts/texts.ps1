# Text generation and processing module
# .\scripts\texts.ps1

# Import required modules
Import-Module "$PSScriptRoot\utility.ps1"
Import-Module "$PSScriptRoot\prompts.ps1"
Import-Module "$PSScriptRoot\model.ps1"

function Send-TextPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [hashtable]$Options = @{},
        [switch]$Stream,
        [switch]$AllowWebResearch
    )
    
    try {
        # Check model health
        if (-not (Test-ModelHealth -ModelType "Text")) {
            throw "Text model not initialized or unhealthy"
        }

        # Check if web research is needed
        if ($AllowWebResearch) {
            $needsResearch = Test-NeedsResearch -Prompt $Prompt
            
            if ($needsResearch) {
                $webResults = Get-WebResearch -Query $Prompt
                
                $Prompt = @"
Context from web research:
$webResults

Original prompt:
$Prompt
"@
            }
        }
        
        # Get model state
        $modelConfig = $global:ModelState.TextModel.Config
        
        # Prepare options
        $modelArgs = @{
            prompt = $Prompt
            temperature = $Options.Temperature ?? $modelConfig.Temperature
            top_p = $Options.TopP ?? $modelConfig.TopP
            context_size = $Options.ContextSize ?? $modelConfig.ContextSize
            batch_size = $Options.BatchSize ?? $modelConfig.BatchSize
            repeat_penalty = $Options.RepeatPenalty ?? $modelConfig.RepeatPenalty
            num_threads = $Options.NumThreads ?? $modelConfig.NumThreads
        }

        # Process through GGUF model
        $result = Invoke-GGUFModel @modelArgs -Stream:$Stream

        return $result
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

function Process-ChatResponse {
    param(
        [string]$Response,
        [scriptblock]$CommandHandler
    )
    
    try {
        $commands = Get-CommandFromResponse $Response
        $cleanResponse = Format-ResponseWithoutCommands $Response
        
        # Execute command handler if provided
        if ($CommandHandler -and $commands) {
            foreach ($command in $commands) {
                & $CommandHandler $command
            }
        }
        
        return @{
            Message = $cleanResponse
            Commands = $commands
        }
    }
    catch {
        Write-Error "Failed to process chat response: $_"
        return @{
            Message = "Error processing response: $_"
            Commands = @()
        }
    }
}

function Send-ChatPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [hashtable]$Context = @{},
        [hashtable]$Options = @{}
    )
    
    try {
        # Format prompt using prompts.ps1
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

# Export functions
Export-ModuleMember -Function *