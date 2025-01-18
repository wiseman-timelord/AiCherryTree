# .\scripts\interface.ps1

# Import required modules
Import-Module "$PSScriptRoot\utility.ps1"
Import-Module "$PSScriptRoot\model.ps1"
Import-Module "$PSScriptRoot\internet.ps1"

# Add Avalonia assemblies
Add-Type -Path ".\lib\Avalonia.dll"
Add-Type -Path ".\lib\Avalonia.Desktop.dll"
Add-Type -Path ".\lib\Avalonia.Controls.dll"

# UI Configuration
$global:UIConfig = @{
    WindowTitle = "LightStone"
    Width = 1200
    Height = 800
    TreeWidth = 300
    MinWidth = 800
    MinHeight = 600
    FontSize = 12
    ChatHeight = 200
    AutoSave = $true
    AutoSaveInterval = 300  # 5 minutes
}

# Event handlers
$global:UIEvents = @{
    OnNodeSelect = {
        param($Node)
        $global:TempVars.CurrentNode = $Node
        Update-ContentPanel
    }
    OnNodeCreate = {
        param($ParentNode)
        $newNode = New-TreeNode -Title "New Node" -ParentId $ParentNode.Id
        Save-TreeNode -Node $newNode
        Update-TreeView
        Show-StatusMessage "Node created successfully" "Success"
    }
    OnNodeDelete = {
        param($Node)
        $confirmed = Show-Confirmation "Delete Node" "Are you sure you want to delete this node?"
        if ($confirmed) {
            Remove-TreeNode -NodeId $Node.Id
            Update-TreeView
            Show-StatusMessage "Node deleted" "Success"
        }
    }
    OnNodeEdit = {
        param($Node, $Content)
        $Node.Content = $Content
        Save-TreeNode -Node $Node
        Show-StatusMessage "Changes saved" "Success"
    }
    OnNodeDragStart = {
        param($Node)
        $global:DragData = @{
            Node = $Node
            StartTime = Get-Date
        }
    }
    OnNodeDragEnd = {
        param($TargetNode)
        if ($global:DragData -and $global:DragData.Node -and $TargetNode) {
            Move-TreeNode -NodeId $global:DragData.Node.Id -NewParentId $TargetNode.Id
            $global:DragData = $null
            Update-TreeView
            Show-StatusMessage "Node moved successfully" "Success"
        }
    }
}

# Enhanced TreeView class
class EnhancedTreeView : Avalonia.Controls.TreeView {
    $DragEnabled = $true
    
    EnhancedTreeView() : base() {
        $this.InitializeDragDrop()
    }
    
    [void]InitializeDragDrop() {
        $this.PointerPressed += {
            param($sender, $e)
            if ($e.GetCurrentPoint($this).Properties.IsLeftButtonPressed) {
                $node = $this.GetNodeAtPoint($e.GetPosition($this))
                if ($node) {
                    $global:UIEvents.OnNodeDragStart.Invoke($node)
                }
            }
        }
        
        $this.PointerReleased += {
            param($sender, $e)
            if ($global:DragData) {
                $node = $this.GetNodeAtPoint($e.GetPosition($this))
                if ($node) {
                    $global:UIEvents.OnNodeDragEnd.Invoke($node)
                }
            }
        }
    }
    
    [object]GetNodeAtPoint([Avalonia.Point]$point) {
        $element = $this.InputHitTest($point)
        while ($element -and -not ($element -is [Avalonia.Controls.TreeViewItem])) {
            $element = [Avalonia.VisualExtensions]::GetVisualParent($element)
        }
        return $element?.DataContext
    }
}

# Main window class
class MainWindow : Avalonia.Controls.Window {
    $TreeView
    $ContentPanel
    $ChatInput
    $ChatOutput
    $StatusBar
    $MenuBar
    $ToolBar
    $AutoSaveTimer

    MainWindow() {
        $this.Title = $global:UIConfig.WindowTitle
        $this.Width = $global:UIConfig.Width
        $this.Height = $global:UIConfig.Height
        $this.MinWidth = $global:UIConfig.MinWidth
        $this.MinHeight = $global:UIConfig.MinHeight
        
        $this.InitializeComponent()
        $this.InitializeAutoSave()
    }

