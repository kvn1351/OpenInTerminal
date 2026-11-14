#!/usr/bin/env python3
"""Exercise custom-menu migration, independent ordering, and CLI argv building."""
import subprocess
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: test-custom-menu-actions.py <Build/Products/Release>")

products = sys.argv[1]
source = r'''
import Foundation
import OpenInTerminalCore

let suiteName = "test.openinterminal.custom-actions.\(UUID().uuidString)"
let store = UserDefaults(suiteName: suiteName)!
Defaults = store
defer { store.removePersistentDomain(forName: suiteName) }

let legacyApps = [
    App(name: "Ghostty", type: .terminal),
    App(name: "Zed", type: .editor)
]
Defaults[.customMenuOptions] = try! JSONEncoder().encode(legacyApps)
Defaults[.customMenuApplyToToolbar] = true
Defaults[.customMenuApplyToContext] = false

let manager = DefaultsManager.shared
manager.migrateLegacyCustomMenuActionsIfNeeded()
precondition(manager.toolbarMenuActions.map(\.name) == ["Ghostty", "Zed"])
precondition(manager.contextMenuActions.isEmpty)

let scriptAction = CustomMenuAction(cliScript: "Run Checks",
                                    path: "/tmp/run checks.sh",
                                    arguments: ["--mode", "value with spaces"])
let contextAction = CustomMenuAction(application: App(name: "TextEdit", type: .editor))
manager.toolbarMenuActions = [scriptAction] + manager.toolbarMenuActions
manager.contextMenuActions = [contextAction]
manager.migrateLegacyCustomMenuActionsIfNeeded()
precondition(manager.toolbarMenuActions.map(\.name) == ["Run Checks", "Ghostty", "Zed"])
precondition(manager.contextMenuActions.map(\.name) == ["TextEdit"])
precondition(manager.toolbarMenuActions[0].arguments == ["--mode", "value with spaces"])

// Upgrade the old global style without overwriting an existing per-menu choice.
Defaults[.firstSetup] = true
Defaults[.legacyCustomMenuIconOption] = "original"
Defaults[.toolbarMenuIconOption] = "no"
manager.firstSetup()
precondition(manager.menuIconOption(for: .toolbar) == .no)
precondition(manager.menuIconOption(for: .context) == .original)
precondition(Defaults[.legacyCustomMenuIconOption] == nil)
manager.setMenuIconOption(.simple, for: .toolbar)
manager.firstSetup()
precondition(manager.menuIconOption(for: .toolbar) == .simple)
precondition(manager.menuIconOption(for: .context) == .original)

let cwd = "/Users/test/Project Space"
let script = "/Users/test/bin/run checks.sh"
let iTermArgs = try TerminalCommandLauncher.arguments(
    terminal: SupportedApps.iTerm.app,
    scriptPath: script,
    workingDirectory: cwd,
    scriptArguments: ["--mode", "value with spaces"]
)
precondition(iTermArgs == ["iterm", cwd, script, "--mode", "value with spaces"])
let wezTermArgs = try TerminalCommandLauncher.arguments(
    terminal: SupportedApps.wezterm.app,
    scriptPath: script,
    workingDirectory: cwd,
    scriptArguments: ["--mode", "value with spaces"]
)
precondition(wezTermArgs == ["open", "-a", "WezTerm", "--args", "start", "--cwd", cwd,
                             "--", script, "--mode", "value with spaces"])
do {
    _ = try TerminalCommandLauncher.arguments(terminal: SupportedApps.warp.app,
                                               scriptPath: script,
                                               workingDirectory: cwd,
                                               scriptArguments: [])
    fatalError("Warp has no supported CLI launch adapter")
} catch TerminalCommandLaunchError.unsupportedTerminal("Warp") {
    // Expected: unsupported preferred terminal is surfaced, not silently mislaunched.
}
print("PASS: legacy migration, independent ordered lists, spaced CLI args, preferred-terminal argv")
'''
subprocess.run(
    ["xcrun", "swift", "-F", products, "-framework", "OpenInTerminalCore", "-e", source],
    check=True,
)
