//
//  CustomPreferencesViewController.swift
//  OpenInTerminal
//
//  Created by Jianing Wang on 2019/4/21.
//  Copyright © 2019 Jianing Wang. All rights reserved.
//

import Cocoa
import OpenInTerminalCore

class CustomPreferencesViewController: PreferencesViewController {
    
    // MARK: Properties
    
    @IBOutlet weak var installedApplicationsTextField: NSTextField!
    @IBOutlet weak var notInstalledApplicationsTextField: NSTextField!
    
    @IBOutlet weak var iTermTextField: NSTextField!
    @IBOutlet weak var iTermWindowButton: NSButton!
    @IBOutlet weak var iTermTabButton: NSButton!
    
    @IBOutlet weak var customMenuTableView: NSTableView!
    @IBOutlet weak var addMenuOptionButton: NSButton!
    var addOptionMenu: NSMenu = NSMenu()
    @IBOutlet weak var toolbarMenuTargetButton: NSButton!
    @IBOutlet weak var contextMenuTargetButton: NSButton!
    
    @IBOutlet weak var noIconButton: NSButton!
    @IBOutlet weak var simpleIconButton: NSButton!
    @IBOutlet weak var originalIconButton: NSButton!
    
    @IBOutlet weak var pathNoButton: NSButton!
    @IBOutlet weak var pathYesButton: NSButton!
    
    private var dragDropType = NSPasteboard.PasteboardType(rawValue: "private.table-row")
    
    var allInstalledAppNames: Set<String> = Set() {
        didSet {
            DispatchQueue.main.async {
                self.refreshSupportedApps()
            }
        }
    }
    var installedSupportedAppNames: [String] = []
        
