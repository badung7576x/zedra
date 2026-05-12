import ActivityKit

struct CodingStatusAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var activeImageName: String
        var activeDisplayName: String
        var activeColor: String
        var activeRunning: Bool
        var activeProject: String
        var otherAgents: [AgentStatus]
    }
}

struct AgentStatus: Codable, Hashable, Identifiable {
    var id: String
    var imageName: String
    var displayName: String
    var color: String
    var running: Bool
    var project: String
}
