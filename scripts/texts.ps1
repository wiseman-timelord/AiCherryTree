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

function New-TextNode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    
    try {
        $hash = Get-RandomHash
        $textPath = Join-Path $global:PATHS.TextsDir "$hash.txt"
        Set-Content -Path $textPath -Value $Content -Force
        return $hash
    }
    catch {
        Write-Error "Failed to create text node: $_"
        return $null
    }
}

function Test-ContentSafety {
    param([string]$Content)
    
    try {
        # Basic content validation patterns
        $patterns = @(
            '(rm|del|remove)\s+-rf?\s+[/*]',  # Dangerous commands
            'system\s*\(',                     # System calls
            'exec\s*\(',                       # Code execution
            '<script',                         # Script injection
            '(?<!\\)%[0-9a-fA-F]{2}'          # URL encoding
        )
        
        foreach ($pattern in $patterns) {
            if ($Content -match $pattern) {
                return $false
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Content validation failed: $_"
        return $false
    }
}

function Format-NodeContent {
    param([string]$Content)
    
    try {
        # Basic content formatting
        $formatted = $Content -replace '\r\n', "`n"           # Normalize line endings
        $formatted = $formatted -replace '\n{3,}', "`n`n"     # Max double line breaks
        $formatted = $formatted.Trim()                        # Trim whitespace
        
        return $formatted
    }
    catch {
        Write-Error "Content formatting failed: $_"
        return $Content
    }
}

# Text Node Management
function New-TextNode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [hashtable]$Options = @{}
    )
    
    try {
        # Validate and format content
        if (-not (Test-ContentSafety -Content $Content)) {
            throw "Content failed safety validation"
        }
        
        $formattedContent = Format-NodeContent -Content $Content
        
        # Generate unique hash for file
        $hash = Get-RandomHash
        $textPath = Join-Path $global:PATHS.TextsDir "$hash.txt"
        
        # Ensure directory exists
        $directory = Split-Path $textPath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Acquire file lock
        if (-not (Lock-File -Path $textPath -Owner "TextCreator")) {
            throw "Could not acquire file lock"
        }
        
        try {
            # Save content
            Set-Content -Path $textPath -Value $formattedContent -Force
            
            # Verify content was saved correctly
            $savedContent = Get-Content -Path $textPath -Raw
            if ($savedContent -ne $formattedContent) {
                throw "Content verification failed"
            }
            
            # Create metadata if enabled
            if ($Options.CreateMetadata) {
                $metadataPath = "$textPath.meta"
                $metadata = @{
                    Title = $Title
                    Created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Modified = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    CharCount = $formattedContent.Length
                    WordCount = ($formattedContent -split '\s+').Count
                    Hash = (Get-FileHash $textPath -Algorithm SHA256).Hash
                }
                $metadata | ConvertTo-Json | Set-Content $metadataPath -Force
            }
            
            return $hash
        }
        finally {
            # Release file lock
            Unlock-File -Path $textPath
        }
    }
    catch {
        Write-Error "Failed to create text node: $_"
        return $null
    }
}

