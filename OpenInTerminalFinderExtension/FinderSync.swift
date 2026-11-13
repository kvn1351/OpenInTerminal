//
//  FinderSync.swift
//  OpenInTerminalFinderExtension
//
//  Created by Cameron Ingham on 4/17/19.
//  Copyright © 2019 Cameron Ingham. All rights reserved.
//

import Cocoa
import FinderSync
import OpenInTerminalCore
import Carbon

class FinderSync: FIFinderSync {
    
    override init() {
        super.init()
        let finderSync = FIFinderSyncController.default()

        // Always include the filesystem root. On recent macOS releases the
        // startup/data volume may be omitted from mountedVolumeURLs when hidden
        // APFS volumes are skipped, which leaves the extension running but with
        // no Finder locations in scope.
        var directoryURLs: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        if let mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
            directoryURLs.formUnion(mountedVolumes)
        }
        finderSync.directoryURLs = directoryURLs
        NSLog("OpenInTerminal Finder extension monitoring: %@",
              directoryURLs.map(\.path).sorted().joined(separator: ", "))

        // Monitor volumes
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { notification in
            if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                finderSync.directoryURLs.insert(volumeURL)
            }
        }
    }

    override var toolbarItemName: String {
        return NSLocalizedString("toolbar.item_name",
                                 comment: "Open in Terminal")
    }
    
    override var toolbarItemToolTip: String {
        return NSLocalizedString("toolbar.item_tooltip",
                                 comment: "Open current directory in Terminal.")
    }
    
    override var toolbarItemImage: NSImage {
        return NSImage(named: "Icon")!
    }
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        switch menuKind {
        case .contextualMenuForContainer,
             .contextualMenuForSidebar,
             .contextualMenuForItems:
            guard !DefaultsManager.shared.isHideContextMenuItems else { return NSMenu() }
            let actions = DefaultsManager.shared.contextMenuActions
            guard !actions.isEmpty else {
                return createDefaultMenu(useSubmenu: DefaultsManager.shared.isContextMenuUseSubmenu)
            }
            return createCustomMenu(actions: actions,
                                    useSubmenu: DefaultsManager.shared.isContextMenuUseSubmenu)

        case .toolbarItemMenu:
            let actions = DefaultsManager.shared.toolbarMenuActions
            guard !actions.isEmpty else { return createDefaultMenu(useSubmenu: false) }
            let menu = createCustomMenu(actions: actions, useSubmenu: false)
            return menu.items.isEmpty ? createDefaultMenu(useSubmenu: false) : menu

        default:
            return NSMenu(title: "")
        }
    }
    
    var scriptPath: URL? {
        return try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    func fileScriptPath(fileName: String) -> URL? {
        return scriptPath?
            .appendingPathComponent(fileName)
            .appendingPathExtension("scpt")
    }
    
    var copyPathItem: NSMenuItem {
        get {
            let copyPathItem = NSMenuItem(title: NSLocalizedString("menu.copy_path_to_clipboard",
                                                                   comment: "Copy path to Clipboard"),
                                                action: #selector(copyPathToClipboard),
                                                keyEquivalent: "")
            if DefaultsManager.shared.customMenuIconOption == .simple {
                let copyPathIcon = NSImage(named: "context_menu_icon_path")
                copyPathItem.image = copyPathIcon
            } else if DefaultsManager.shared.customMenuIconOption == .original {
                let copyPathIcon = NSImage(named: "context_menu_icon_color_path")
                copyPathItem.image = copyPathIcon
            }
            return copyPathItem
        }
    }
    
    /// Wraps the given items into a single "Open in..." submenu.
    func makeSubmenuItem(with itemsMenu: NSMenu) -> NSMenuItem {
        let submenuItem = NSMenuItem(title: NSLocalizedString("menu.submenu_title",
                                                              comment: "Open in..."),
                                     action: nil,
                                     keyEquivalent: "")
        submenuItem.submenu = itemsMenu
        return submenuItem
    }

    func createDefaultMenu(useSubmenu: Bool) -> NSMenu {
        let menu = NSMenu(title: "")

        // when submenu grouping is enabled, add the items into a separate
        // menu that will be attached under a single top level item
        let itemsMenu = useSubmenu ? NSMenu(title: "") : menu

        let terminal = DefaultsManager.shared.defaultTerminal ?? SupportedApps.terminal.app
        let terminalTitle = terminal.name
        let openInTerminalItem = NSMenuItem(title: terminalTitle,
                                            action: #selector(openDefaultTerminal),
                                            keyEquivalent: "")
        let terminalIcon = DefaultsManager.shared.getAppIcon(terminal)
        openInTerminalItem.image = terminalIcon
        itemsMenu.addItem(openInTerminalItem)

        let editor = DefaultsManager.shared.defaultEditor ?? SupportedApps.textEdit.app
        let editorTitle = editor.name
        let openInEditorItem = NSMenuItem(title: editorTitle,
                                            action: #selector(openDefaultEditor),
                                            keyEquivalent: "")
        let editorIcon = DefaultsManager.shared.getAppIcon(editor)
        openInEditorItem.image = editorIcon
        itemsMenu.addItem(openInEditorItem)

        // add "Copy Path"
        itemsMenu.addItem(self.copyPathItem)

        // attach the items menu under a single top level item when needed
        if useSubmenu {
            menu.addItem(makeSubmenuItem(with: itemsMenu))
        }

        return menu
    }

    func createCustomMenu(actions: [CustomMenuAction], useSubmenu: Bool) -> NSMenu {
        let menu = NSMenu(title: "")
        let itemsMenu = useSubmenu ? NSMenu(title: "") : menu

        for action in actions {
            let menuItem = NSMenuItem(title: action.name,
                                      action: #selector(customMenuItemClicked),
                                      keyEquivalent: "")
            menuItem.representedObject = action.id.uuidString
            if let app = action.application {
                menuItem.image = DefaultsManager.shared.getAppIcon(app)
            }
            itemsMenu.addItem(menuItem)
        }

        itemsMenu.addItem(copyPathItem)
        if useSubmenu {
            menu.addItem(makeSubmenuItem(with: itemsMenu))
        }
        return menu
    }

    // MARK: - Actions
    
    func getSelectedPathsFromFinder() -> [URL] {
        var urls = [URL]()
        if let items = FIFinderSyncController.default().selectedItemURLs(), items.count > 0 {
            items.forEach {
                urls.append($0)
            }
        } else if let url = FIFinderSyncController.default().targetedURL() {
            urls.append(url)
        }
        return urls
    }
    
    func open(_ app: App) {
        let urls = getSelectedPathsFromFinder()
        do {
            try app.openInSandbox(urls)
        } catch {
            logw("Failed to open \(app.name) with \(urls)")
        }
    }
    
//    func openTerminal(_ terminal: TerminalType) {
//        var scriptPath: URL
//        if terminal == .terminal,
//            let newOption = DefaultsManager.shared.getNewOption(.terminal),
//            newOption == .tab {
//            guard let fileScriptPath = fileScriptPath(fileName: terminal.rawValue + "-tab") else { return }
//            scriptPath = fileScriptPath
//        } else {
//            guard let fileScriptPath = fileScriptPath(fileName: terminal.rawValue) else { return }
//            scriptPath = fileScriptPath
//        }
//        guard FileManager.default.fileExists(atPath: scriptPath.path) else { return }
//        guard let script = try? NSUserAppleScriptTask(url: scriptPath) else { return }
//        script.execute(completionHandler: nil)
//    }
//
//    func openEditor(_ editor: EditorType) {
//        if (editor == .vscode) {
//            var path = "open -a Visual\\ Studio\\ Code"
//            if let items = FIFinderSyncController.default().selectedItemURLs(), items.count > 0 {
//                items.forEach { (url) in
//                    path += " \(url.path.specialCharEscaped2)"
//                }
//            } else if let url = FIFinderSyncController.default().targetedURL() {
//                path = url.path.specialCharEscaped2
//            } else {
//                return
//            }
//            let appleScript = try! NSUserAppleScriptTask(url: fileScriptPath(fileName: editor.rawValue)!)
//            appleScript.execute(withAppleEvent: getScriptEvent(functionName: "openVSCode", path)) { (appleEvent, error) in
//                if let error = error {
//                    print(error)
//                }
//            }
//        } else {
//            guard let scriptPath = fileScriptPath(fileName: editor.rawValue) else { return }
//            guard FileManager.default.fileExists(atPath: scriptPath.path) else { return }
//            guard let script = try? NSUserAppleScriptTask(url: scriptPath) else { return }
//            script.execute(completionHandler: nil)
//        }
//    }
    
    // MARK: - Menu Actions
    
    @objc func openDefaultTerminal() {
        let terminal = DefaultsManager.shared.defaultTerminal ?? SupportedApps.terminal.app
        open(terminal)
    }
    
    @objc func openDefaultEditor() {
        let editor = DefaultsManager.shared.defaultEditor ?? SupportedApps.textEdit.app
        open(editor)
    }
    
    @objc func customMenuItemClicked(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let action = DefaultsManager.shared.menuAction(withID: id) else { return }

        switch action.kind {
        case .application:
            guard let app = action.application else { return }
            open(app)
        case .cliScript:
            runCLIScript(action)
        }
    }

    private func runCLIScript(_ action: CustomMenuAction) {
        guard let scriptPath = action.scriptPath,
              FileManager.default.isExecutableFile(atPath: scriptPath) else {
            reportCLIError("The script for “\(action.name)” is missing or not executable.")
            return
        }
        guard let selectedURL = getSelectedPathsFromFinder().first else {
            reportCLIError("Finder did not provide a current folder for “\(action.name)”.")
            return
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory)
        let directoryURL = isDirectory.boolValue ? selectedURL : selectedURL.deletingLastPathComponent()
        let terminal = DefaultsManager.shared.defaultTerminal ?? SupportedApps.terminal.app

        do {
            let arguments = try TerminalCommandLauncher.arguments(
                terminal: terminal,
                scriptPath: scriptPath,
                workingDirectory: directoryURL.path,
                scriptArguments: action.arguments
            )
            guard let mode = arguments.first,
                  let scriptURL = fileScriptPath(fileName: ScriptManager.shared.getCLICommandScriptName(mode: mode)),
                  FileManager.default.fileExists(atPath: scriptURL.path) else {
                reportCLIError("The CLI script runner is missing. Restart OpenInTerminal and try again.")
                return
            }
            let script = try NSUserAppleScriptTask(url: scriptURL)
            let event = ScriptManager.shared.getCLICommandScriptEvent(arguments: arguments)
            script.execute(withAppleEvent: event) { _, error in
                if let error {
                    self.reportCLIError("Could not run “\(action.name)”: \(error.localizedDescription)")
                }
            }
        } catch {
            reportCLIError("Could not run “\(action.name)” in \(terminal.name): \(error.localizedDescription)")
        }
    }

    private func reportCLIError(_ message: String) {
        logw(message)
        let notification = NSUserNotification()
        notification.title = "OpenInTerminal CLI Action"
        notification.informativeText = message
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    @objc func copyPathToClipboard() {
        let urls = getSelectedPathsFromFinder()
        var paths = urls.map { $0.path }
        if DefaultsManager.shared.isPathEscaped {
            paths = paths.map { $0.specialCharEscaped() }
        }
        let pathString = paths.joined(separator: "\n")
        // Set string
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pathString, forType: .string)
    }
    
}

fileprivate extension String {
    
    subscript(_ range: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        let end = index(start, offsetBy: min(self.count - range.lowerBound,
                                             range.upperBound - range.lowerBound))
        return String(self[start..<end])
    }

    subscript(_ range: CountablePartialRangeFrom<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
         return String(self[start...])
    }
    
}
