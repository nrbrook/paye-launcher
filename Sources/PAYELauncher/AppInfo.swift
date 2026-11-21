import Foundation

enum AppInfo {
    static let name = "PAYE Launcher"
    static let windowTitle = "Basic PAYE Tools"
    static let projectURL = URL(string: "https://github.com/nrbrook/paye-launcher")!
    static let issuesURL = URL(string: "https://github.com/nrbrook/paye-launcher/issues")!
    static let userGuideURL = URL(string: "https://www.gov.uk/government/publications/basic-paye-tools-user-guide")!
    static let serviceIssuesURL = URL(
        string: "https://www.gov.uk/government/publications/basic-paye-tools-service-availability-and-issues/basic-paye-service-availability-and-issues"
    )!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
