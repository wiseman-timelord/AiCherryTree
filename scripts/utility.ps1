# .\scripts\utility.ps1

# Import required modules
using namespace System.Security.Cryptography

# Simple utility functions
function Get-RandomHash {
    $bytes = [byte[]]::new(4)
    $rng = [RNGCryptoServiceProvider]::new()
    $rng.GetBytes($bytes)
    return ([Convert]::ToHexString($bytes)).ToLower()
}

function Test-PathExists {
    param([string]$Path)
    return Test-Path $Path
}

function Remove-TempFiles {
    Get-ChildItem ".\temp" | Remove-Item -Force -Recurse
}

# File operations
function New-TextNode {
    param(
        [string]$Content,
        [string]$Title
    )
    $hash = Get-RandomHash
    $filePath = ".\foliage\texts\$hash.txt"
    Set-Content -Path $filePath -Value $Content
    return @{
        Hash = $hash
        Title = $Title
        Path = $filePath
    }
}

function Save-ImageFile {
    param([string]$Path)
    # TODO: Implement image processing and saving
    throw [NotImplementedException]::new()
}

# Tree operations
function New-TreeNode {
    param(
        [string]$Title,
        [string]$ParentId = "root"
    )
    return @{
        Id = (Get-RandomHash)
        Title = $Title
        ParentId = $ParentId
        Children = @()
        Created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
}

# Import/Export PSD1 functions (from previous impexppsd1.ps1)
function Import-PowerShellData1 {
    param([string]$Path)
    $content = Get-Content -Path $Path -Raw
    $content = $content -replace '^(#.*[\r\n]*)+', ''
    $content = $content -replace '\bTrue\b', '$true' -replace '\bFalse\b', '$false'
    $scriptBlock = [scriptblock]::Create($content)
    return . $scriptBlock
}

function Export-PowerShellData1 {
    param(
        [hashtable]$Data,
        [string]$Path
    )
    $content = "@{`n"
    foreach ($key in $Data.Keys) {
        $value = $Data[$key]
        $content += "    $key = $(ConvertTo-Psd1String $value)`n"
    }
    $content += "}"
    Set-Content -Path $Path -Value $content
}

# Placeholder for complex functions
function Optimize-Image {
    # TODO: Implement image optimization
    throw [NotImplementedException]::new()
}

function Backup-TreeState {
    # TODO: Implement tree state backup
    throw [NotImplementedException]::new()
}

# Export all functions
Export-ModuleMember -Function *