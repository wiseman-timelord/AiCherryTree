# Update internet.ps1

# Import required modules
Import-Module "$PSScriptRoot\utility.ps1"
Import-Module "$PSScriptRoot\model.ps1"

# Web Research Configuration
$global:WebConfig = @{
    UserAgent = "Mozilla/5.0 LightStone/1.0"
    TimeoutSec = 30
    MaxRetries = 3
    MaxConcurrent = 5
    CacheDuration = [TimeSpan]::FromHours(24)
    BlockedDomains = @(
        "facebook.com",
        "twitter.com",
        "instagram.com",
        "tiktok.com",
        "pinterest.com"
    )
    AllowedFileTypes = @(
        ".html",
        ".htm",
        ".txt",
        ".pdf",
        ".doc",
        ".docx"
    )
}

# Web Research Pipeline
class WebResearchPipeline {
    [string]$Query
    [int]$MaxResults
    [int]$MaxDepth
    [hashtable]$Options
    [object]$ProgressCallback

    WebResearchPipeline([string]$query, [int]$maxResults, [int]$maxDepth, [hashtable]$options) {
        $this.Query = $query
        $this.MaxResults = $maxResults
        $this.MaxDepth = $maxDepth
        $this.Options = $options
    }

    [void]SetProgressCallback([object]$callback) {
        $this.ProgressCallback = $callback
    }

