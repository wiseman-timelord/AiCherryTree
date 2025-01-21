# AI prompt management and templates
# .\scripts\prompts.ps1

# Import required modules
Import-Module "$PSScriptRoot\utility.ps1"
Import-Module "$PSScriptRoot\texts.ps1"

# LLamaBox-specific chat templates
$global:LlamaTemplates = @{
    Default = @"
[INST]<<SYS>>
You are an AI assistant helping with a tree-based document system. Focus on organizing information, 
generating content, and providing clear responses. Keep node content under 2300 characters.
<</SYS>>

{0}
[/INST]
"@
    Research = @"
[INST]<<SYS>>
You are conducting research and analysis. Focus on extracting key information, organizing findings,
and identifying important patterns and relationships.
<</SYS>>

CONTEXT:
{0}

QUERY:
{1}
[/INST]
"@
    Content = @"
[INST]<<SYS>>
You are generating content for a document node. Keep content focused, well-organized, and under 2300 characters.
Consider the node's position in the document hierarchy.
<</SYS>>

TITLE: {0}
CONTEXT: {1}
REQUIREMENTS: {2}
[/INST]
"@
    ImagePrompt = @"
[INST]<<SYS>>
You are creating detailed image prompts. Focus on visual details, composition, and style.
Consider the type of image (Scene/Person/Item) and required dimensions.
<</SYS>>

DESCRIPTION: {0}
TYPE: {1}
STYLE REQUIREMENTS: {2}
[/INST]
"@
}

# Command markup for responses
$global:CommandMarkup = @{
    Start = "##COMMAND:"
    End = "##"
    Separator = ":"
}

function New-PromptContext {
    param(
        [hashtable]$Node = $null,
        [string]$Content = "",
        [hashtable]$Additional = @{}
    )
    
    $context = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Node = if ($Node) {
            @{
                Id = $Node.Id
                Title = $Node.Title
                ParentId = $Node.ParentId
            }
        } else { $null }
        Content = $Content
    }
    
    # Add additional context
    foreach ($key in $Additional.Keys) {
        $context[$key] = $Additional[$key]
    }
    
    return ($context | ConvertTo-Json -Compress)
}

function Format-LlamaPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,
        [string[]]$Parameters
    )
    
    try {
        # Get template
        $promptTemplate = $global:LlamaTemplates[$Template]
        if (-not $promptTemplate) {
            throw "Template not found: $Template"
        }
        
        # Format with parameters
        return [string]::Format($promptTemplate, $Parameters)
    }
    catch {
        Write-Error "Failed to format prompt: $_"
        return $null
    }
}

function New-ChatPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [hashtable]$Context = @{},
        [string]$Template = "Default"
    )
    
    try {
        # Create context string
        $contextStr = New-PromptContext -Node $Context.CurrentNode `
            -Content $Context.CurrentNodeContent `
            -Additional $Context
        
        # Format prompt using LLama template
        return Format-LlamaPrompt -Template $Template -Parameters @($contextStr, $Message)
    }
    catch {
        Write-Error "Failed to create chat prompt: $_"
        return $null
    }
}

function New-ContentPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Context = "",
        [hashtable]$Requirements = @{}
    )
    
    try {
        # Format requirements
        $reqStr = $Requirements.Keys | ForEach-Object {
            "$_: $($Requirements[$_])"
        } | Join-String -Separator "`n"
        
        # Create prompt
        return Format-LlamaPrompt -Template "Content" -Parameters @(
            $Title,
            $Context,
            $reqStr
        )
    }
    catch {
        Write-Error "Failed to create content prompt: $_"
        return $null
    }
}

function New-ImagePrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [string]$Type = "Scene",
        [hashtable]$Style = @{}
    )
    
    try {
        # Format style requirements
        $styleStr = $Style.Keys | ForEach-Object {
            "$_: $($Style[$_])"
        } | Join-String -Separator "`n"
        
        # Create prompt
        return Format-LlamaPrompt -Template "ImagePrompt" -Parameters @(
            $Description,
            $Type,
            $styleStr
        )
    }
    catch {
        Write-Error "Failed to create image prompt: $_"
        return $null
    }
}

function Get-CommandFromResponse {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Response
    )
    
    try {
        $commands = @()
        $pattern = "$($global:CommandMarkup.Start)([^$($global:CommandMarkup.End)]+)$($global:CommandMarkup.End)"
        $matches = [regex]::Matches($Response, $pattern)
        
        foreach ($match in $matches) {
            $parts = $match.Groups[1].Value -split $global:CommandMarkup.Separator
            if ($parts.Count -ge 2) {
                $commands += @{
                    Type = $parts[0].Trim()
                    Parameters = $parts[1..($parts.Count - 1)].Trim()
                    RawText = $match.Value
                }
            }
        }
        
        return $commands
    }
    catch {
        Write-Error "Failed to extract commands: $_"
        return @()
    }
}

function Format-ResponseWithoutCommands {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Response
    )
    
    try {
        $pattern = "$($global:CommandMarkup.Start)[^$($global:CommandMarkup.End)]+$($global:CommandMarkup.End)"
        return $Response -replace $pattern, ''
    }
    catch {
        Write-Error "Failed to format response: $_"
        return $Response
    }
}

function Process-ChatResponse {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Response
    )
    
    try {
        # Extract commands
        $commands = Get-CommandFromResponse -Response $Response
        
        # Clean response
        $message = Format-ResponseWithoutCommands -Response $Response
        
        # Validate message length
        if ($message.Length -gt 2300) {
            Write-Warning "Response exceeded character limit, truncating..."
            $message = $message.Substring(0, 2300)
        }
        
        return @{
            Message = $message.Trim()
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

# Token Management
function Format-TokenizedPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [int]$MaxTokens = 2048
    )
    
    try {
        # Get token count
        $tokenCount = Get-TokenCount -Text $Prompt
        
        # If within limit, return as-is
        if ($tokenCount -le $MaxTokens) {
            return $Prompt
        }
        
        # Calculate characters to keep (approximate)
        $charLimit = [math]::Floor($MaxTokens * 4 * 0.9) # 90% of theoretical max
        
        # Truncate content
        return $Prompt.Substring(0, $charLimit) + "`n[Content truncated to fit token limit]"
    }
    catch {
        Write-Error "Failed to format tokenized prompt: $_"
        return $Prompt
    }
}

# Export functions
Export-ModuleMember -Function * -Variable @('LlamaTemplates', 'CommandMarkup')