    [void]InitializeComponent() {
        # Create main layout
        $mainPanel = New-Object Avalonia.Controls.DockPanel
        
        # Create menu and toolbar
        $topPanel = New-Object Avalonia.Controls.StackPanel
        $topPanel.Orientation = [Avalonia.Layout.Orientation]::Vertical
        
        $this.MenuBar = $this.CreateMenuBar()
        $this.ToolBar = $this.CreateToolBar()
        
        $topPanel.Children.Add($this.MenuBar)
        $topPanel.Children.Add($this.ToolBar)
        
        [Avalonia.Controls.DockPanel]::SetDock($topPanel, [Avalonia.Controls.Dock]::Top)
        $mainPanel.Children.Add($topPanel)
        
        # Create status bar
        $this.StatusBar = $this.CreateStatusBar()
        [Avalonia.Controls.DockPanel]::SetDock($this.StatusBar, [Avalonia.Controls.Dock]::Bottom)
        $mainPanel.Children.Add($this.StatusBar)
        
        # Create main split container
        $splitContainer = New-Object Avalonia.Controls.Grid
        $columnDef1 = New-Object Avalonia.Controls.ColumnDefinition
        $columnDef1.Width = $global:UIConfig.TreeWidth
        $columnDef2 = New-Object Avalonia.Controls.ColumnDefinition
        $columnDef2.Width = "*"
        $splitContainer.ColumnDefinitions.Add($columnDef1)
        $splitContainer.ColumnDefinitions.Add($columnDef2)
        
        # Create and add tree view with search
        $treePanel = New-Object Avalonia.Controls.DockPanel
        $searchBox = New-Object Avalonia.Controls.TextBox
        $searchBox.Watermark = "Search nodes..."
        $searchBox.Margin = New-Object Avalonia.Thickness(5)
        [Avalonia.Controls.DockPanel]::SetDock($searchBox, [Avalonia.Controls.Dock]::Top)
        $treePanel.Children.Add($searchBox)
        
        $this.TreeView = $this.CreateTreeView()
        $treePanel.Children.Add($this.TreeView)
        
        [Avalonia.Controls.Grid]::SetColumn($treePanel, 0)
        $splitContainer.Children.Add($treePanel)
        
        # Create right panel (content + chat)
        $rightPanel = New-Object Avalonia.Controls.Grid
        $rowDef1 = New-Object Avalonia.Controls.RowDefinition
        $rowDef1.Height = "*"
        $rowDef2 = New-Object Avalonia.Controls.RowDefinition
        $rowDef2.Height = [Avalonia.Controls.GridLength]::new($global:UIConfig.ChatHeight)
        $rightPanel.RowDefinitions.Add($rowDef1)
        $rightPanel.RowDefinitions.Add($rowDef2)
        
        # Create content panel with toolbar
        $contentContainer = New-Object Avalonia.Controls.DockPanel
        $contentToolbar = $this.CreateContentToolBar()
        [Avalonia.Controls.DockPanel]::SetDock($contentToolbar, [Avalonia.Controls.Dock]::Top)
        $contentContainer.Children.Add($contentToolbar)
        
        $this.ContentPanel = $this.CreateContentPanel()
        $contentContainer.Children.Add($this.ContentPanel)
        
        [Avalonia.Controls.Grid]::SetRow($contentContainer, 0)
        $rightPanel.Children.Add($contentContainer)
        
        # Create chat panel
        $chatPanel = $this.CreateChatPanel()
        [Avalonia.Controls.Grid]::SetRow($chatPanel, 1)
        $rightPanel.Children.Add($chatPanel)
        
        # Add right panel to split container
        [Avalonia.Controls.Grid]::SetColumn($rightPanel, 1)
        $splitContainer.Children.Add($rightPanel)
        
        # Add split container to main panel
        $mainPanel.Children.Add($splitContainer)
        
        # Set content
        $this.Content = $mainPanel
        
        # Add keyboard handlers
        $this.KeyDown += {
            param($sender, $e)
            if ($e.KeyModifiers -eq [Avalonia.Input.KeyModifiers]::Control) {
                switch ($e.Key) {
                    ([Avalonia.Input.Key]::S) { 
                        Save-TreeNode -Node $global:TempVars.CurrentNode
                        $e.Handled = $true
                    }
                    ([Avalonia.Input.Key]::N) {
                        $global:UIEvents.OnNodeCreate.Invoke($global:TempVars.CurrentNode)
                        $e.Handled = $true
                    }
                }
            }
        }
    }
    