    [hashtable]Process() {
        try {
            $this.ReportProgress(0, "Starting research")

            # Step 1: Check cache
            $this.ReportProgress(10, "Checking cache")
            $cached = Get-WebCache -Query $this.Query
            if ($cached) {
                $this.ReportProgress(100, "Retrieved from cache")
                return $cached
            }

            # Step 2: Search for sources
            $this.ReportProgress(20, "Searching for sources")
            $sources = $this.SearchSources()
            if (-not $sources -or $sources.Count -eq 0) {
                throw "No valid sources found"
            }

            # Step 3: Gather content
            $this.ReportProgress(40, "Gathering content")
            $content = $this.GatherContent($sources)

            # Step 4: Analyze content
            $this.ReportProgress(60, "Analyzing content")
            $analysis = $this.AnalyzeContent($content)

            # Step 5: Validate and filter
            $this.ReportProgress(80, "Validating results")
            $results = $this.ValidateResults($analysis)

            # Step 6: Cache results
            $this.ReportProgress(90, "Caching results")
            Add-WebCache -Query $this.Query -Results $results

            $this.ReportProgress(100, "Research complete")
            return $results
        }
        catch {
            Write-Error "Research pipeline failed: $_"
            return @{
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }

    hidden [array]SearchSources() {
        $sources = @()
        $searchers = @(
            { param($q) Search-GoogleWeb -Query $q },
            { param($q) Search-BingWeb -Query $q },
            { param($q) Search-ScholarWeb -Query $q }
        )

        foreach ($searcher in $searchers) {
            try {
                $results = & $searcher $this.Query
                $sources += $results | Where-Object { Test-ValidSource $_ }
                if ($sources.Count -ge $this.MaxResults) {
                    break
                }
            }
            catch {
                Write-Warning "Search error: $_"
                continue
            }
        }

        return $sources | Select-Object -First $this.MaxResults
    }

    hidden [array]GatherContent([array]$sources) {
        $content = @()
        $concurrent = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
        $tasks = @()

        foreach ($source in $sources) {
            $tasks += Start-ThreadJob -ScriptBlock {
                param($url, $config)
                try {
                    $content = Get-SafeWebContent -Url $url -UserAgent $config.UserAgent -TimeoutSec $config.TimeoutSec
                    if ($content) {
                        @{
                            Url = $url
                            Content = $content
                            Success = $true
                        }
                    }
                }
                catch {
                    @{
                        Url = $url
                        Error = $_.Exception.Message
                        Success = $false
                    }
                }
            } -ArgumentList $source, $global:WebConfig
        }

        Wait-Job $tasks | Receive-Job | ForEach-Object {
            if ($_.Success) {
                $content += $_
            }
        }

        return $content
    }

    hidden [hashtable]AnalyzeContent([array]$content) {
        $analysis = @{
            Summary = ""
            KeyPoints = @()
            Sources = @()
            Relevance = @{}
        }

        # Prepare content for analysis
        $combinedContent = $content | ForEach-Object {
            "Source: $($_.Url)`n$($_.Content)"
        } | Join-String -Separator "`n`n"

        # Use AI model for analysis
        $analysisPrompt = @"
Analyze the following content and provide:
1. A brief summary
2. Key points (max 5)
3. Relevance score (0-100)

Content:
$combinedContent
"@

        $result = Send-TextPrompt -Prompt $analysisPrompt -Options @{
            Temperature = 0.3
            MaxTokens = 1000
        }

        if ($result) {
            # Parse AI response
            $parts = $result -split "`n"
            $analysis.Summary = ($parts | Where-Object { $_ -match "^Summary:" })[0] -replace "^Summary: ", ""
            $analysis.KeyPoints = $parts | Where-Object { $_ -match "^\d+\. " } | ForEach-Object { $_ -replace "^\d+\. ", "" }
            
            # Calculate relevance
            foreach ($item in $content) {
                $relevanceScore = [int]($parts | Where-Object { $_ -match "Relevance.*: .*$($item.Url)" } | 
                    ForEach-Object { $_ -match "\d+" | ForEach-Object { $matches[0] } })
                $analysis.Relevance[$item.Url] = $relevanceScore
            }
        }

        $analysis.Sources = $content | Where-Object { $analysis.Relevance[$_.Url] -gt 50 }
        return $analysis
    }

    hidden [hashtable]ValidateResults([hashtable]$analysis) {
        # Filter and structure results
        $results = @{
            Query = $this.Query
            Timestamp = Get-Date
            Summary = $analysis.Summary
            KeyPoints = $analysis.KeyPoints | Where-Object { $_ }
            Sources = $analysis.Sources | ForEach-Object {
                @{
                    Url = $_.Url
                    Relevance = $analysis.Relevance[$_.Url]
                    Title = Get-WebPageTitle $_.Content
                    Excerpt = Get-ContentExcerpt $_.Content
                }
            }
            RawContent = $analysis.Sources
        }

        # Validate required fields
        if (-not $results.Summary -or $results.KeyPoints.Count -eq 0) {
            throw "Invalid analysis results"
        }

        return $results
    }

    hidden [void]ReportProgress([int]$progress, [string]$status) {
        if ($this.ProgressCallback) {
            & $this.ProgressCallback $progress $status
        }
    }
}

# Web Search Functions
function Search-GoogleWeb {
    param([string]$Query)
    
    try {
        $encodedQuery = [Uri]::EscapeDataString($Query)
        $url = "https://www.google.com/search?q=$encodedQuery"
        
        $content = Get-SafeWebContent -Url $url
        if (-not $content) { return @() }
        
        # Extract URLs
        $pattern = 'href="(?<url>https?://[^"]+)"'
        $matches = [regex]::Matches($content, $pattern)
        
        return $matches | ForEach-Object { $_.Groups['url'].Value } |
            Where-Object { Test-ValidSource $_ }
    }
    catch {
        Write-Error "Google search failed: $_"
        return @()
    }
}

function Search-BingWeb {
    param([string]$Query)
    
    try {
        $encodedQuery = [Uri]::EscapeDataString($Query)
        $url = "https://www.bing.com/search?q=$encodedQuery"
        
        $content = Get-SafeWebContent -Url $url
        if (-not $content) { return @() }
        
        # Extract URLs
        $pattern = 'href="(?<url>https?://[^"]+)"'
        $matches = [regex]::Matches($content, $pattern)
        
        return $matches | ForEach-Object { $_.Groups['url'].Value } |
            Where-Object { Test-ValidSource $_ }
    }
    catch {
        Write-Error "Bing search failed: $_"
        return @()
    }
}

function Search-ScholarWeb {
    param([string]$Query)
    
    try {
        $encodedQuery = [Uri]::EscapeDataString($Query)
        $url = "https://scholar.google.com/scholar?q=$encodedQuery"
        
        $content = Get-SafeWebContent -Url $url
        if (-not $content) { return @() }
        
        # Extract URLs
        $pattern = 'href="(?<url>https?://[^"]+\.pdf)"'
        $matches = [regex]::Matches($content, $pattern)
        
        return $matches | ForEach-Object { $_.Groups['url'].Value } |
            Where-Object { Test-ValidSource $_ }
    }
    catch {
        Write-Error "Scholar search failed: $_"
        return @()
    }
}

# Content Processing Functions
function Get-WebPageTitle {
    param([string]$Content)
    
    try {
        if ($Content -match '<title>(.*?)</title>') {
            return $matches[1] -replace '<[^>]+>', '' -replace '\s+', ' '
        }
        return ""
    }
    catch {
        return ""
    }
}

function Get-ContentExcerpt {
    param(
        [string]$Content,
        [int]$MaxLength = 200
    )
    
    try {
        # Clean HTML
        $text = $Content -replace '<script.*?</script>', '' -replace '<style.*?</style>', ''
        $text = $text -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '\s+', ' '
        
        # Get first substantial paragraph
        $paragraphs = $text -split '\n' | Where-Object { $_.Length -gt 50 }
        if ($paragraphs) {
            $excerpt = $paragraphs[0]
            if ($excerpt.Length -gt $MaxLength) {
                $excerpt = $excerpt.Substring(0, $MaxLength) + "..."
            }
            return $excerpt
        }
        return ""
    }
    catch {
        return ""
    }
}

# Cache Management
function Get-WebCache {
    param([string]$Query)
    
    try {
        $cacheFile = Join-Path $global:PATHS.TempDir "web_cache.json"
        if (-not (Test-Path $cacheFile)) {
            return $null
        }
        
        $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $hash = Get-StringHash $Query
        
        $entry = $cache.Queries[$hash]
        if (-not $entry) {
            return $null
        }
        
        # Check age
        $age = [DateTime]::Now - [DateTime]::Parse($entry.Timestamp)
        if ($age -gt $global:WebConfig.CacheDuration) {
            return $null
        }
        
        return $entry.Results
    }
    catch {
        Write-Error "Cache retrieval failed: $_"
        return $null
    }
}

function Add-WebCache {
    param(
        [string]$Query,
        [hashtable]$Results
    )
    
    try {
        $cacheFile = Join-Path $global:PATHS.TempDir "web_cache.json"
        
        # Load or create cache
        if (Test-Path $cacheFile) {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        }
        else {
            $cache = @{
                Version = "1.0"
                Queries = @{}
            }
        }
        
        # Add entry
        $hash = Get-StringHash $Query
        $cache.Queries[$hash] = @{
            Query = $Query
            Results = $Results
            Timestamp = (Get-Date -Format "o")
        }
        
        # Save cache
        $cache | ConvertTo-Json -Depth 10 | Set-Content $cacheFile
        return $true
    }
    catch {
        Write-Error "Cache update failed: $_"
        return $false
    }
}

# Main Research Function
function Start-WebResearch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        [int]$MaxResults = 5,
        [int]$MaxDepth = 2,
        [hashtable]$Options = @{}
    )
    
