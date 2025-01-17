# .\scripts\internet.ps1

# Import utilities
Import-Module "$PSScriptRoot\utility.ps1"

# Configuration
$global:WebConfig = @{
    UserAgent = "Mozilla/5.0 LightStone/1.0"
    TimeoutSec = 30
    MaxRetries = 3
    CacheDuration = 3600
}

# Simple functions
function Test-InternetConnection {
    try {
        $response = Invoke-WebRequest -Uri "http://www.google.com" -Method HEAD -TimeoutSec 5
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

# Enhance Get-SafeWebContent
function Get-SafeWebContent {
    param(
        [string]$Url,
        [switch]$Raw,
        [int]$Timeout = 30
    )
    try {
        $response = Invoke-WebRequest -Uri $Url -UserAgent $global:WebConfig.UserAgent -TimeoutSec $Timeout
        if ($Raw) {
            return $response.Content
        }
        # Basic HTML cleaning
        $content = $response.Content -replace '<script.*?</script>', '' -replace '<style.*?</style>', ''
        return $content -replace '<[^>]+>', '' -replace '&nbsp;', ' ' -replace '\s+', ' '
    }
    catch {
        Write-Error "Failed to fetch content: $_"
        return $null
    }
}

# File operations
# Enhance Save-WebImage
function Save-WebImage {
    param(
        [string]$Url,
        [string]$OutputPath = $null
    )
    try {
        if (-not $OutputPath) {
            $extension = [System.IO.Path]::GetExtension($Url)
            if (-not $extension) { $extension = ".jpg" }
            $OutputPath = ".\temp\$(Get-RandomHash)$extension"
        }
        
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath
        return (Optimize-Image -InputPath $OutputPath)
    }
    catch {
        Write-Error "Failed to download image: $_"
        return $null
    }
}

# Placeholder functions
function Get-WebResearch {
    param(
        [string]$Query,
        [int]$MaxResults = 5
    )
    # TODO: Implement web research
    throw [NotImplementedException]::new()
}

function Get-WebPageSummary {
    param([string]$Url)
    # TODO: Implement page summarization
    throw [NotImplementedException]::new()
}

function Update-WebCache {
    # TODO: Implement cache management
    throw [NotImplementedException]::new()
}

# Research Functions
function Start-Research {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Topic,
        [int]$MaxResults = 5,
        [int]$MaxDepth = 2
    )
    
    try {
        # Initialize results
        $results = @{
            Topic = $Topic
            Sources = @()
            Summary = ""
            Details = @()
            Images = @()
            Timestamp = Get-Date
        }

        # Get search results
        $searchUrls = Search-Topic -Topic $Topic -MaxResults $MaxResults
        
        # Process each URL
        foreach ($url in $searchUrls) {
            if (Test-ValidSource -Url $url) {
                $content = Get-SafeWebContent -Url $url
                if ($content) {
                    # Extract relevant information
                    $info = Get-ContentSummary -Content $content
                    
                    # Add to results
                    $results.Sources += $url
                    $results.Details += $info
                    
                    # Get images if available
                    $images = Get-ContentImages -Content $content -Url $url
                    $results.Images += $images | Select-Object -First 3
                }
            }
        }

        # Generate summary using AI
        $allDetails = $results.Details -join "`n`n"
        $results.Summary = Send-TemplatedPrompt -Template "Summarize" -Content $allDetails

        return $results
    }
    catch {
        Write-Error "Research failed: $_"
        return $null
    }
}

function Search-Topic {
    param(
        [string]$Topic,
        [int]$MaxResults = 5
    )
    try {
        $searchUrl = "https://www.google.com/search?q=$([Uri]::EscapeDataString($Topic))"
        $content = Get-SafeWebContent -Url $searchUrl
        
        # Extract URLs using regex
        $urlPattern = 'href="(https?://[^"]+)"'
        $urls = [regex]::Matches($content, $urlPattern) | 
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { Test-ValidSource -Url $_ } |
            Select-Object -First $MaxResults
        
        return $urls
    }
    catch {
        Write-Error "Search failed: $_"
        return @()
    }
}

function Get-ContentSummary {
    param(
        [string]$Content,
        [int]$MaxLength = 1000
    )
    try {
        # Clean HTML
        $text = $Content -replace '<script.*?</script>', '' -replace '<style.*?</style>', ''
        $text = $text -replace '<[^>]+>', ' ' -replace '&nbsp;', ' '
        $text = $text -replace '\s+', ' '
        
        # Extract main content
        $paragraphs = $text -split '[\.\n]' |
            Where-Object { $_.Length -gt 50 } |
            Select-Object -First 10
        
        $summary = $paragraphs -join ". "
        if ($summary.Length -gt $MaxLength) {
            $summary = $summary.Substring(0, $MaxLength) + "..."
        }
        
        return $summary
    }
    catch {
        Write-Error "Summary extraction failed: $_"
        return ""
    }
}

function Get-ContentImages {
    param(
        [string]$Content,
        [string]$BaseUrl
    )
    try {
        # Extract image URLs
        $imgPattern = 'src="([^"]+\.(jpg|jpeg|png|gif))"'
        $images = [regex]::Matches($content, $imgPattern) |
            ForEach-Object { $_.Groups[1].Value }
        
        # Convert relative URLs to absolute
        $images = $images | ForEach-Object {
            if ($_.StartsWith("/")) {
                $baseUri = [Uri]$BaseUrl
                "https://$($baseUri.Host)$_"
            }
            else {
                $_
            }
        }
        
        return $images
    }
    catch {
        Write-Error "Image extraction failed: $_"
        return @()
    }
}

function Test-ValidSource {
    param([string]$Url)
    try {
        # List of blocked domains
        $blockedDomains = @(
            "youtube.com",
            "facebook.com",
            "twitter.com",
            "instagram.com"
        )
        
        # Parse URL
        $uri = [Uri]$Url
        
        # Check domain
        $domain = $uri.Host -replace '^www\.'
        if ($blockedDomains -contains $domain) {
            return $false
        }
        
        # Check file type
        $extension = [System.IO.Path]::GetExtension($uri.LocalPath)
        if ($extension -in @(".pdf", ".doc", ".docx", ".xls", ".xlsx")) {
            return $false
        }
        
        return $true
    }
    catch {
        return $false
    }
}


# Export functions
Export-ModuleMember -Function *