#!/usr/bin/env python3
"""Exercise Finder callbacks with only the fields transported across XPC."""
from pathlib import Path
import subprocess
import sys
import tempfile

if len(sys.argv) != 2:
    raise SystemExit("Usage: test-finder-menu-dispatch.py <Build/Products/Release>")
products = str(Path(sys.argv[1]).resolve())
root = Path(__file__).resolve().parents[1]
source = r'''
import Cocoa
import OpenInTerminalCore

final class DispatchProbe: FinderSync {
    var opened: [App] = []
    override func open(_ app: App) { opened.append(app) }
}

let application = NSApplication.shared
let probe = DispatchProbe()
let terminal = App(name: "Terminal", type: .terminal)
let editor = App(name: "TextEdit", type: .editor)
var first = CustomMenuAction(application: terminal)
var second = CustomMenuAction(application: editor)
// Duplicate titles must not affect action identity.
first.name = "Open"
second.name = "Open"
let menu = probe.createCustomMenu(actions: [first, second], useSubmenu: false)
for item in menu.items.prefix(2) {
    let transportedItem = NSMenuItem(title: item.title, action: item.action, keyEquivalent: "")
    transportedItem.tag = item.tag
    precondition(transportedItem.representedObject == nil)
    probe.customMenuItemClicked(transportedItem)
}
precondition(probe.opened == [terminal, editor], "Finder transport lost action identity")

let groupedMenu = probe.createCustomMenu(actions: [second], useSubmenu: true)
let groupedItem = groupedMenu.items[0].submenu!.items[0]
let transportedItem = NSMenuItem(title: groupedItem.title, action: groupedItem.action, keyEquivalent: "")
transportedItem.tag = groupedItem.tag
probe.customMenuItemClicked(transportedItem)
precondition(probe.opened == [terminal, editor, editor], "Grouped menu dispatched an outdated action")

print("PASS: Finder-transported tags dispatch duplicate titles and grouped menus")
'''
with tempfile.TemporaryDirectory(prefix="oit-menu-dispatch-") as temporary:
    main = Path(temporary) / "main.swift"
    main.write_text(source)
    executable = Path(temporary) / "dispatch-probe"
    subprocess.run([
        "xcrun", "swiftc", "-F", products, "-framework", "OpenInTerminalCore",
        "-Xlinker", "-rpath", "-Xlinker", products,
        str(root / "OpenInTerminalFinderExtension/FinderSync.swift"),
        str(main), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
