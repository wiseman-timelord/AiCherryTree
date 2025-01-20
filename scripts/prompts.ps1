# AI prompt management and templates
# .\scripts\prompts.ps1

# Import required modules
# Note: These modules are imported based on dependency order
Import-Module "$PSScriptRoot\utility.ps1"
Import-Module "$PSScriptRoot\texts.ps1"  # For Send-TextPrompt

# Template Categories
$global:PromptTemplates = @{
    System = @{
        Default = @"
You are assisting with a tree-based document management system. Your role is to:
1. Help organize and structure information
2. Generate appropriate content for nodes
3. Assist with research and data gathering
4. Provide clear, concise responses

Remember to:
- Keep responses within 2300 characters per node
- Generate appropriate content for the context
- Consider the hierarchical nature of the document tree
- Maintain consistent style and tone
"@
        Research = @"
You are conducting research on a specific topic. Your task is to:
1. Analyze the provided information
2. Extract key points and insights
3. Organize findings in a clear structure
4. Identify areas needing more detail

Focus on accuracy and relevance while maintaining clear organization.
"@
    }
    Chat = @{
        Default = @"
CONTEXT:
{0}

USER MESSAGE:
{1}

Respond naturally and execute any necessary commands using the ##COMMAND:Type:Parameters## format.
"@
        ResearchMode = @"
RESEARCH CONTEXT:
{0}

CURRENT QUERY:
{1}

Analyze the information and provide insights. Consider:
- Key findings
- Relationships between concepts
- Areas needing clarification
- Potential next steps
"@
    }
    Content = @{
        TextGeneration = @"
Create content for a node with the title: {0}

CONTEXT:
{1}

REQUIREMENTS:
- Keep within 2300 characters
- Maintain consistent style
- Include relevant details
- Consider the node's position in the tree

Generate appropriate content that fits these parameters.
"@
        ImageGeneration = @"
Create a detailed image description for: {0}

CONTEXT:
{1}

Consider:
- Required image type (Scene/Person/Item)
- Key visual elements
- Composition and layout
- Style and mood

Provide a clear, detailed description suitable for image generation.
"@
    }
    Analysis = @{
        NodeStructure = @"
Analyze the following node structure:

{0}

Consider:
- Organization and hierarchy
- Content completeness
- Logical flow
- Areas for improvement

Provide recommendations for optimization.
"@
        ContentQuality = @"
Review the following content:

{0}

Evaluate:
- Clarity and coherence
- Completeness
- Accuracy
- Style consistency

Suggest specific improvements if needed.
"@
    }
}

# Prompt Construction Functions
function New-SystemPrompt {
    param(
        [string]$Type = "Default",
        [hashtable]$Variables = @{}
    )
    
    try {
        $template = $global:PromptTemplates.System[$Type]
        if (-not $template) {
            throw "Invalid system prompt type: $Type"
        }
        
        $prompt = $template
        foreach ($key in $Variables.Keys) {
            $prompt = $prompt -replace "\{$key\}", $Variables[$key]
        }
        
        return $prompt
    }
    catch {
        Write-Error "Failed to create system prompt: $_"
        return $global:PromptTemplates.System.Default
    }
}

function New-ChatPrompt {
    param(
        [string]$Type = "Default",
        [string]$Context = "",
        [string]$Message,
        [hashtable]$Additional = @{}
    )
    
    try {
        $template = $global:PromptTemplates.Chat[$Type]
        if (-not $template) {
            throw "Invalid chat prompt type: $Type"
        }
        
        $prompt = [string]::Format($template, $Context, $Message)
        
        # Add any additional context
        foreach ($key in $Additional.Keys) {
            $prompt += "`n$key: $($Additional[$key])"
        }
        
        return $prompt
    }
    catch {
        Write-Error "Failed to create chat prompt: $_"
        return [string]::Format($global:PromptTemplates.Chat.Default, "", $Message)
    }
}

function New-ContentPrompt {
    param(
        [string]$Type,
        [string]$Title,
        [string]$Context,
        [hashtable]$Parameters = @{}
    )
    
    try {
        $template = $global:PromptTemplates.Content[$Type]
        if (-not $template) {
            throw "Invalid content prompt type: $Type"
        }
        
        $prompt = [string]::Format($template, $Title, $Context)
        
        # Add custom parameters
        foreach ($key in $Parameters.Keys) {
            $prompt += "`n$key: $($Parameters[$key])"
        }
        
        return $prompt
    }
    catch {
        Write-Error "Failed to create content prompt: $_"
        return $null
    }
}

