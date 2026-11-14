# Upstream Integration Notes

This file records upstream changes manually adapted into this checkout. “Adapted” does not mean merged upstream.

## Base

- **Source:** [PR #281](https://github.com/Ji4n1ng/OpenInTerminal/pull/281), fork branch [`agent/fix-macos-27-preferences-hotkeys`](https://github.com/chillednems/OpenInTerminal/tree/agent/fix-macos-27-preferences-hotkeys), revision `6cfb5291fc9c007f1d610dae957858b7e70f1a15`.
- **Status:** Existing checkout baseline; PR #281 is still an upstream pull request, not an upstream merge.
- **Included behavior:** macOS 27 preference migration/persistence, shortcut registration, login-item changes, and Finder Sync scope fixes.

## Adapted: PR #291 — Finder settings bridge

- **Source PR:** [Ji4n1ng/OpenInTerminal#291](https://github.com/Ji4n1ng/OpenInTerminal/pull/291).
- **Implementation source:** [hex-ci/OpenInTerminal commit `71e8a25`](https://github.com/hex-ci/OpenInTerminal/commit/71e8a25f5995242d6e2d795c4a2ca92edbd459de), branch `fix/macos26-27-finder-toolbar`.
- **Status:** Adapted into this working tree; not merged upstream.
- **Changes adapted:**
  - Mirror host preferences to `~/Library/Application Scripts/<Finder Sync extension bundle ID>/shared-settings.plist`, readable by the sandboxed extension without App Group authorization.
  - Read mirrored values in the Finder extension and write-through host preference subscripts.
  - Import legacy App Group values and restore missing host defaults before first-run defaults; publish a full preference snapshot after startup.
  - Clear the mirror when preferences are reset.
  - Handle Finder's sidebar contextual-menu kind and provide a non-empty toolbar fallback when a custom menu is empty.
- **Adaptation note:** Kept PR #281's signing-aware defaults store and versioned migration. The mirror import preserves existing host values and only fills missing values, then publishes the host's active settings.

## Persistence strategy selected

- **Selected:** File-based settings sharing through the Finder extension's Application Scripts directory, the approach proposed by [PR #286](https://github.com/Ji4n1ng/OpenInTerminal/pull/286) and [PR #291](https://github.com/Ji4n1ng/OpenInTerminal/pull/291). It works for this ad-hoc-signed build without claiming another developer team's App Group.
- **Implementation used:** Adapted PR #291's `SharedConfig` design because it provides an explicit typed preference mirror and legacy migration while retaining the existing PR #281 defaults model.
- **Not selected:** [PR #285](https://github.com/Ji4n1ng/OpenInTerminal/pull/285)'s Team-ID-prefixed App Group is appropriate for matching-team signed builds but is not sufficient for this ad-hoc build. Its separate Finder toolbar Quick Toggle change remains unadapted.

- **Build-target decision:** Kept PR #281's minimum deployment target unchanged. Xcode 27 build was verified with the command-line `MACOSX_DEPLOYMENT_TARGET=12.0` override, as documented by PR #281; no permanent OS-support increase was adopted.

## Local feature additions (not from an upstream PR)

- **Source:** User request, November 13, 2026.
- Store separate ordered CLI/application action lists for Finder toolbar and context menus, migrating the prior shared list according to its old per-menu enable flags.
- Add executable CLI-script actions with optional per-line arguments; launch in the currently selected preferred terminal where a direct command-launch adapter exists.
- Fix Finder action dispatch using `NSMenuItem.tag` and a menu-local action snapshot: Finder's XPC menu transport drops `representedObject`, so UUID lookup there silently discarded every custom application/CLI click.
- Keep custom-menu migration one-time so restarts preserve CLI entries, and explicitly size the CLI arguments editor.
- Do not inspect the CLI executable from the Finder extension sandbox: a binary selected in the host picker can be inaccessible there. Pass its path to the out-of-sandbox script/terminal, which executes it with the user's access.
- Replace the menu-target radio buttons with a localized segmented selector above the action list and a description of the selected Finder menu.
- Store independent toolbar/right-click icon styles, migrate the previous shared style without overwriting per-menu choices, and apply each style to application and Copy path items in custom/default menus.

## Reviewed, not adapted

- [PR #285](https://github.com/Ji4n1ng/OpenInTerminal/pull/285): Team-ID-prefixed App Group and a Finder toolbar Quick Toggle behavior. The App Group approach does not solve preference sharing for this ad-hoc-signed local build; Quick Toggle is separate and remains unapplied.
- [PR #286](https://github.com/Ji4n1ng/OpenInTerminal/pull/286): Another Application Scripts preference store approach, plus AppleScript/TCC and deployment-target changes. The preference-store portion overlaps PR #291; unrelated execution and deployment changes remain unapplied.