    [void]InitializeAutoSave() {
        if ($global:UIConfig.AutoSave) {
            $this.AutoSaveTimer = [System.Timers.Timer]::new($global:UIConfig.AutoSaveInterval * 1000)
            $this.AutoSaveTimer.Elapsed += {
                if ($global:TempVars.CurrentNode) {
                    Save-TreeNode -Node $global:TempVars.CurrentNode
                    Show-StatusMessage "Auto-saved" "Info"
                }
            }
            $this.AutoSaveTimer.Start()
        }
    }
    
    [Avalonia.Controls.ToolBar]CreateToolBar() {
        $toolBar = New-Object Avalonia.Controls.ToolBar
        
        # Add common tools
        $toolBar.Items.Add($this.CreateToolButton "New" { $global:UIEvents.OnNodeCreate.Invoke($global:TempVars.CurrentNode) })
        $toolBar.Items.Add($this.CreateToolButton "Save" { Save-TreeNode -Node $global:TempVars.CurrentNode })
        $toolBar.Items.Add(New-Object Avalonia.Controls.Separator)
        $toolBar.Items.Add($this.CreateToolButton "Cut" { $this.CutNode() })
        $toolBar.Items.Add($this.CreateToolButton "Copy" { $this.CopyNode() })
        $toolBar.Items.Add($this.CreateToolButton "Paste" { $this.PasteNode() })
        
        return $toolBar
    }
    
    [Avalonia.Controls.ToolBar]CreateContentToolBar() {
        $toolBar = New-Object Avalonia.Controls.ToolBar
        
        # Add content editing tools
        $toolBar.Items.Add($this.CreateToolButton "Bold" { $this.FormatText("bold") })
        $toolBar.Items.Add($this.CreateToolButton "Italic" { $this.FormatText("italic") })
        $toolBar.Items.Add(New-Object Avalonia.Controls.Separator)
        $toolBar.Items.Add($this.CreateToolButton "Insert Image" { $this.InsertImage() })
        
        return $toolBar
    }
    
    [Avalonia.Controls.Button]CreateToolButton($text, $action) {
        $button = New-Object Avalonia.Controls.Button
        $button.Content = $text
        $button.Command = [Avalonia.Input.RoutedCommand]::new($action)
        return $button
    }
    
