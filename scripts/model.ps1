# .\scripts\model.ps1

# Import utilities
Import-Module "$PSScriptRoot\utility.ps1"

# Model configuration
$global:ModelConfig = @{
    Path = ".\data\cudart-llama-bin-win-cu11.7\main.exe"
    MaxTokens = 2048
    Temperature = 0.7
    TopP = 0.9
    Context = 4096
    Threads = 4
}

# Model initialization
function Initialize-AIModel {
    try {
        # Check if model exists
        if (-not (Test-Path $global:ModelConfig.Path)) {
            throw "Model binary not found"
        }

        # Set environment variables
        $env:LLAMA_CUDA_UNIFIED_MEMORY = 1
        
        # Test model
        $testProcess = Start-Process -FilePath $global:ModelConfig.Path -ArgumentList "--help" -Wait -PassThru -NoNewWindow
        if ($testProcess.ExitCode -ne 0) {
            throw "Model test failed"
        }

        $global:TempVars.ModelLoaded = $true
        return $true
    }
    catch {
        Write-Error "Failed to initialize AI model: $_"
        $global:TempVars.ModelLoaded = $false
        return $false
    }
}

# Prompt handling
function Send-Prompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [hashtable]$Options = @{}
    )
    
    try {
        # Merge options with defaults
        $params = @{
            MaxTokens = $Options.MaxTokens ?? $global:ModelConfig.MaxTokens
            Temperature = $Options.Temperature ?? $global:ModelConfig.Temperature
            TopP = $Options.TopP ?? $global:ModelConfig.TopP
            Threads = $Options.Threads ?? $global:ModelConfig.Threads
        }

        # Build arguments
        $args = @(
            "--model", $global:ModelConfig.Path,
            "--ctx_size", $global:ModelConfig.Context,
            "--threads", $params.Threads,
            "--temp", $params.Temperature,
            "--top_p", $params.TopP,
            "--n_predict", $params.MaxTokens,
            "--prompt", $Prompt
        )

        # Run model
        $process = Start-Process -FilePath $global:ModelConfig.Path -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput ".\temp\response.txt"
        
        if ($process.ExitCode -ne 0) {
            throw "Model execution failed"
        }

        # Get response
        $response = Get-Content ".\temp\response.txt" -Raw
        return Format-ModelResponse $response
    }
    catch {
        Write-Error "Failed to process prompt: $_"
        return $null
    }
}

# Response processing
function Format-ModelResponse {
    param([string]$Response)
    
    # Remove any prompt echoing
    $Response = $Response -replace '^[^\n]+\n', ''
    
    # Clean up whitespace
    $Response = $Response.Trim()
    
    # Remove any special tokens
    $Response = $Response -replace '<\|.*?\|>', ''
    
    return $Response
}

# Context Management
class ConversationContext {
    [System.Collections.ArrayList]$Messages
    [int]$TokenCount
    [int]$MaxTokens
    [string]$SystemPrompt

    ConversationContext([int]$maxTokens = 4096) {
        $this.Messages = [System.Collections.ArrayList]::new()
        $this.TokenCount = 0
        $this.MaxTokens = $maxTokens
        $this.SystemPrompt = "You are an AI assistant helping with document organization and research."
    }

    [void]AddMessage([string]$Role, [string]$Content) {
        $tokens = $this.EstimateTokens($Content)
        while (($this.TokenCount + $tokens) -gt $this.MaxTokens -and $this.Messages.Count -gt 0) {
            $this.TokenCount -= $this.EstimateTokens($this.Messages[0].Content)
            $this.Messages.RemoveAt(0)
        }
        
        $this.Messages.Add(@{
            Role = $Role
            Content = $Content
            Timestamp = Get-Date
            Tokens = $tokens
        })
        $this.TokenCount += $tokens
    }

    [int]EstimateTokens([string]$Text) {
        # Rough estimation: ~4 chars per token
        return [Math]::Ceiling($Text.Length / 4)
    }

    [string]GetPrompt() {
        $prompt = $this.SystemPrompt + "`n`n"
        foreach ($msg in $this.Messages) {
            $prompt += "[$($msg.Role)]: $($msg.Content)`n"
        }
        return $prompt
    }
}

# Conversation Management
$global:CurrentContext = [ConversationContext]::new()

function Send-ContextualPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [hashtable]$Options = @{}
    )
    
    try {
        # Add to context
        $global:CurrentContext.AddMessage("user", $Prompt)

        # Get full prompt with context
        $fullPrompt = $global:CurrentContext.GetPrompt()

        # Send to model
        $response = Send-Prompt -Prompt $fullPrompt -Options $Options

        # Add response to context
        $global:CurrentContext.AddMessage("assistant", $response)

        return $response
    }
    catch {
        Write-Error "Failed to process contextual prompt: $_"
        return $null
    }
}

# Advanced Prompt Templates
$global:PromptTemplates = @{
    Summarize = @"
Please summarize the following content in a concise way:

{0}

Provide a summary that captures the main points while remaining clear and coherent.
"@
    
    Research = @"
Please research the following topic and provide key information:

Topic: {0}

Include:
1. Main points
2. Key facts
3. Relevant details
4. Sources if available
"@
    
    Organize = @"
Please help organize the following content into a structured format:

{0}

Organize this into:
1. Main topics
2. Subtopics
3. Key points
4. Related information
"@
}

function Get-FormattedPrompt {
    param(
        [string]$Template,
        [string]$Content
    )
    return $global:PromptTemplates[$Template] -f $Content
}

function Send-TemplatedPrompt {
    param(
        [string]$Template,
        [string]$Content,
        [hashtable]$Options = @{}
    )
    $prompt = Get-FormattedPrompt -Template $Template -Content $Content
    return Send-ContextualPrompt -Prompt $prompt -Options $Options
}

# Response Processing
function Format-ModelResponse {
    param(
        [string]$Response,
        [string]$Format = "text"
    )
    
    $cleaned = $Response.Trim()
    
    switch ($Format) {
        "text" { 
            return $cleaned 
        }
        "json" {
            try {
                $json = $cleaned | ConvertFrom-Json
                return $json
            }
            catch {
                Write-Error "Failed to parse JSON response"
                return $null
            }
        }
        "list" {
            return $cleaned -split "`n" | Where-Object { $_ -match '^\s*[\-\*]\s' }
        }
        default {
            return $cleaned
        }
    }
}

# Export functions
Export-ModuleMember -Function *