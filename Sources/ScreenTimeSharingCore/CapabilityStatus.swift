import Foundation

public enum ScreenTimeCapabilityStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case fullAppDetail
    case aggregateOnly
    case unavailable
}

public struct ScreenTimeCapability: Codable, Equatable, Sendable {
    public var status: ScreenTimeCapabilityStatus
    public var reason: String?

    public init(status: ScreenTimeCapabilityStatus, reason: String? = nil) {
        self.status = status
        self.reason = reason
    }

    public static let fullAppDetail = ScreenTimeCapability(status: .fullAppDetail)

    public static func aggregateOnly(reason: String? = nil) -> ScreenTimeCapability {
        ScreenTimeCapability(status: .aggregateOnly, reason: reason)
    }

    public static func unavailable(reason: String) -> ScreenTimeCapability {
        ScreenTimeCapability(status: .unavailable, reason: reason)
    }

    public var allowsUpload: Bool {
        status == .fullAppDetail || status == .aggregateOnly
    }

    public var allowsPerAppRows: Bool {
        status == .fullAppDetail
    }
}