    var customMenuTarget: CustomMenuTarget = .context
    var customMenuActions = [CustomMenuAction]() {
        didSet {
            customMenuTableView.reloadData()
            if customMenuActions != DefaultsManager.shared.menuActions(for: customMenuTarget) {
                DefaultsManager.shared.setMenuActions(customMenuActions, for: customMenuTarget)
            }
        }
    }
    var runningApps = [App]()
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        customMenuTableView.dataSource = self
        customMenuTableView.delegate = self
        customMenuTableView.registerForDraggedTypes([dragDropType])
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        // fetch installed apps
        DispatchQueue.global(qos: .background).async {
            self.allInstalledAppNames = FinderManager.shared.getAllInstalledApps()
        }
        selectMenuTarget(customMenuTarget)
        refreshSupportedApps()
        refreshCustomButtons()
        refreshIconTypeOptionState()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
    }
    
    // MARK: Refresh UI
    
    func refreshSupportedApps() {
        // get all installed supported apps
        installedSupportedAppNames = SupportedApps.allCases.map(\.name)
            .filter(allInstalledAppNames.contains)
            .sortedIgnoreCase()
        installedApplicationsTextField.stringValue = installedSupportedAppNames.joined(separator: ", ")
        
        // get all not installed supported apps
        let notInstalledSupportedApps = SupportedApps.allCases.map(\.name)
            .filter { !installedSupportedAppNames.contains($0) }
            .sortedIgnoreCase()
        notInstalledApplicationsTextField.stringValue = notInstalledSupportedApps.joined(separator: ", ")
        
        // refresh text field enabled state
        let terminals: [(SupportedApps, NSTextField)] = [
            (.iTerm, iTermTextField)
        ]
        terminals.forEach { terminal, textField in
            let isInstalled = installedSupportedAppNames.contains(terminal.name)
            textField.isEnabled = isInstalled
            if isInstalled {
                textField.textColor = .labelColor
                textField.stringValue = "\(terminal.name)"
            } else {
                textField.textColor = .secondaryLabelColor
                let notInstalledString = NSLocalizedString("pref.toolbar.not_installed", comment: "Not Installed")
                textField.stringValue = "\(terminal.name) (\(notInstalledString))"
            }
        }
        
        // refresh button state
        iTermWindowButton.isEnabled = iTermTextField.isEnabled
        iTermTabButton.isEnabled = iTermTextField.isEnabled
        
        let terminalStates: [(SupportedApps, NSButton, NSButton)] = [
            (.iTerm, iTermWindowButton, iTermTabButton)
        ]
        terminalStates.forEach { terminal, windowButton, tabButton in
            let _newOption = DefaultsManager.shared.getNewOption(terminal)
            if let newOption = _newOption {
                if newOption == .window {
                    windowButton.state = .on
                    tabButton.state = .off
                } else {
                    windowButton.state = .off
                    tabButton.state = .on
                }
            }
        }
    }
    
    func refreshCustomButtons() {
        toolbarMenuTargetButton.state = customMenuTarget == .toolbar ? .on : .off
        contextMenuTargetButton.state = customMenuTarget == .context ? .on : .off
        let isPathEscaped = DefaultsManager.shared.isPathEscaped
        pathYesButton.state = isPathEscaped ? .on : .off
        pathNoButton.state = isPathEscaped ? .off : .on
    }

    func selectMenuTarget(_ target: CustomMenuTarget) {
        customMenuTarget = target
        refreshCustomButtons()
        customMenuActions = DefaultsManager.shared.menuActions(for: target)
    }
    
    func offIconTypeButtons() {
        noIconButton.state = .off
        simpleIconButton.state = .off
        originalIconButton.state = .off
    }
    
    func refreshIconTypeOptionState() {
        offIconTypeButtons()
        let option = DefaultsManager.shared.customMenuIconOption
        switch option {
        case .no:
            noIconButton.state = .on
        case .simple:
            simpleIconButton.state = .on
        case .original:
            originalIconButton.state = .on
        }
    }
    
    func refreshAddOptionMenu() {
        addOptionMenu.removeAllItems()
        
        // 1. Installed Supported Apps
        let installedSupportedMenu = NSMenu()
        installedSupportedAppNames.forEach {
            let menuItem = NSMenuItem(title: $0,
              action: #selector(selectSupportedApp),
              keyEquivalent: "")
            menuItem.target = self
            menuItem.image = NSImage(named: $0)
            menuItem.image?.size = NSSize(width: 14, height: 14)
            installedSupportedMenu.addItem(menuItem)
        }
        let installedSupportedMenuItem = NSMenuItem()
        installedSupportedMenuItem.title = NSLocalizedString("pref.custom.menu.installed_supported", comment: "Installed Supported Apps")
        addOptionMenu.addItem(installedSupportedMenuItem)
        addOptionMenu.setSubmenu(installedSupportedMenu, for: installedSupportedMenuItem)
        
        // 2. All Supported Apps
        let supportedMenu = NSMenu()
        SupportedApps.allCases.forEach {
            let menuItem = NSMenuItem(title: $0.name,
                                      action: #selector(selectSupportedApp),
                                      keyEquivalent: "")
            menuItem.target = self
            menuItem.image = NSImage(named: $0.name)
            menuItem.image?.size = NSSize(width: 14, height: 14)
            supportedMenu.addItem(menuItem)
        }
        let supportedMenuItem = NSMenuItem()
        supportedMenuItem.title = NSLocalizedString("pref.custom.menu.all_supported", comment: "All Supported Apps")
        addOptionMenu.addItem(supportedMenuItem)
        addOptionMenu.setSubmenu(supportedMenu, for: supportedMenuItem)
        
        // 3. Running Applications
        let runningMenu = NSMenu()
        let runningApplications = NSWorkspace.shared.runningApplications
        runningApps.removeAll()
        for runningApp in runningApplications {
            guard runningApp.activationPolicy == .regular else { continue }
            guard let bundleURL = runningApp.bundleURL else { continue }
            let icon = AppManager.getApplicationIcon(from: bundleURL)
            let name = AppManager.getApplicationFileName(from: bundleURL.path)
            let menuItem = NSMenuItem(title: name,
                                      action: #selector(selectRunningApp),
                                      keyEquivalent: "")
            menuItem.target = self
            menuItem.image = icon
            menuItem.image?.size = NSSize(width: 14, height: 14)
            runningMenu.addItem(menuItem)
            let app = App(name: name, type: .terminal)
            runningApps.append(app)
        }
        let runningMenuItem = NSMenuItem()
        runningMenuItem.title = NSLocalizedString("pref.custom.menu.running_apps", comment: "Running Apps")
        addOptionMenu.addItem(runningMenuItem)
        addOptionMenu.setSubmenu(runningMenu, for: runningMenuItem)
        
        // 4. Manually Select From Finder
        let manuallySelectTitle = NSLocalizedString("pref.custom.menu.manually_select", comment: "Manually Select From Finder")
        let manuallySelectMenuItem = NSMenuItem(title: manuallySelectTitle,
                                                action: #selector(selectManuallySelect),
                                                keyEquivalent: "")
        manuallySelectMenuItem.target = self
        addOptionMenu.addItem(manuallySelectMenuItem)
        
        // 5. Manually Input
        let manuallyInputTitle = NSLocalizedString("pref.custom.menu.manually_input", comment: "Manually Input")
        let manuallyInputMenuItem = NSMenuItem(title: manuallyInputTitle,
                                                action: #selector(selectManuallyInput),
                                                keyEquivalent: "")
        manuallyInputMenuItem.target = self
        addOptionMenu.addItem(manuallyInputMenuItem)
        addOptionMenu.addItem(.separator())
        let cliScriptItem = NSMenuItem(title: "Add CLI Script…",
                                       action: #selector(addCLIScript),
                                       keyEquivalent: "")
        cliScriptItem.target = self
        addOptionMenu.addItem(cliScriptItem)
        
    }
    
    // MARK: Button Actions
    
    @IBAction func iTermWindowButtonClicked(_ sender: NSButton) {
        iTermTabButton.state = .off
        DefaultsManager.shared.setNewOption(.iTerm, .window)
    }
    
    @IBAction func iTermTabButtonClicked(_ sender: NSButton) {
        iTermWindowButton.state = .off
        DefaultsManager.shared.setNewOption(.iTerm, .tab)
    }
    
    @IBAction func pathNoButtonClicked(_ sender: NSButton) {
        pathYesButton.state = .off
        DefaultsManager.shared.isPathEscaped = false
    }
    
    @IBAction func pathYesButtonClicked(_ sender: NSButton) {
        pathNoButton.state = .off
        DefaultsManager.shared.isPathEscaped = true
    }
    
    @IBAction func addMenuOptionButtonClicked(_ sender: NSButton) {
        refreshAddOptionMenu()
        let point = NSPoint(x: sender.frame.origin.x, y: sender.frame.origin.y - (sender.frame.height / 2))
        addOptionMenu.popUp(positioning: nil, at: point, in: sender.superview)
    }
    
    @objc func selectSupportedApp(_ sender: NSMenuItem) {
        guard let app = SupportedApps.from(name: sender.title) else { return }
        customMenuActions.append(CustomMenuAction(application: app.app))
    }

    @objc func selectRunningApp(_ sender: NSMenuItem) {
        guard let app = runningApps.first(where: { $0.name == sender.title }) else { return }
        showCustomInputViewController(app.name)
    }

    @objc func selectManuallySelect(_ sender: NSMenuItem) {
        openFileSelectPanel()
    }

    @objc func selectManuallyInput(_ sender: NSMenuItem) {
        showCustomInputViewController()
    }

    func addCustomApp(_ app: App) {
        customMenuActions.append(CustomMenuAction(application: app))
    }

    @objc func addCLIScript() {
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.beginSheetModal(for: view.window!) { response in
            guard response == .OK, let scriptURL = openPanel.url else { return }
            guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
                let alert = NSAlert()
                alert.messageText = "The script must be executable"
                alert.informativeText = "Run chmod +x on the script, then add it again."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
            self.promptForCLIScript(at: scriptURL)
        }
    }

    private func promptForCLIScript(at scriptURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Add CLI Script"
        alert.informativeText = "Runs in the preferred Terminal, iTerm, Alacritty, kitty, WezTerm, or Ghostty. Enter one optional argument per line; spaces within a line are preserved."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: scriptURL.deletingPathExtension().lastPathComponent)
        let argumentsView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 72))
        argumentsView.isRichText = false
        let argumentsScrollView = NSScrollView(frame: argumentsView.frame)
        argumentsScrollView.hasVerticalScroller = true
        argumentsScrollView.borderType = .bezelBorder
        argumentsScrollView.documentView = argumentsView

        let stack = NSStackView(views: [
            NSTextField(labelWithString: "Menu title"),
            nameField,
            NSTextField(labelWithString: "Arguments (one per line)"),
            argumentsScrollView
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 156)
        nameField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        argumentsScrollView.widthAnchor.constraint(equalToConstant: 320).isActive = true
        argumentsScrollView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let arguments = argumentsView.string
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        customMenuActions.append(CustomMenuAction(cliScript: name,
                                                   path: scriptURL.path,
                                                   arguments: arguments))
    }
    
    @IBAction func removeMenuOptionButtonClicked(_ sender: NSButton) {
        let row = customMenuTableView.selectedRow
        guard customMenuActions.indices.contains(row) else { return }
        customMenuActions.remove(at: row)
    }

    @IBAction func selectToolbarMenuClicked(_ sender: NSButton) {
        selectMenuTarget(.toolbar)
    }

    @IBAction func selectContextMenuClicked(_ sender: NSButton) {
        selectMenuTarget(.context)
    }
    
    func showCustomInputViewController(_ appName: String = "") {
        guard let customInputViewController = Constants.PreferencesStoryboard.instantiateController(withIdentifier: Constants.Id.CustomInputViewController) as? CustomInputViewController else {
            return
        }
        if appName != "" {
            customInputViewController.appName = appName
        }
        self.presentAsSheet(customInputViewController)
    }
    
    @IBAction func noIconButtonClicked(_ sender: NSButton) {
        offIconTypeButtons()
        noIconButton.state = .on
        DefaultsManager.shared.customMenuIconOption = .no
    }
    
    @IBAction func simpleIconButtonClicked(_ sender: NSButton) {
        offIconTypeButtons()
        simpleIconButton.state = .on
        DefaultsManager.shared.customMenuIconOption = .simple
    }
    
    @IBAction func originalIconButtonClicked(_ sender: NSButton) {
        offIconTypeButtons()
        originalIconButton.state = .on
        DefaultsManager.shared.customMenuIconOption = .original
    }
}

