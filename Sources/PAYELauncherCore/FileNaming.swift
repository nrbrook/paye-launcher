import Foundation

public enum FileNaming {
    /// A file URL in `directory` that does not exist yet: "form.pdf", then
    /// "form 2.pdf", "form 3.pdf" and so on.
    public static func uniqueURL(in directory: URL, name: String, exists: (URL) -> Bool) -> URL {
        let safeName = sanitised(name)
        var url = directory.appendingPathComponent(safeName)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while exists(url) {
            url = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return url
    }

    /// Removes path separators and leading dots from a suggested file name.
    public static func sanitised(_ name: String) -> String {
        var result = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while result.hasPrefix(".") { result.removeFirst() }
        return result.isEmpty ? "download" : result
    }
}