    [Avalonia.Controls.MenuBar]CreateMenuBar() {
        $menuBar = New-Object Avalonia.Controls.MenuBar
        
        # File menu
        $fileMenu = New-Object Avalonia.Controls.MenuItem
        $fileMenu.Header = "File"
        $fileMenu.Items.Add($this.CreateMenuItem("New Node", { $global:UIEvents.OnNodeCreate.Invoke($global:TempVars.CurrentNode) }))
        $fileMenu.Items.Add($this.CreateMenuItem("Save", { Save-TreeNode -Node $global:TempVars.CurrentNode }))
        $fileMenu.Items.Add(New-Object Avalonia.Controls.Separator)
        $fileMenu.Items.Add($this.CreateMenuItem("Export", { $this.ExportTree() }))
        $fileMenu.Items.Add($this.CreateMenuItem("Import", { $this.ImportTree() }))
        $fileMenu.Items.Add(New-Object Avalonia.Controls.Separator)
        $fileMenu.Items.Add($this.CreateMenuItem("Exit", { $this.Close() }))
        $menuBar.Items.Add($fileMenu)
        
        # Edit menu
        $editMenu = New-Object Avalonia.Controls.MenuItem
        $editMenu.Header = "Edit"
        $editMenu.Items.Add($this.CreateMenuItem("Cut", { $this.CutNode() }))
        $editMenu.Items.Add($this.CreateMenuItem("Copy", { $this.CopyNode() }))
        $editMenu.Items.Add($this.CreateMenuItem("Paste", { $this.PasteNode() }))
        $editMenu.Items.Add(New-Object Avalonia.Controls.Separator)
        $editMenu.Items.Add($this.CreateMenuItem("Delete Node", { $global:UIEvents.OnNodeDelete.Invoke($global:TempVars.CurrentNode) }))
        $menuBar.Items.Add($editMenu)
        
        # View menu
        $viewMenu = New-Object Avalonia.Controls.MenuItem
        $viewMenu.Header = "View"
        $viewMenu.Items.Add($this.CreateMenuItem("Expand All", { $this.ExpandAll() }))
        $viewMenu.Items.Add($this.CreateMenuItem("Collapse All", { $this.CollapseAll() }))
        $menuBar.Items.Add($viewMenu)
        
        # Tools menu
        $toolsMenu = New-Object Avalonia.Controls.MenuItem
        $toolsMenu.Header = "Tools"
        $toolsMenu.Items.Add($this.CreateMenuItem("Settings", { $this.ShowSettings() }))
        $menuBar.Items.Add($toolsMenu)
        
        return $menuBar
    }
    
    [Avalonia.Controls.MenuItem]CreateMenuItem($header, $action) {
        $menuItem = New-Object Avalonia.Controls.MenuItem
        $menuItem.Header = $header
        $menuItem.Command = [Avalonia.Input.RoutedCommand]::new($action)
        return $menuItem
    }
    
    [Avalonia.Controls.TreeView]CreateTreeView() {
        $treeView = [EnhancedTreeView]::new()
        $treeView.SelectionChanged += {
            param($sender, $e)
            $node = $e.AddedItems[0]
            if ($node) {
                $global:UIEvents.OnNodeSelect.Invoke($node)
            }
        }
        return $treeView
    }
    
    [Avalonia.Controls.Panel]CreateContentPanel() {
        $panel = New-Object Avalonia.Controls.DockPanel
        
        # Create rich text box for content
        $contentBox = New-Object Avalonia.Controls.TextBox
        $contentBox.AcceptsReturn = $true
        $contentBox.TextWrapping = [Avalonia.Media.TextWrapping]::Wrap
        $contentBox.VerticalAlignment = [Avalonia.Layout.VerticalAlignment]::Stretch
        $contentBox.FontSize = $global:UIConfig.FontSize
        
        # Add content change handler
        $contentBox.TextChanged += {
            param($sender, $e)
            if ($global:TempVars.CurrentNode) {
                $global:UIEvents.OnNodeEdit.Invoke($global:TempVars.CurrentNode, $sender.Text)
            }
        }
        
        $panel.Children.Add($contentBox)
        return $panel
    }
    
    [Avalonia.Controls.Panel]CreateChatPanel() {
        $panel = New-Object Avalonia.Controls.DockPanel
        
        # Create splitter for chat panel
        $splitter = New-Object Avalonia.Controls.GridSplitter
        $splitter.Height = 5
        [Avalonia.Controls.DockPanel]::SetDock($splitter, [Avalonia.Controls.Dock]::Top)
        $panel.Children.Add($splitter)
        
        # Create chat output
        $this.ChatOutput = New-Object Avalonia.Controls.TextBox
        $this.ChatOutput.AcceptsReturn = $true
        $this.ChatOutput.IsReadOnly = $true
        $this.ChatOutput.Height = 150
        [Avalonia.Controls.DockPanel]::SetDock($this.ChatOutput, [Avalonia.Controls.Dock]::Top)
        $panel.Children.Add($this.ChatOutput)
        
        # Create chat input
        $inputPanel = New-Object Avalonia.Controls.DockPanel
        
        $sendButton = New-Object Avalonia.Controls.Button
        $sendButton.Content = "Send"
        $sendButton.Width = 60
        [Avalonia.Controls.DockPanel]::SetDock($sendButton, [Avalonia.Controls.Dock]::Right)
        
        $this.ChatInput = New-Object Avalonia.Controls.TextBox
        $this.ChatInput.Height = 50
        $this.ChatInput.Watermark = "Type your message here..."
        
        # Add key handler for chat input
        $this.ChatInput.KeyDown += {
            param($sender, $e)
            if ($e.Key -eq [Avalonia.Input.Key]::Enter -and -not $e.KeyModifiers) {
                $this.SendChatMessage($sender.Text)
                $sender.Text = ""
                $e.Handled = $true
            }
        }
        
        # Add click handler for send button
        $sendButton.Click += {
            $this.SendChatMessage($this.ChatInput.Text)
            $this.ChatInput.Text = ""
        }
        
        $inputPanel.Children.Add($sendButton)
        $inputPanel.Children.Add($this.ChatInput)
        
        $panel.Children.Add($inputPanel)
        return $panel
    }
    
