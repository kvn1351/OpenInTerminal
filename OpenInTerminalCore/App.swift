//
//  App.swift
//  OpenInTerminalCore
//
//  Created by Jianing Wang on 2020/12/5.
//  Copyright © 2020 Jianing Wang. All rights reserved.
//

import Foundation
import ScriptingBridge

public enum AppType: String, Codable {
    case terminal
    case editor
}

public struct App: Codable {
    public var name: String
    public var path: String?
    public var bundleId: String?
    public var type: AppType
    
    public init(name: String, type: AppType) {
        self.name = name
        self.type = type
    }
}

extension App: Equatable {
    public static func == (lhs: App, rhs: App) -> Bool {
        return lhs.name == rhs.name && lhs.bundleId == rhs.bundleId
    }
}

// MARK: - Openable

public protocol Openable {
    func openOutsideSandbox() throws
    func openInSandbox(_ urls: [URL]) throws
}

extension App: Openable {
    
    public func openOutsideSandbox() throws {

        // Launch the `open` command directly, passing each path as a discrete
        // argument. This avoids building a shell command string or an AppleScript
        // source string from an untrusted path, which was exploitable for both
        // AppleScript injection and shell command injection via crafted folder
        // names. See the security advisory (Findings 1 & 2).
        func runOpen(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = arguments
            logw("open " + arguments.joined(separator: " "))
            do {
                try process.run()
            } catch {
                throw OITError.cannotAccessApp(self.name)
            }
        }

        switch self.type {
        case .terminal:
            // get path
            var path = try FinderManager.shared.getPathToFrontFinderWindowOrSelectedFile()
            if path == "" {
                // No Finder window and no file selected.
                guard let desktopPath = FinderManager.shared.getDesktopPath() else { return }
                path = desktopPath
            }

            if SupportedApps.is(self, is: .terminal) {
                // this app is supported: Terminal
                let url = URL(fileURLWithPath: path)
                guard let terminal = SBApplication(bundleIdentifier: SupportedApps.terminal.bundleId) as TerminalApplication?,
                      let open = terminal.open else {
                    throw OITError.cannotAccessApp(self.name)
                }
                open([url])
                terminal.activate()
            } else {
                // this app is general (e.g. iTerm, Alacritty, kitty)
                var arguments = DefaultsManager.shared.getOpenArguments(self)
                arguments.append(path)
                try runOpen(arguments)
            }

        case .editor:
            // get paths
            var paths = try FinderManager.shared.getFullPathsToFrontFinderWindowOrSelectedFile()
            if paths.count == 0 {
                // No Finder window and no file selected.
                guard let desktopPath = FinderManager.shared.getDesktopPath() else { return }
                paths.append(desktopPath)
            }

            var arguments = DefaultsManager.shared.getOpenArguments(self)
            // fix for neovim: the command template carries a "PATH" placeholder
            // token that must be replaced by the actual path arguments.
            if SupportedApps.is(self, is: .neovim) {
                arguments = arguments.flatMap { $0 == "PATH" ? paths : [$0] }
            } else {
                arguments.append(contentsOf: paths)
            }
            try runOpen(arguments)
        }
    }
    
    public func openInSandbox(_ urls: [URL]) throws {
        // Build the invocation as a list of discrete arguments — the leading
        // program, the app-specific option tokens (trusted config from
        // getOpenArguments), then the raw target paths as individual elements.
        // The installed AppleScript shell-quotes every element via
        // `quoted form of`, so nothing here is manually escaped and a crafted
        // file/folder name cannot inject shell commands. This mirrors the
        // argument-array approach used by openOutsideSandbox.
        var arguments = ["/usr/bin/open"]
        arguments.append(contentsOf: DefaultsManager.shared.getOpenArguments(self))

        switch self.type {
        case .terminal:
            guard var url = urls.first else { return }
            url.getDirectory()
            arguments.append(url.path)
        case .editor:
            let paths = urls.map { $0.path }
            // fix for neovim: the command template carries a "PATH" placeholder
            // token that must be replaced by the actual path arguments.
            if SupportedApps.is(self, is: .neovim) {
                arguments = arguments.flatMap { $0 == "PATH" ? paths : [$0] }
            } else {
                arguments.append(contentsOf: paths)
            }
        }

        // script
        guard let scriptURL = ScriptManager.shared.getScriptURL(with: Constants.generalScript) else { return }
        // excute
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return }
        guard let script = try? NSUserAppleScriptTask(url: scriptURL) else { return }
        let event = ScriptManager.shared.getScriptEvent(functionName: "openApp", arguments: arguments)
        script.execute(withAppleEvent: event) { (appleEvent, error) in
            if let error = error {
                logw("cannot execute applescript: \(error)")
            }
        }
    }
    
}

public enum CustomMenuTarget: String, Codable {
    case toolbar
    case context
}

public struct CustomMenuAction: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case application
        case cliScript
    }

    public let id: UUID
    public let kind: Kind
    public var name: String
    public var application: App?
    public var scriptPath: String?
    public var arguments: [String]

    public init(application: App) {
        id = UUID()
        kind = .application
        name = application.name
        self.application = application
        scriptPath = nil
        arguments = []
    }

    public init(cliScript name: String, path: String, arguments: [String]) {
        id = UUID()
        kind = .cliScript
        self.name = name
        application = nil
        scriptPath = path
        self.arguments = arguments
    }
}

public enum TerminalCommandLaunchError: LocalizedError {
    case unsupportedTerminal(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedTerminal(let name):
            return "\(name) does not expose a supported command-launch interface."
        }
    }
}

/// Builds a shell-safe AppleScript argument vector for running a script in the
/// configured terminal. Paths and optional arguments remain separate values
/// until the trusted AppleScript quotes each one for the terminal shell.
public enum TerminalCommandLauncher {
    public static func arguments(terminal: App,
                                 scriptPath: String,
                                 workingDirectory: String,
                                 scriptArguments: [String]) throws -> [String] {
        guard let app = SupportedApps.from(name: terminal.name), app.type == .terminal else {
            throw TerminalCommandLaunchError.unsupportedTerminal(terminal.name)
        }

        switch app {
        case .terminal, .iTerm:
            return [app == .terminal ? "terminal" : "iterm",
                    workingDirectory, scriptPath] + scriptArguments
        case .alacritty:
            return ["open", "-a", app.name, "--args",
                    "--working-directory", workingDirectory, "-e", scriptPath] + scriptArguments
        case .kitty:
            return ["open", "-a", app.name, "--args",
                    "--directory", workingDirectory, scriptPath] + scriptArguments
        case .wezterm:
            return ["open", "-a", app.name, "--args",
                    "start", "--cwd", workingDirectory, "--", scriptPath] + scriptArguments
        case .ghostty:
            return ["open", "-a", app.name, "--args",
                    "--working-directory", workingDirectory, "-e", scriptPath] + scriptArguments
        default:
            throw TerminalCommandLaunchError.unsupportedTerminal(app.name)
        }
    }
}

