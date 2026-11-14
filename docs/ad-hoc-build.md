# Ad-hoc build: installation and security notes

This is an unofficial OpenInTerminal fork. The app is ad-hoc signed (`codesign --sign -`), has no Apple Developer Team ID, and is **not notarized**. A valid ad-hoc signature checks bundle integrity; it does not establish a verified publisher or imply Apple approval.

## Install

1. Quit any existing OpenInTerminal instance and move `OpenInTerminal.app` to `/Applications`, replacing the old app.
2. macOS may block this downloaded, unnotarized app. Only if you trust this fork and have checked the download, remove its quarantine attribute:
   ```sh
   xattr -dr com.apple.quarantine /Applications/OpenInTerminal.app
   ```
3. Open the app, then enable its Finder extension under **System Settings → General → Login Items & Extensions → Finder**.
4. Configure the preferred terminal/editor and the independent **Finder Toolbar / Right-click Menu** lists in Preferences.
5. When macOS asks to control Terminal or iTerm, review and allow the Automation request to use CLI actions.

If Finder does not show the extension after replacing an older build, re-register the installed bundle and restart Finder:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/OpenInTerminal.app
pluginkit -a /Applications/OpenInTerminal.app/Contents/PlugIns/OpenInTerminalFinderExtension.appex
pluginkit -e use -i wang.jianing.app.OpenInTerminal.OpenInTerminalFinderExtension
killall Finder
```

## Preferences and compatibility

This fork shares preferences through `~/Library/Application Scripts/wang.jianing.app.OpenInTerminal.OpenInTerminalFinderExtension/shared-settings.plist`. It does not require authorization for the upstream developer's App Group. The host writes the snapshot; the sandboxed Finder extension reads it.

The release contains Apple Silicon (`arm64`) and Intel (`x86_64`) code. It is built with Xcode 27 using a macOS 12 deployment-target override; the repository's original minimum target is unchanged. Runtime validation was performed on macOS 27; older versions are unverified.

See [configuration instructions](https://github.com/kvn1351/OpenInTerminal/blob/main/Resources/README-Config.md) and [integration provenance](https://github.com/kvn1351/OpenInTerminal/blob/main/UPSTREAM_INTEGRATIONS.md). Historical signed-build reports refer to separate artifacts, not this ad-hoc release.