extension CustomPreferencesViewController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == customMenuTableView {
            return customMenuActions.count
        } else {
            return 0
        }
    }
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: self.dragDropType)
        return item
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above {
            return .move
        }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        var oldIndexes = [Int]()
        info.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { dragItem, _, _ in
            if let str = (dragItem.item as! NSPasteboardItem).string(forType: self.dragDropType), let index = Int(str) {
                oldIndexes.append(index)
            }
        }
        var oldIndexOffset = 0
        var newIndexOffset = 0
        
        customMenuActions.move(with: IndexSet(oldIndexes), to: row)

        // For simplicity, the code below uses `tableView.moveRowAtIndex` to move rows around directly.
        // You may want to move rows in your content array and then call `tableView.reloadData()` instead.
        tableView.beginUpdates()
        for oldIndex in oldIndexes {
            if oldIndex < row {
                // ⬇️
                tableView.moveRow(at: oldIndex + oldIndexOffset, to: row - 1)
                oldIndexOffset -= 1
            } else {
                // ⬆️
                tableView.moveRow(at: oldIndex, to: row + newIndexOffset)
                newIndexOffset += 1
            }
        }
        tableView.endUpdates()

        return true
    }

}

extension CustomPreferencesViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let cell = tableView.makeView(withIdentifier: Constants.Id.CustomMenuCell, owner: nil) as? NSTableCellView {
            let action = customMenuActions[row]
            cell.textField?.stringValue = action.kind == .cliScript
                ? "\(action.name) (CLI)"
                : action.name
            return cell
        }
        return nil
    }
    
}

extension CustomPreferencesViewController: NSMenuDelegate {

    func openFileSelectPanel() {
        let openPanel = NSOpenPanel()
        openPanel.directoryURL = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first!
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedFileTypes = ["app", "App", "APP"]
        openPanel.beginSheetModal(for: view.window!, completionHandler: {
            result in
            if result == NSApplication.ModalResponse.OK {
                if let appPath = openPanel.url?.path,
                   let _ = Bundle(url: openPanel.url!)?.bundleIdentifier {
                    let name = AppManager.getApplicationFileName(from: appPath)
                    self.showCustomInputViewController(name)
                } else {
                    // 对于没有 bundleId 的应用可能是快捷方式, 给予提示
                }
            }
        })
    }
    
    
}
