# .\scripts\interface.ps1

# Import required modules
Import-Module "$PSScriptRoot\utility.ps1"
Import-Module "$PSScriptRoot\model.ps1"
Import-Module "$PSScriptRoot\internet.ps1"

# Add Avalonia assemblies
Add-Type -Path ".\lib\Avalonia.dll"
Add-Type -Path ".\lib\Avalonia.Desktop.dll"
Add-Type -Path ".\lib\Avalonia.Controls.dll"

# Initialize settings
$settings = Get-Settings
$global:UIConfig = @{
    AutoSave = $settings.AutoBackup
    AutoSaveInterval = $settings.AutoSaveInterval
}

# Event handlers
$global:UIEvents = @{
    NodeOperations = @{
        OnSelect = { 
            param($Node) 
            $global:TempVars.CurrentNode = $Node
            Update-ContentPanel 
        }
        OnCreate = { 
            param($ParentNode)
            $newNode = New-TreeNode -Title "New Node" -ParentId $ParentNode.Id
            Save-TreeNode -Node $newNode
            Update-TreeView
            Show-StatusMessage "Node created successfully" "Success"
        }
        OnDelete = {
            param($Node)
            if (Show-Confirmation "Delete Node" "Are you sure you want to delete this node?") {
                Remove-TreeNode -NodeId $Node.Id
                Update-TreeView
                Show-StatusMessage "Node deleted" "Success"
            }
        }
        OnEdit = {
            param($Node, $Content)
            $Node.Content = $Content
            Save-TreeNode -Node $Node
            Show-StatusMessage "Changes saved" "Success"
        }
    }
    Search = @{
        OnChange = { param($Text) Update-TreeViewFilter -Filter $Text }
    }
}

# Auto-save manager
class AutoSaveManager {
    [System.Timers.Timer]$Timer
    [scriptblock]$SaveCallback
    
    AutoSaveManager([scriptblock]$callback) {
        $settings = Get-Settings
        $this.SaveCallback = $callback
        $this.Timer = [System.Timers.Timer]::new($settings.AutoSaveInterval * 1000)
        $this.Timer.Elapsed += {
            if ($settings.AutoBackup) {
                try {
                    & $this.SaveCallback
                    Show-StatusMessage "Auto-saved" "Success"
                }
                catch {
                    Show-StatusMessage "Auto-save failed: $_" "Error"
                }
            }
        }
    }
    
    [void]Start() { $this.Timer.Start() }
    [void]Stop() { $this.Timer.Stop() }
}

# Main window class
class MainWindow : Avalonia.Controls.Window {
    $TreeView
    $ContentBox
    $ChatBox
    $StatusText
    $StatusProgress
    $AutoSaveManager
    
    MainWindow() {
        # Load XAML
        $xaml = [System.IO.File]::ReadAllText("$PSScriptRoot\interface.xaml")
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        [Avalonia.Markup.Xaml.AvaloniaXamlLoader]::Load($this, $reader)
        
        $this.InitializeComponents()
        $this.InitializeAutoSave()
        $this.InitializeCommands()
        
        # Apply theme from settings
        $settings = Get-Settings
        $this.Theme = $settings.Theme
    }
    
    [void]InitializeComponents() {
        # Get controls
        $this.TreeView = $this.FindName("DocumentTree")
        $this.ContentBox = $this.FindName("ContentBox")
        $this.ChatBox = $this.FindName("ChatBox")
        $this.StatusText = $this.FindName("StatusText")
        $this.StatusProgress = $this.FindName("StatusProgress")
        
        # Add event handlers
        $this.TreeView.SelectionChanged += { $global:UIEvents.NodeOperations.OnSelect.Invoke($_.AddedItems[0]) }
        $this.ContentBox.TextChanged += { 
            if ($global:TempVars.CurrentNode) {
                $global:UIEvents.NodeOperations.OnEdit.Invoke($global:TempVars.CurrentNode, $_.Text)
            }
        }
        
        # Add search handler
        $searchBox = $this.FindName("SearchBox")
        $searchBox.TextChanged += { $global:UIEvents.Search.OnChange.Invoke($_.Text) }
    }
    
    [void]InitializeAutoSave() {
        $this.AutoSaveManager = [AutoSaveManager]::new({
            if ($global:TempVars.CurrentNode) {
                Save-TreeNode -Node $global:TempVars.CurrentNode
            }
        })
        $this.AutoSaveManager.Start()
    }
    
