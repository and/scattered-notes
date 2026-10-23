import Foundation

public enum CategoryType: String, Codable, CaseIterable, Sendable {
    case inbox = "inbox"
    case project = "project"
    case area = "area"
    
    public var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .project: return "Projects"
        case .area: return "Areas"
        }
    }
    
    public var iconName: String {
        switch self {
        case .inbox: return "tray.fill"
        case .project: return "folder.fill"
        case .area: return "square.stack.3d.up.fill"
        }
    }
}

public struct ProjectArea: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var type: CategoryType
    public var customIcon: String?
    
    public init(name: String, type: CategoryType, customIcon: String? = nil) {
        self.id = "\(type.rawValue):\(name.lowercased())"
        self.name = name
        self.type = type
        self.customIcon = customIcon
    }
    
    public var iconName: String {
        if let custom = customIcon, !custom.isEmpty {
            return custom
        }
        return type.iconName
    }
    
    public static let inbox = ProjectArea(name: "Inbox", type: .inbox)
}