    try {
        # Create pipeline
        $pipeline = [WebResearchPipeline]::new($Query, $MaxResults, $MaxDepth, $Options)
        
        # Set progress callback if UI is available
        if ($global:MainWindow.ProgressManager) {
            $taskId = $global:MainWindow.ProgressManager.StartTask("Researching: $Query")
            $pipeline.SetProgressCallback({
                param($progress, $status)
                $global:MainWindow.ProgressManager.UpdateTask($taskId, $progress, $status)
            })
        }
        
        # Process pipeline
        $result = $pipeline.Process()
        
        # Complete progress task if used
        if ($taskId) {
            $global:MainWindow.ProgressManager.CompleteTask($taskId)
        }
        
        return $result
    }
    catch {
        Write-Error "Research failed: $_"
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Get-SafeWebContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [string]$UserAgent = $global:WebConfig.UserAgent,
        [int]$TimeoutSec = $global:WebConfig.TimeoutSec,
        [switch]$Raw
    )
    
    try {
        # Validate URL
        if (-not (Test-ValidSource -Url $Url)) {
            throw "Invalid or blocked URL"
        }

        # Setup request
        $webClient = [System.Net.WebClient]::new()
        $webClient.Headers.Add("User-Agent", $UserAgent)
        $webClient.Encoding = [System.Text.Encoding]::UTF8

        # Download with timeout
        $task = $webClient.DownloadStringTaskAsync($Url)
        if (-not (Wait-Task -Task $task -TimeoutSec $TimeoutSec)) {
            throw "Request timed out"
        }

        $content = $task.Result

        if (-not $Raw) {
            # Clean content
            $content = $content -replace '<script.*?</script>', ''
            $content = $content -replace '<style.*?</style>', ''
            $content = $content -replace '<!--.*?-->', ''
            if (-not $Raw) {
                $content = $content -replace '[\r\n]+', "`n"
                $content = $content -replace '\s{2,}', ' '
            }
        }

        return $content
    }
    catch {
        Write-Error "Failed to fetch content: $_"
        return $null
    }
    finally {
        if ($webClient) {
            $webClient.Dispose()
        }
    }
}

function Test-ValidSource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )
    
    try {
        # Parse URL
        $uri = [System.Uri]::new($Url)
        
        # Check protocol
        if ($uri.Scheme -notin @('http', 'https')) {
            return $false
        }
        
        # Check blocked domains
        $domain = $uri.Host -replace '^www\.', ''
        if ($domain -in $global:WebConfig.BlockedDomains) {
            return $false
        }
        
        # Check file extension
        $extension = [System.IO.Path]::GetExtension($uri.LocalPath).ToLower()
        if ($extension -and $extension -notin $global:WebConfig.AllowedFileTypes) {
            return $false
        }

        # Additional checks
        if ($uri.Host -match '\.onion$') { return $false }  # Tor domains
        if ($uri.Host -match '^(?:\d{1,3}\.){3}\d{1,3}$') { return $false }  # IP addresses
        if ($uri.Fragment) { return $false }  # No fragment identifiers
        if ($uri.Query -match '(password|token|key)=') { return $false }  # Sensitive parameters
        
        return $true
    }
    catch {
        return $false
    }
}

function Wait-Task {
    param(
        [Parameter(Mandatory = $true)]
        [System.Threading.Tasks.Task]$Task,
        [int]$TimeoutSec = 30
    )
    
    try {
        $timeout = [TimeSpan]::FromSeconds($TimeoutSec)
        return $Task.Wait($timeout)
    }
    catch {
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Start-WebResearch',
    'Get-SafeWebContent',
    'Test-ValidSource'
) -Variable 'WebConfig'