    [void]InitializeCommands() {
        # Menu commands
        $this.FindName("NewNodeCommand").Execute += { $global:UIEvents.NodeOperations.OnCreate.Invoke($global:TempVars.CurrentNode) }
        $this.FindName("SaveCommand").Execute += { 
            if ($global:TempVars.CurrentNode) {
                Save-TreeNode -Node $global:TempVars.CurrentNode
                Show-StatusMessage "Saved successfully" "Success"
            }
        }
        $this.FindName("ExitCommand").Execute += { $this.Close() }
        
        # Add keyboard shortcuts
        $this.KeyDown += {
            param($sender, $e)
            if ($e.KeyModifiers -eq [Avalonia.Input.KeyModifiers]::Control) {
                switch ($e.Key) {
                    ([Avalonia.Input.Key]::S) {
                        if ($global:TempVars.CurrentNode) {
                            Save-TreeNode -Node $global:TempVars.CurrentNode
                            Show-StatusMessage "Saved successfully" "Success"
                            $e.Handled = $true
                        }
                    }
                    ([Avalonia.Input.Key]::N) {
                        if ($global:TempVars.CurrentNode) {
                            $global:UIEvents.NodeOperations.OnCreate.Invoke($global:TempVars.CurrentNode)
                            $e.Handled = $true
                        }
                    }
                }
            }
        }
    }
}

# UI utility functions
function Show-Confirmation {
    param(
        [string]$Title,
        [string]$Message
    )
    $result = $false
    
    $dialog = $global:MainWindow.FindName("ConfirmationDialog")
    $dialog.Title = $Title
    $dialog.FindName("MessageText").Text = $Message
    
    $dialog.FindName("OKButton").Click += { $result = $true; $dialog.Close() }
    $dialog.FindName("CancelButton").Click += { $dialog.Close() }
    
    $dialog.ShowDialog($global:MainWindow)
    return $result
}

function Show-StatusMessage {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    $color = switch ($Type) {
        "Success" { "Green" }
        "Warning" { "Orange" }
        "Error" { "Red" }
        default { "Black" }
    }
    
    $global:MainWindow.StatusText.Text = $Message
    $global:MainWindow.StatusText.Foreground = [Avalonia.Media.SolidColorBrush]::Parse($color)
}

function Show-Progress {
    param(
        [int]$Value,
        [string]$Message
    )
    $global:MainWindow.StatusProgress.Value = $Value
    $global:MainWindow.StatusProgress.IsVisible = $Value -gt 0 -and $Value -lt 100
    
    if ($Message) {
        Show-StatusMessage $Message
    }
}

function Update-TreeView {
    $treeData = Get-TreeData
    $global:MainWindow.TreeView.Items = ConvertTo-TreeViewItems $treeData.root
}

function Update-TreeViewFilter {
    param([string]$Filter)
    if ([string]::IsNullOrWhiteSpace($Filter)) {
        Update-TreeView
        return
    }
    
    $treeData = Get-TreeData
    $filteredItems = Convert-TreeNodeToViewModel $treeData.root | 
        Where-Object { $_.Title -like "*$Filter*" }
    $global:MainWindow.TreeView.Items = $filteredItems
}

function Update-ContentPanel {
    if ($global:TempVars.CurrentNode) {
        $content = Get-TreeNodeContent $global:TempVars.CurrentNode.TextHash
        if ($content) {
            $global:MainWindow.ContentBox.Text = $content
        }
    }
}

function Initialize-AvaloniaUI {
    try {
        $appBuilder = [Avalonia.AppBuilder]::Configure[[LightStoneApp]]()
            .UsePlatformDetect()
            .LogToTrace()
        return $appBuilder.StartWithClassicDesktopLifetime(@())
    }
    catch {
        Write-Error "Failed to initialize Avalonia UI: $_"
        return $false
    }
}

function Start-LightStoneInterface {
    param([hashtable]$Config)
    
    try {
        if (-not (Initialize-AvaloniaUI)) {
            throw "Failed to initialize Avalonia UI"
        }
        
        $global:MainWindow = [MainWindow]::new()
        Update-TreeView
        $global:MainWindow.Show()
        return $true
    }
    catch {
        Write-Error "Failed to start interface: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function *