function New-AnalysisPrompt {
    param(
        [string]$Type,
        [string]$Content,
        [hashtable]$Parameters = @{}
    )
    
    try {
        $template = $global:PromptTemplates.Analysis[$Type]
        if (-not $template) {
            throw "Invalid analysis prompt type: $Type"
        }
        
        $prompt = [string]::Format($template, $Content)
        
        # Add analysis parameters
        foreach ($key in $Parameters.Keys) {
            $prompt += "`n$key: $($Parameters[$key])"
        }
        
        return $prompt
    }
    catch {
        Write-Error "Failed to create analysis prompt: $_"
        return $null
    }
}

# Prompt Management Functions
function Add-PromptTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Template
    )
    
    try {
        if (-not $global:PromptTemplates[$Category]) {
            $global:PromptTemplates[$Category] = @{}
        }
        
        $global:PromptTemplates[$Category][$Name] = $Template
        return $true
    }
    catch {
        Write-Error "Failed to add prompt template: $_"
        return $false
    }
}

function Get-PromptTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    
    try {
        if (-not $global:PromptTemplates[$Category] -or 
            -not $global:PromptTemplates[$Category][$Name]) {
            throw "Template not found: $Category/$Name"
        }
        
        return $global:PromptTemplates[$Category][$Name]
    }
    catch {
        Write-Error "Failed to get prompt template: $_"
        return $null
    }
}

function Test-PromptTokens {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [int]$MaxTokens = 2048
    )
    
    try {
        # Approximate token count (characters / 4)
        $tokenCount = [math]::Ceiling($Prompt.Length / 4)
        return $tokenCount -le $MaxTokens
    }
    catch {
        Write-Error "Failed to test prompt tokens: $_"
        return $false
    }
}

# Command Processing
function Get-CommandFromResponse {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Response
    )
    
    try {
        $commands = @()
        $pattern = '##COMMAND:([^#]+)##'
        $matches = [regex]::Matches($Response, $pattern)
        
        foreach ($match in $matches) {
            $parts = $match.Groups[1].Value -split ':'
            if ($parts.Count -ge 2) {
                $commands += @{
                    Type = $parts[0]
                    Parameters = $parts[1..($parts.Count - 1)]
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
        return $Response -replace '##COMMAND:[^#]+##', ''
    }
    catch {
        Write-Error "Failed to format response: $_"
        return $Response
    }
}

# Export functions
Export-ModuleMember -Function *
# Compatibility Functions (Moved from texts.ps1)
function Format-ChatPrompt {
    param(
        [string]$UserMessage,
        [hashtable]$Context = @{},
        [string]$SystemPrompt = ""
    )
    
    # Convert from old format to new
    $type = if ($Context.ResearchResults) { "ResearchMode" } else { "Default" }
    $contextStr = Format-ContextString $Context
    return New-ChatPrompt -Type $type -Context $contextStr -Message $UserMessage
}

function Send-ChatPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [hashtable]$Context = @{},
        [hashtable]$Options = @{}
    )
    
    try {
        $prompt = Format-ChatPrompt -UserMessage $Message -Context $Context
        
        $defaultOptions = @{
            Temperature = 0.7
            MaxTokens = 2000
            TopP = 0.95
        }
        
        $finalOptions = $defaultOptions + $Options
        
        $response = Send-TextPrompt -Prompt $prompt -Options $finalOptions
        return Process-ChatResponse -Response $response
    }
    catch {
        Write-Error "Failed to process chat prompt: $_"
        return @{
            Message = "Error processing request: $_"
            Commands = @()
        }
    }
}

# Helper Functions
function Format-ContextString {
    param([hashtable]$Context)
    
    $contextParts = @()
    
    if ($Context.CurrentNode) {
        $contextParts += "Current Node: $($Context.CurrentNode.Title)"
        if ($Context.CurrentNodeContent) {
            $contextParts += "Content: $($Context.CurrentNodeContent)"
        }
    }
    
    if ($Context.ResearchResults) {
        $contextParts += "Research Results:`n$($Context.ResearchResults)"
    }
    
    if ($Context.LastCommand) {
        $contextParts += "Last Command: $($Context.LastCommand | ConvertTo-Json)"
    }
    
    return $contextParts -join "`n`n"
}

Export-ModuleMember -Function *
# Image Analysis Functions (Moved from images.ps1)
function Get-ContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    
    $prompt = New-ContentPrompt -Type "ImageGeneration" -Title "Content Type Analysis" -Context $Description `
        -Parameters @{
            Instructions = "Analyze this description and classify it as Scene, Person, or Item. Respond with only one word."
        }
    
    $result = Send-TextPrompt -Prompt $prompt -Options @{
        Temperature = 0.1
        MaxTokens = 10
    }
    
    $type = $result.Trim()
    if ($type -in @("Scene", "Person", "Item")) {
        return $type
    }
    
    return "Scene"  # Default to Scene if unclear
}

Export-ModuleMember -Function *
Export-ModuleMember -Variable PromptTemplates