function Test-ContentSafety {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [hashtable]$AdditionalPatterns = @{}
    )
    
    try {
        # Core dangerous patterns
        $dangerousPatterns = @{
            SystemCommands = '(rm|del|remove)\s+-rf?\s+[/*]'
            SystemCalls = '(system|exec|eval|invoke)\s*\('
            ScriptInjection = '<script|javascript:|data:text/javascript'
            SQLInjection = "('\s*(or|and)\s*'?\d)|(-{2})|(/\*)|(\b(union|select|insert|update|delete|drop)\b)"
            URLEncoding = '(?<!\\)%[0-9a-fA-F]{2}'
            PathTraversal = '\.\./|\.\.\\'
            ControlChars = '[\x00-\x08\x0B\x0C\x0E-\x1F]'
            Base64Code = '[a-zA-Z0-9+/]{64,}'
        }
        
        # Add additional patterns if provided
        foreach ($key in $AdditionalPatterns.Keys) {
            $dangerousPatterns[$key] = $AdditionalPatterns[$key]
        }
        
        # Check against patterns
        foreach ($pattern in $dangerousPatterns.Values) {
            if ($Content -match $pattern) {
                Write-Warning "Content matched dangerous pattern: $($dangerousPatterns.GetEnumerator() | Where-Object { $_.Value -eq $pattern } | Select-Object -ExpandProperty Key)"
                return $false
            }
        }
        
        # Length validation
        if ($Content.Length -gt 2300) {  # Maximum content length
            Write-Warning "Content exceeds maximum length of 2300 characters"
            return $false
        }
        
        # Basic structure validation
        $lines = $Content -split '\n'
        if ($lines.Count -gt 100) {  # Maximum line count
            Write-Warning "Content exceeds maximum line count of 100"
            return $false
        }
        
        foreach ($line in $lines) {
            if ($line.Length -gt 200) {  # Maximum line length
                Write-Warning "Content contains line exceeding maximum length of 200 characters"
                return $false
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Content safety check failed: $_"
        return $false
    }
}

function Format-NodeContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [hashtable]$Options = @{
            TrimWhitespace = $true
            NormalizeLineEndings = $true
            MaxConsecutiveNewlines = 2
            IndentSpaces = 4
            PreserveMarkdown = $true
        }
    )
    
    try {
        $formatted = $Content
        
        # Normalize line endings
        if ($Options.NormalizeLineEndings) {
            $formatted = $formatted -replace '\r\n?', "`n"
        }
        
        # Handle markdown if enabled
        if ($Options.PreserveMarkdown) {
            # Preserve code blocks before processing
            $codeBlocks = [System.Collections.ArrayList]::new()
            $formatted = $formatted -replace '```[\s\S]*?```', {
                $codeBlocks.Add($_.Value) | Out-Null
                "CODE_BLOCK_${($codeBlocks.Count - 1)}"
            }
        }
        
        # Basic formatting
        if ($Options.TrimWhitespace) {
            # Trim each line
            $lines = $formatted -split '\n' | ForEach-Object { $_.TrimEnd() }
            $formatted = $lines -join "`n"
            
            # Trim start/end
            $formatted = $formatted.Trim()
        }
        
        # Limit consecutive newlines
        if ($Options.MaxConsecutiveNewlines -gt 0) {
            $pattern = "\n{$($Options.MaxConsecutiveNewlines + 1),}"
            $replacement = "`n" * $Options.MaxConsecutiveNewlines
            $formatted = $formatted -replace $pattern, $replacement
        }
        
        # Handle indentation
        if ($Options.IndentSpaces -gt 0) {
            # Replace tabs with spaces
            $formatted = $formatted -replace '\t', (' ' * $Options.IndentSpaces)
        }
        
        # Restore code blocks if markdown was preserved
        if ($Options.PreserveMarkdown) {
            for ($i = 0; $i -lt $codeBlocks.Count; $i++) {
                $formatted = $formatted -replace "CODE_BLOCK_$i", $codeBlocks[$i]
            }
        }
        
        return $formatted
    }
    catch {
        Write-Error "Content formatting failed: $_"
        return $Content  # Return original content on error
    }
}

function Get-TextMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TextHash
    )
    
    try {
        $textPath = Join-Path $global:PATHS.TextsDir "$TextHash.txt"
        $metadataPath = "$textPath.meta"
        
        if (-not (Test-Path $metadataPath)) {
            # Generate metadata if it doesn't exist
            $content = Get-Content $textPath -Raw
            $metadata = @{
                Created = (Get-Item $textPath).CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                Modified = (Get-Item $textPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                CharCount = $content.Length
                WordCount = ($content -split '\s+').Count
                Hash = (Get-FileHash $textPath -Algorithm SHA256).Hash
            }
            
            $metadata | ConvertTo-Json | Set-Content $metadataPath -Force
            return $metadata
        }
        
        return Get-Content $metadataPath -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        Write-Error "Failed to get text metadata: $_"
        return $null
    }
}

function Update-TextContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TextHash,
        [Parameter(Mandatory = $true)]
        [string]$NewContent
    )
    
    try {
        # Validate new content
        if (-not (Test-ContentSafety -Content $NewContent)) {
            throw "New content failed safety validation"
        }
        
        # Format content
        $formattedContent = Format-NodeContent -Content $NewContent
        
        $textPath = Join-Path $global:PATHS.TextsDir "$TextHash.txt"
        if (-not (Test-Path $textPath)) {
            throw "Text file not found"
        }
        
        # Create backup
        $backupPath = "$textPath.bak"
        Copy-Item $textPath $backupPath -Force
        
        # Acquire file lock
        if (-not (Lock-File -Path $textPath -Owner "TextUpdater")) {
            throw "Could not acquire file lock"
        }
        
        try {
            # Update content
            Set-Content -Path $textPath -Value $formattedContent -Force
            
            # Update metadata
            $metadataPath = "$textPath.meta"
            if (Test-Path $metadataPath) {
                $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json -AsHashtable
                $metadata.Modified = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $metadata.CharCount = $formattedContent.Length
                $metadata.WordCount = ($formattedContent -split '\s+').Count
                $metadata.Hash = (Get-FileHash $textPath -Algorithm SHA256).Hash
                $metadata | ConvertTo-Json | Set-Content $metadataPath -Force
            }
            
            # Remove backup after successful update
            Remove-Item $backupPath -Force
            return $true
        }
        catch {
            # Restore from backup on error
            Copy-Item $backupPath $textPath -Force
            throw
        }
        finally {
            # Release file lock
            Unlock-File -Path $textPath
        }
    }
    catch {
        Write-Error "Failed to update text content: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-TextNode',
    'Test-ContentSafety',
    'Format-NodeContent',
    'Get-TextMetadata',
    'Update-TextContent'
)