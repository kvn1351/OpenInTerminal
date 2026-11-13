//
//  ScriptManager.swift
//  OpenInTerminalCore
//
//  Created by Jianing Wang on 2020/12/7.
//  Copyright © 2020 Jianing Wang. All rights reserved.
//

import Foundation
import Carbon

public class ScriptManager {
    
    public static var shared = ScriptManager()
    
    // MARK: - Get AppleScript
    
    /// This script requires parameters to be passed in.
    ///
    /// `argv`: the full command as a list of discrete argument strings, e.g.
    /// `{"/usr/bin/open", "-a", "Terminal", "/Users/user/My Folder"}`. Each
    /// element is shell-quoted individually with `quoted form of`, so an
    /// argument that contains spaces or shell metacharacters (for example a
    /// crafted file/folder name) is passed to `open` verbatim and can never be
    /// interpreted as shell syntax. This is the injection-safe replacement for
    /// the previous single pre-escaped command string.
    public func getGeneralScript() -> String {
        let script = """
        on openApp(argv)
            set theCommand to ""
            repeat with theArgument in argv
                set theCommand to theCommand & quoted form of (theArgument as text) & " "
            end repeat
            tell application "Finder"
                activate
                do shell script theCommand
            end tell
        end openApp
        """
        return script
    }
    
    public func getGeneralScriptName() -> String {
        return Constants.generalScript
    }
    
    /// Open path in a new tab of Terminal
    public func getTerminalNewTabAppleScript() -> String {
        let script = """
        on openApp(command)
            if not application "Terminal" is running then
                tell application "Terminal"
                    do script command
                    activate
                end tell
            else
                tell application "Terminal"
                    if not (exists window 1) then
                        do script command
                        activate
                    else
                        activate
                        tell application "System Events" to keystroke "t" using command down
                        repeat while contents of selected tab of window 1 starts with linefeed
                            delay 0.01
                        end repeat
                        do script command in window 1
                    end if
                end tell
            end if
        end openApp
        """
        return script
    }
    
    public func getTerminalNewTabScriptName() -> String {
        return Constants.terminalNewTabScript
    }
    
    public func getTerminalNewTabCommand(path: String) -> String {
        let command = "cd \(path.terminalPathEscaped())"
        return command
    }

    public func getCLICommandScriptName(mode: String) -> String {
        switch mode {
        case "terminal": return Constants.cliCommandTerminalScript
        case "iterm": return Constants.cliCommandItermScript
        default: return Constants.cliCommandOpenScript
        }
    }

    /// Each terminal-specific script has its own compiled command dictionary;
    /// the generic open script avoids requiring an installed terminal's AppleScript dictionary.
    public func getCLICommandAppleScript(mode: String) -> String {
        switch mode {
        case "terminal":
            return """
            on runCLIAction(argv)
                set workingDirectory to item 2 of argv as text
                set scriptPath to item 3 of argv as text
                set commandText to "cd -- " & quoted form of workingDirectory & " && " & quoted form of scriptPath
                repeat with index from 4 to (count of argv)
                    set commandText to commandText & " " & quoted form of ((item index of argv) as text)
                end repeat
                tell application "Terminal"
                    activate
                    do script commandText
                end tell
            end runCLIAction
            """
        case "iterm":
            return """
            on runCLIAction(argv)
                set workingDirectory to item 2 of argv as text
                set scriptPath to item 3 of argv as text
                set shellCommand to "cd -- " & quoted form of workingDirectory & " && " & quoted form of scriptPath
                repeat with index from 4 to (count of argv)
                    set shellCommand to shellCommand & " " & quoted form of ((item index of argv) as text)
                end repeat
                set commandText to "/bin/zsh -l -c " & quoted form of (shellCommand & "; exec /bin/zsh -l")
                tell application id "com.googlecode.iterm2"
                    activate
                    create window with default profile command commandText
                end tell
            end runCLIAction
            """
        default:
            return """
            on runCLIAction(argv)
                set commandText to quoted form of "/usr/bin/open"
                repeat with index from 2 to (count of argv)
                    set commandText to commandText & " " & quoted form of ((item index of argv) as text)
                end repeat
                do shell script commandText
            end runCLIAction
            """
        }
    }
    
    /// Open path in a new tab of Terminal
    public func getTerminalNewTabAppleScript(url: URL) -> String {
        let script = """
        if not application "Terminal" is running then
            tell application "Terminal"
                do script "cd \(url.path.terminalPathEscaped())"
                activate
            end tell
        else
            tell application "Terminal"
                if not (exists window 1) then
                    do script "cd \(url.path.terminalPathEscaped())"
                    activate
                else
                    activate
                    tell application "System Events" to keystroke "t" using command down
                    repeat while contents of selected tab of window 1 starts with linefeed
                        delay 0.01
                    end repeat
                    do script "cd \(url.path.terminalPathEscaped())" in window 1
                end if
            end tell
        end if
        """
        return script
    }
    
    
    // MARK: - Utils
    
