# Node management and operations
# .\scripts\nodes.ps1

# Import required modules
. "$PSScriptRoot\utility.ps1"

# Tree management
function New-TreeNode {
    param(
        [string]$Title,
        [string]$Content = "",
        [string]$ParentId = "root",
        [array]$Children = @(),
        [hashtable]$Metadata = @{}
    )
    
    $nodeId = Get-RandomHash
    
    return @{
        Id = $nodeId
        Title = $Title
        Content = $Content
        ParentId = $ParentId
        Children = $Children
        Created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Modified = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Metadata = $Metadata
    }
}

function Save-TreeNode {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Node,
        [bool]$CreateBackup = $true
    )
    
    try {
        # Save content to text file if present
        if ($Node.Content) {
            $textHash = Get-RandomHash
            $textPath = Join-Path $global:PATHS.TextsDir "$textHash.txt"
            Set-Content -Path $textPath -Value $Node.Content -Force
            $Node.TextHash = $textHash
            $Node.Content = $null  # Don't store content in tree
        }

        # Update tree
        $tree = Get-TreeData
        $updated = Update-TreeNodeRecursive $tree.root $Node
        if (-not $updated) {
            throw "Failed to update node"
        }

        # Save tree
        $treeJson = $tree | ConvertTo-Json -Depth 10
        Set-Content -Path $global:PATHS.TreeFile -Value $treeJson -Force

        # Create backup if requested
        if ($CreateBackup) {
            Copy-Item $global:PATHS.TreeFile $global:PATHS.BackupFile -Force
        }

        return $true
    }
    catch {
        Write-Error "Failed to save tree node: $_"
        return $false
    }
}

function Update-TreeNodeRecursive {
    param(
        [Parameter(Mandatory = $true)]
        [object]$CurrentNode,
        [Parameter(Mandatory = $true)]
        [hashtable]$UpdateNode
    )
    
    if ($CurrentNode.Id -eq $UpdateNode.Id) {
        foreach ($key in $UpdateNode.Keys) {
            $CurrentNode.$key = $UpdateNode.$key
        }
        return $true
    }
    
    foreach ($child in $CurrentNode.Children) {
        if (Update-TreeNodeRecursive $child $UpdateNode) {
            return $true
        }
    }
    
    return $false
}

function Get-TreeNodeContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TextHash
    )
    
    $textPath = Join-Path $global:PATHS.TextsDir "$TextHash.txt"
    if (Test-Path $textPath) {
        return Get-Content -Path $textPath -Raw
    }
    return $null
}

function Move-TreeNode {
    param(
        [string]$NodeId,
        [string]$NewParentId,
        [int]$Position = -1  # -1 means append
    )
    try {
        $tree = Get-TreeData
        $node = Find-TreeNode -Tree $tree -NodeId $NodeId
        $oldParent = Find-TreeNode -Tree $tree -NodeId $node.ParentId
        $newParent = Find-TreeNode -Tree $tree -NodeId $NewParentId

        # Remove from old parent
        $oldParent.Children = $oldParent.Children | Where-Object { $_.Id -ne $NodeId }

        # Add to new parent
        $node.ParentId = $NewParentId
        if ($Position -eq -1 -or $Position -ge $newParent.Children.Count) {
            $newParent.Children += $node
        } else {
            $newParent.Children = @(
                $newParent.Children[0..($Position-1)]
                $node
                $newParent.Children[$Position..($newParent.Children.Count-1)]
            )
        }

        Save-TreeData -Tree $tree
        return $true
    }
    catch {
        Write-Error "Failed to move node: $_"
        return $false
    }
}

function Copy-TreeNode {
    param(
        [string]$NodeId,
        [string]$NewParentId,
        [bool]$Recursive = $true
    )
    try {
        $tree = Get-TreeData
        $sourceNode = Find-TreeNode -Tree $tree -NodeId $NodeId
        $targetParent = Find-TreeNode -Tree $tree -NodeId $NewParentId

        # Create copy of node
        $newNode = @{
            Id = Get-RandomHash
            Title = "$($sourceNode.Title) (Copy)"
            ParentId = $NewParentId
            Created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Modified = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Children = @()
        }

        # Copy content if exists
        if ($sourceNode.TextHash) {
            $content = Get-TreeNodeContent -TextHash $sourceNode.TextHash
            $newNode.TextHash = New-TextNode -Content $content -Title $newNode.Title
        }

        # Copy children recursively if requested
        if ($Recursive -and $sourceNode.Children) {
            foreach ($child in $sourceNode.Children) {
                Copy-TreeNode -NodeId $child.Id -NewParentId $newNode.Id -Recursive $true
            }
        }

        $targetParent.Children += $newNode
        Save-TreeData -Tree $tree
        return $newNode.Id
    }
    catch {
        Write-Error "Failed to copy node: $_"
        return $null
    }
}

