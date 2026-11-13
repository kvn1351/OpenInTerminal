//
//  SharedConfig.swift
//  OpenInTerminalCore
//
//  Shares the host app's preferences with its sandboxed Finder Sync extension.
//  The host publishes a plist in the extension's Application Scripts directory,
//  which the extension can read without App Group authorization.
//

import Foundation

public enum SharedConfig {
    private static let fileName = "shared-settings.plist"

    public static var isFinderExtension: Bool {
        Bundle.main.bundlePath.hasSuffix(".appex")
    }

    private static var isHostApplication: Bool {
        Bundle.main.bundleIdentifier == Constants.Id.MainApp
    }

    private static let preferenceKeys = [
        DefaultsKeys.firstSetup._key,
        DefaultsKeys.launchAtLogin._key,
        DefaultsKeys.quickToggle._key,
        DefaultsKeys.quickToggleType._key,
        DefaultsKeys.hideStatusItem._key,
        DefaultsKeys.hideContextMenuItems._key,
        DefaultsKeys.contextMenuUseSubmenu._key,
        DefaultsKeys.defaultTerminal._key,
        DefaultsKeys.defaultEditor._key,
        DefaultsKeys.terminalNewOption._key,
        DefaultsKeys.iTermNewOption._key,
        DefaultsKeys.customMenuOptions._key,
        DefaultsKeys.customMenuApplyToToolbar._key,
        DefaultsKeys.customMenuApplyToContext._key,
        DefaultsKeys.toolbarMenuActions._key,
        DefaultsKeys.contextMenuActions._key,
        DefaultsKeys.customMenuIconOption._key,
        DefaultsKeys.pathEscapeOption._key,
        DefaultsKeys.kittyCommand._key,
        DefaultsKeys.onlyActivateShortcutsInFinder._key,
        DefaultsKeys.neovimCommand._key,
        DefaultsKeys.gitkrakenCommand._key,
        DefaultsKeys.liteDefaultTerminal._key,
        DefaultsKeys.liteDefaultEditor._key
    ]

    private static func directoryURL(create: Bool) -> URL? {
        let fileManager = FileManager.default
        let scriptsURL: URL
        if let url = try? fileManager.url(for: .applicationScriptsDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: nil,
                                          create: create) {
            scriptsURL = url
        } else if create {
            let fallback = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Scripts", isDirectory: true)
            do {
                try fileManager.createDirectory(at: fallback,
                                                withIntermediateDirectories: true)
                scriptsURL = fallback
            } catch {
                return nil
            }
        } else {
            return nil
        }

        let extensionDirectory = scriptsURL.lastPathComponent == Constants.Id.FinderExtension
            ? scriptsURL
            : scriptsURL.deletingLastPathComponent()
                .appendingPathComponent(Constants.Id.FinderExtension, isDirectory: true)
        if create {
            do {
                try fileManager.createDirectory(at: extensionDirectory,
                                                withIntermediateDirectories: true)
            } catch {
                return nil
            }
        }
        return extensionDirectory
    }

    private static var fileURL: URL? {
        directoryURL(create: false)?.appendingPathComponent(fileName)
    }

    private static func values() -> [String: Any] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data,
                                                                        options: [],
                                                                        format: nil) else {
            return [:]
        }
        return object as? [String: Any] ?? [:]
    }

    public static func value(forKey key: String) -> Any? {
        values()[key]
    }

    /// The host app is the only writer; the extension reads the published file.
    public static func set(_ value: Any?, forKey key: String) {
        guard isHostApplication else { return }
        var snapshot = values()
        if let value {
            snapshot[key] = value
        } else {
            snapshot.removeValue(forKey: key)
        }
        write(snapshot)
    }

    /// Seed the host defaults from an existing mirror before first-run defaults
    /// are applied. Existing host values always win.
    public static func restoreMissingValues(to defaults: UserDefaults) {
        guard isHostApplication else { return }
        for (key, value) in values() where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    /// Import settings from older App Group stores, then let the active host
    /// defaults take precedence when the full snapshot is published.
    public static func migrateLegacySettings(to defaults: UserDefaults) {
        guard isHostApplication else { return }
        var snapshot = values()
        let legacyGroups = [Constants.Id.Group,
                            Constants.Id.PreviousGroup,
                            Constants.Id.LegacyGroup]
        for group in legacyGroups {
            guard let legacy = UserDefaults(suiteName: group) else { continue }
            for key in preferenceKeys where snapshot[key] == nil {
                guard let value = legacy.object(forKey: key) else { continue }
                snapshot[key] = value
                if defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
        }
        write(snapshot)
    }

    /// Publish current host values without deleting mirror entries the host
    /// cannot see (for example, values migrated from a previous App Group).
    public static func publish(from defaults: UserDefaults) {
        guard isHostApplication else { return }
        var snapshot = values()
        for key in preferenceKeys {
            if let value = defaults.object(forKey: key) {
                snapshot[key] = value
            }
        }
        write(snapshot)
    }

    public static func removeAll() {
        guard isHostApplication, let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func write(_ values: [String: Any]) {
        guard let directory = directoryURL(create: true),
              let data = try? PropertyListSerialization.data(fromPropertyList: values,
                                                             format: .binary,
                                                             options: 0) else {
            return
        }
        let url = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: url.path)
        } catch {
            logw("SharedConfig: writing shared settings failed: \(error.localizedDescription)")
        }
    }
}