    [Avalonia.Controls.StackPanel]CreateStatusBar() {
        $statusBar = New-Object Avalonia.Controls.StackPanel
        $statusBar.Orientation = [Avalonia.Layout.Orientation]::Horizontal
        $statusBar.Height = 25
        
        # Status label
        $statusLabel = New-Object Avalonia.Controls.TextBlock
        $statusLabel.Text = "Ready"
        $statusLabel.VerticalAlignment = [Avalonia.Layout.VerticalAlignment]::Center
        $statusLabel.Margin = New-Object Avalonia.Thickness(5)
        $statusBar.Children.Add($statusLabel)
        
        # Progress bar
        $progressBar = New-Object Avalonia.Controls.ProgressBar
        $progressBar.Width = 100
        $progressBar.Height = 15
        $progressBar.IsVisible = $false
        $progressBar.Margin = New-Object Avalonia.Thickness(5)
        $statusBar.Children.Add($progressBar)
        
        return $statusBar
    }
    
    # Helper methods for node operations
    [void]CutNode() {
        if ($global:TempVars.CurrentNode) {
            $global:ClipboardNode = $global:TempVars.CurrentNode
            $global:ClipboardOperation = "cut"
            Show-StatusMessage "Node cut to clipboard" "Info"
        }
    }
    
    [void]CopyNode() {
        if ($global:TempVars.CurrentNode) {
            $global:ClipboardNode = $global:TempVars.CurrentNode
            $global:ClipboardOperation = "copy"
            Show-StatusMessage "Node copied to clipboard" "Info"
        }
    }
    
    [void]PasteNode() {
        if ($global:ClipboardNode -and $global:TempVars.CurrentNode) {
            if ($global:ClipboardOperation -eq "cut") {
                Move-TreeNode -NodeId $global:ClipboardNode.Id -NewParentId $global:TempVars.CurrentNode.Id
                $global:ClipboardNode = $null
            }
            else {
                Copy-TreeNode -NodeId $global:ClipboardNode.Id -NewParentId $global:TempVars.CurrentNode.Id
            }
            Update-TreeView
            Show-StatusMessage "Node pasted successfully" "Success"
        }
    }
    
    [void]ExpandAll() {
        $items = $this.TreeView.GetItems()
        foreach ($item in $items) {
            $item.IsExpanded = $true
        }
    }
    
    [void]CollapseAll() {
        $items = $this.TreeView.GetItems()
        foreach ($item in $items) {
            $item.IsExpanded = $false
        }
    }
    
    [void]ShowSettings() {
        # TODO: Implement settings dialog
        Show-StatusMessage "Settings dialog not implemented" "Warning"
    }
    
