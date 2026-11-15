import AppKit
import FlowCore
import Foundation

/// Finds the apps installed on this Mac so Flow can open and control any of them by name
/// (not just Mail, Calendar, Notes, Finder and Safari). Read-only: it lists app bundles in the
/// standard Applications folders and reads their names and bundle identifiers.
public enum InstalledAppScanner {
    public static let folders: [URL] = {
        var urls = [
            "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications", "/System/Cryptexes/App/System/Applications",
        ].map { URL(fileURLWithPath: $0) }
        urls.append(FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"))
        return urls
    }()

    /// Spoken nicknames for common apps (only used when that app is installed).
    public static let nicknames: [String: [String]] = [
        "com.apple.systempreferences": ["settings", "system preferences", "preferences"],
        "com.microsoft.VSCode": ["vs code", "vscode", "code"],
        "com.apple.iCal": ["calendar", "ical"],
        "com.apple.MobileSMS": ["imessage", "imessages", "texts"],
        "com.apple.AddressBook": ["address book"],
        "com.apple.Terminal": ["the terminal"],
        "com.apple.ActivityMonitor": ["task manager"],
        "com.google.Chrome": ["chrome"],
        "com.apple.calculator": ["calc"],
        "com.apple.TextEdit": ["text edit"],
        "com.apple.finder": ["files"],
    ]

    /// Scans the folders (one level, plus app bundles inside plain subfolders).
    public static func scan(folders: [URL] = folders) -> [AppDirectory.Entry] {
        var seen: Set<String> = []
        var entries: [AppDirectory.Entry] = []
        func add(_ url: URL) {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !seen.contains(id.lowercased()) else { return }
            let info = bundle.localizedInfoDictionary ?? [:]
            let plist = bundle.infoDictionary ?? [:]
            let display = (info["CFBundleDisplayName"] as? String) ?? (plist["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String) ?? (plist["CFBundleName"] as? String)
            let fileName = url.deletingPathExtension().lastPathComponent
            let name = (display?.isEmpty == false ? display! : fileName)
            seen.insert(id.lowercased())
            var aliases = [fileName]
            aliases += nicknames[id] ?? []
            entries.append(AppDirectory.Entry(app: KnownApp(name: name, bundleIdentifier: id), aliases: aliases))
        }
        let fm = FileManager.default
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                if item.pathExtension == "app" { add(item); continue }
                // e.g. /Applications/Adobe Something/Some App.app
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue,
                   let inner = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    inner.filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        // Finder lives outside the Applications folders.
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        // "the browser" → the default web browser.
        if let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
           let id = Bundle(url: browser)?.bundleIdentifier,
           let i = entries.firstIndex(where: { $0.app.bundleIdentifier == id }) {
            entries[i] = AppDirectory.Entry(app: entries[i].app, aliases: entries[i].aliases + ["browser", "web browser", "the browser"])
        }
        return entries
    }

    /// Scans and installs the result as Flow's app directory. Returns how many apps were found.
    @discardableResult
    public static func installDirectory() -> Int {
        let entries = scan()
        AppDirectory.install(entries)
        return entries.count
    }
}