function Merge-TreeNodes {
    param(
        [string[]]$NodeIds,
        [string]$NewTitle
    )
    try {
        $tree = Get-TreeData
        $nodes = $NodeIds | ForEach-Object { Find-TreeNode -Tree $tree -NodeId $_ }
        
        # Create merged content
        $mergedContent = @()
        foreach ($node in $nodes) {
            if ($node.TextHash) {
                $content = Get-TreeNodeContent -TextHash $node.TextHash
                $mergedContent += "=== $($node.Title) ===`n$content`n`n"
            }
        }

        # Create new node
        $newNode = @{
            Id = Get-RandomHash
            Title = $NewTitle
            ParentId = $nodes[0].ParentId
            Created = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Modified = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Children = @()
        }

        # Save merged content
        if ($mergedContent) {
            $newNode.TextHash = New-TextNode -Content ($mergedContent -join "`n") -Title $NewTitle
        }

        # Move all children to new node
        foreach ($node in $nodes) {
            $newNode.Children += $node.Children
            foreach ($child in $node.Children) {
                $child.ParentId = $newNode.Id
            }
        }

        # Remove old nodes
        $parent = Find-TreeNode -Tree $tree -NodeId $nodes[0].ParentId
        $parent.Children = @($parent.Children | Where-Object { $_.Id -notin $NodeIds })
        $parent.Children += $newNode

        Save-TreeData -Tree $tree
        return $newNode.Id
    }
    catch {
        Write-Error "Failed to merge nodes: $_"
        return $null
    }
}

# Node History Management
function Add-NodeHistory {
    param(
        [string]$NodeId,
        [string]$Action,
        [hashtable]$Changes
    )
    try {
        $historyPath = ".\data\history.psd1"
        $history = if (Test-Path $historyPath) {
            Import-PowerShellData1 -Path $historyPath
        } else {
            @{}
        }

        if (-not $history[$NodeId]) {
            $history[$NodeId] = @()
        }

        $history[$NodeId] += @{
            Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            Action = $Action
            Changes = $Changes
        }

        Export-PowerShellData1 -Data $history -Path $historyPath
        return $true
    }
    catch {
        Write-Error "Failed to add history: $_"
        return $false
    }
}

function Get-NodeHistory {
    param([string]$NodeId)
    try {
        $historyPath = ".\data\history.psd1"
        if (Test-Path $historyPath) {
            $history = Import-PowerShellData1 -Path $historyPath
            return $history[$NodeId]
        }
        return @()
    }
    catch {
        Write-Error "Failed to get history: $_"
        return @()
    }
}

# Tree Validation
function Test-TreeStructure {
    param([hashtable]$Tree)
    try {
        # Validate root
        if (-not $Tree.root) {
            throw "Missing root node"
        }

        # Track all node IDs
        $nodeIds = @{}
        $parentIds = @{}

        function Validate-Node {
            param($Node, $ParentId)
            
            # Check required properties
            if (-not $Node.Id -or -not $Node.Title) {
                throw "Node missing required properties"
            }

            # Check for duplicate IDs
            if ($nodeIds[$Node.Id]) {
                throw "Duplicate node ID: $($Node.Id)"
            }
            $nodeIds[$Node.Id] = $true

            # Track parent relationship
            if ($ParentId) {
                $parentIds[$Node.Id] = $ParentId
            }

            # Validate children
            if ($Node.Children) {
                foreach ($child in $Node.Children) {
                    Validate-Node -Node $child -ParentId $Node.Id
                }
            }
        }

        Validate-Node -Node $Tree.root

        # Validate parent references
        foreach ($nodeId in $nodeIds.Keys) {
            if ($nodeId -ne "root" -and -not $parentIds[$nodeId]) {
                throw "Orphaned node found: $nodeId"
            }
        }

        return $true
    }
    catch {
        Write-Error "Tree validation failed: $_"
        return $false
    }
}

# Export all functions
Export-ModuleMember -Function *