	[void]ShowSettings() {
			$settingsDialog = [SettingsDialog]::new()
			$settingsDialog.ShowDialog($this)
			
			# Apply UI updates based on new settings
			$settings = Get-Settings
			if ($settings.Theme -eq "Dark") {
				$this.Background = [Avalonia.Media.Brushes]::Black
				$this.Foreground = [Avalonia.Media.Brushes]::White
			}
			else {
				$this.Background = [Avalonia.Media.Brushes]::White
				$this.Foreground = [Avalonia.Media.Brushes]::Black
			}
			
			# Update auto-save timer if changed
			if ($this.AutoSaveTimer) {
				$this.AutoSaveTimer.Interval = $settings.AutoSaveInterval * 1000
			}
			
			Show-StatusMessage "Settings updated" "Success"
		}
    }
}

# UI utility functions
function Show-Confirmation {
    param(
        [string]$Title,
        [string]$Message
    )
    $dialog = New-Object Avalonia.Controls.Window
    $dialog.Title = $Title
    $dialog.Width = 300
    $dialog.Height = 150
    $dialog.WindowStartupLocation = [Avalonia.Controls.WindowStartupLocation]::CenterOwner
    
    $panel = New-Object Avalonia.Controls.StackPanel
    $panel.Margin = New-Object Avalonia.Thickness(10)
    
    $messageText = New-Object Avalonia.Controls.TextBlock
    $messageText.Text = $Message
    $messageText.TextWrapping = [Avalonia.Media.TextWrapping]::Wrap
    $panel.Children.Add($messageText)
    
    $buttonPanel = New-Object Avalonia.Controls.StackPanel
    $buttonPanel.Orientation = [Avalonia.Layout.Orientation]::Horizontal
    $buttonPanel.Margin = New-Object Avalonia.Thickness(0, 10, 0, 0)
    $buttonPanel.HorizontalAlignment = [Avalonia.Layout.HorizontalAlignment]::Right
    
    $result = $false
    
    $okButton = New-Object Avalonia.Controls.Button
    $okButton.Content = "OK"
    $okButton.Click += {
        $result = $true
        $dialog.Close()
    }
    
    $cancelButton = New-Object Avalonia.Controls.Button
    $cancelButton.Content = "Cancel"
    $cancelButton.Click += {
        $dialog.Close()
    }
    
    $buttonPanel.Children.Add($okButton)
    $buttonPanel.Children.Add($cancelButton)
    $panel.Children.Add($buttonPanel)
    
    $dialog.Content = $panel
    $dialog.ShowDialog($global:MainWindow) | Out-Null
    
    return $result
}

# UI update functions
function Update-TreeView {
    $treeData = Get-TreeData
    $global:MainWindow.TreeView.Items = ConvertTo-TreeViewItems $treeData.root
}

function Update-ContentPanel {
    if ($global:TempVars.CurrentNode) {
        $content = Get-TreeNodeContent $global:TempVars.CurrentNode.TextHash
        if ($content) {
            $contentBox = $global:MainWindow.ContentPanel.Children[0]
            $contentBox.Text = $content
        }
    }
}

function Show-StatusMessage {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    $statusLabel = $global:MainWindow.StatusBar.Children[0]
    $statusLabel.Text = $Message
    
    # Update status color based on type
    $color = switch ($Type) {
        "Success" { "Green" }
        "Warning" { "Orange" }
        "Error" { "Red" }
        default { "Black" }
    }
    $statusLabel.Foreground = [Avalonia.Media.SolidColorBrush]::Parse($color)
}

function Show-Progress {
    param(
        [int]$Value,
        [string]$Message
    )
    $progressBar = $global:MainWindow.StatusBar.Children[1]
    $progressBar.Value = $Value
    $progressBar.IsVisible = $Value -gt 0 -and $Value -lt 100
    
    if ($Message) {
        Show-StatusMessage $Message
    }
}

# Main interface functions
function Initialize-AvaloniaUI {
    try {
        # Setup app builder
        $appBuilder = [Avalonia.AppBuilder]::Configure[[LightStoneApp]]()
            .UsePlatformDetect()
            .LogToTrace()
        
        # Initialize app
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
        # Initialize Avalonia
        if (-not (Initialize-AvaloniaUI)) {
            throw "Failed to initialize Avalonia UI"
        }
        
        # Create main window
        $global:MainWindow = [MainWindow]::new()
        
        # Load initial data
        Update-TreeView
        
        # Show window
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