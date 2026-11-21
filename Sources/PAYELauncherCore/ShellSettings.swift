import Foundation

/// Reads `bptshell-settings.ini`, the settings file of HMRC's own user interface.
public enum ShellSettings {
    public static let defaultPort = 46729

    /// The port from a settings file text, or nil if there is no valid port.
    ///
    /// HMRC documents that the port can be changed in this file but not the key
    /// name, so any key that contains "port" is accepted. Comments start with
    /// `;` or `#`.
    public static func port(fromINI text: String) -> Int? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#"), !line.hasPrefix("[") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].lowercased().contains("port"),
                  let port = Int(parts[1]), (1024...65535).contains(port) else { continue }
            return port
        }
        return nil
    }

    /// The port from the settings file at `url`, or the default port.
    public static func port(at url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return defaultPort }
        return port(fromINI: text) ?? defaultPort
    }
}