    public func getScriptURL(with name: String) -> URL? {
        let scriptFolderURL = try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        guard let url = scriptFolderURL else { return nil }
        let fileURL = url
            .appendingPathComponent(name)
            .appendingPathExtension("scpt")
        return fileURL
    }
    
    func getScriptEvent(functionName: String, arguments: [String]) -> NSAppleEventDescriptor {
        // The handler takes a single parameter that is itself a list of
        // argument strings. Build that inner list, delivering each argument as
        // a discrete descriptor so no shell-sensitive concatenation happens on
        // this side, then wrap it as the sole positional parameter.
        let argumentList = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            argumentList.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }

        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(argumentList, at: 1)

        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setDescriptor(NSAppleEventDescriptor(string: functionName), forKeyword: AEKeyword(keyASSubroutineName))
        event.setDescriptor(parameters, forKeyword: AEKeyword(keyDirectObject))
        return event
    }

    public func getCLICommandScriptEvent(arguments: [String]) -> NSAppleEventDescriptor {
        getScriptEvent(functionName: "runCLIAction", arguments: arguments)
    }
    
    
    // MARK: - Deprecated Functions
    
    /// **[Deprecated]** This script can run independently without additional parameters.
    @available(*, deprecated, message: "Use getGeneralScript()")
    func getAppleScript(app: App) -> String {
        switch app.type {
        case .terminal:
            let openCommand = DefaultsManager.shared.getOpenCommand(app, escapeCount: 2)
            let script = """
            tell application "Finder"
                set finderSelList to selection as alias list
                
                if finderSelList ≠ {} then
                    set theSelected to item 1 of finderSelList
                    set thePath to POSIX path of (contents of theSelected)
                    try
                        do shell script "cd " & quoted form of thePath
                    on error
                        set thePath to POSIX path of ((container of theSelected) as text)
                    end try
                end if
                
                if finderSelList = {} then
                    tell application "Finder"
                        try
                            set thePath to POSIX path of ((target of front Finder window) as text)
                        on error
                            set thePath to POSIX path of (path to desktop)
                        end try
                    end tell
                end if
            end tell

            do shell script "\(openCommand) " & quoted form of thePath
            """
            return script
        case .editor:
            let openCommand = DefaultsManager.shared.getOpenCommand(app, escapeCount: 2)
            let script = """
            tell application "Finder"
                set pathList to {}
                
                set finderSelList to selection as alias list
                
                if finderSelList = {} then
                    tell application "Finder"
                        try
                            set thePath to POSIX path of ((target of front Finder window) as text)
                        on error
                            set thePath to POSIX path of (path to desktop)
                        end try
                        set end of pathList to thePath
                    end tell
                end if
                
                if finderSelList ≠ {} then
                    repeat with theSelected in finderSelList
                        set thePath to POSIX path of (contents of theSelected)
                        set end of pathList to thePath
                    end repeat
                end if
                
            end tell

            set scriptStr to "\(openCommand)"

            repeat with thePath in pathList
                set scriptStr to scriptStr & " " & quoted form of thePath
            end repeat

            do shell script scriptStr
            """
            return script
        }
    }
    /// **[Deprecated]** Open path in a new tab of Terminal
    func getTerminalNewTabAppleScript2() -> String {
        let script = """
        tell application "Finder"
            set finderSelList to selection as alias list
            
            if finderSelList ≠ {} then
                set theSelected to item 1 of finderSelList
                set thePath to POSIX path of (contents of theSelected)
                try
                    do shell script "cd " & quoted form of thePath
                on error
                    set thePath to POSIX path of ((container of theSelected) as text)
                end try
            end if
            
            if finderSelList = {} then
                tell application "Finder"
                    try
                        set thePath to POSIX path of ((target of front Finder window) as text)
                    on error
                        set thePath to POSIX path of (path to desktop)
                    end try
                end tell
            end if
        end tell

        if not application "Terminal" is running then
            tell application "Terminal"
                do script "cd " & quoted form of thePath
                activate
            end tell
        else
            tell application "Terminal"
                if not (exists window 1) then
                    do script "cd " & quoted form of thePath
                    activate
                else
                    activate
                    tell application "System Events" to keystroke "t" using command down
                    repeat while contents of selected tab of window 1 starts with linefeed
                        delay 0.01
                    end repeat
                    do script "cd " & quoted form of thePath in window 1
                end if
            end tell
        end if
        """
        return script
    }
}

