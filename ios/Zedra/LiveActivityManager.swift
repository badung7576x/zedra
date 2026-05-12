import ActivityKit
import Foundation

struct TerminalStatus {
    let imageName: String
    let displayName: String
    let color: String
    let running: Bool
    let project: String
    var isActive: Bool
}

@available(iOS 17.0, *)
class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<CodingStatusAttributes>?
    private var terminalStatuses: [String: TerminalStatus] = [:]
    private var activityUpdatesTask: Task<Void, Never>?

    init() {
        observeActivityUpdates()
    }

    // Detect when iOS dismisses the activity (user tap, system kill)
    // so we clear stale references and can recreate on next update.
    private func observeActivityUpdates() {
        activityUpdatesTask = Task { [weak self] in
            for await activity in Activity<CodingStatusAttributes>.activityUpdates {
                guard let self else { return }
                switch activity.activityState {
                case .ended, .dismissed:
                    if self.activity?.id == activity.id {
                        NSLog("[LiveActivity] activity ended/dismissed by system: id=%@", activity.id)
                        self.activity = nil
                    }
                default:
                    break
                }
            }
        }
    }

    func update(
        terminalId: String,
        imageName: String,
        displayName: String,
        color: String,
        running: Bool,
        project: String,
        isActive: Bool
    ) {
        NSLog("[LiveActivity] update() called: tid=%@ image=%@ name=%@ running=%d isActive=%d terminals=%d", terminalId, imageName, displayName, running, isActive, terminalStatuses.count)

        if !running {
            terminalStatuses.removeValue(forKey: terminalId)
        } else {
            terminalStatuses[terminalId] = TerminalStatus(
                imageName: imageName, displayName: displayName,
                color: color, running: running,
                project: project, isActive: isActive
            )
        }

        if isActive {
            for (id, _) in terminalStatuses where id != terminalId {
                terminalStatuses[id]?.isActive = false
            }
        }

        let active = terminalStatuses.values.first { $0.isActive }
            ?? terminalStatuses.values.first { $0.running }

        let otherAgents = terminalStatuses.values
            .filter { !$0.isActive && $0.running }
            .enumerated()
            .map { index, entry in
                AgentStatus(
                    id: "\(entry.displayName)-\(entry.project)-\(index)",
                    imageName: entry.imageName, displayName: entry.displayName,
                    color: entry.color, running: entry.running, project: entry.project
                )
            }

        let content = buildContent(active: active, otherAgents: otherAgents)

        if let activity = activity {
            if activity.activityState == .active {
                NSLog("[LiveActivity] updating existing activity")
                Task { await activity.update(content) }
                return
            } else {
                NSLog("[LiveActivity] dead activity reference (state=%@), clearing", String(describing: activity.activityState))
                self.activity = nil
            }
        }

        if active != nil {
            createActivity(content: content)
        } else {
            NSLog("[LiveActivity] no running agents, skipping activity creation")
        }
    }

    private func buildContent(active: TerminalStatus?, otherAgents: [AgentStatus]) -> ActivityContent<CodingStatusAttributes.ContentState> {
        if let active {
            return ActivityContent(
                state: CodingStatusAttributes.ContentState(
                    activeImageName: active.imageName,
                    activeDisplayName: active.displayName,
                    activeColor: active.color,
                    activeRunning: active.running,
                    activeProject: active.project,
                    otherAgents: otherAgents
                ),
                staleDate: Calendar.current.date(byAdding: .minute, value: 5, to: Date())
            )
        }
        return ActivityContent(
            state: CodingStatusAttributes.ContentState(
                activeImageName: "", activeDisplayName: "",
                activeColor: "", activeRunning: false,
                activeProject: "", otherAgents: []
            ),
            staleDate: Calendar.current.date(byAdding: .minute, value: 5, to: Date())
        )
    }

    private func createActivity(content: ActivityContent<CodingStatusAttributes.ContentState>) {
        let auth = ActivityAuthorizationInfo().areActivitiesEnabled
        NSLog("[LiveActivity] creating new activity, areActivitiesEnabled=%d", auth)
        guard auth else {
            NSLog("[LiveActivity] ABORT: activities not enabled in Settings")
            return
        }
        do {
            activity = try Activity.request(
                attributes: CodingStatusAttributes(), content: content
            )
            NSLog("[LiveActivity] activity started successfully: id=%@", activity?.id ?? "nil")
        } catch {
            NSLog("[LiveActivity] FAILED to start activity: %@", error.localizedDescription)
        }
    }

    // Only called on explicit workspace disconnect (mark_disconnected in Rust).
    func end() {
        NSLog("[LiveActivity] end() called, hasActivity=%d, terminals=%d", activity != nil, terminalStatuses.count)
        guard let activity = activity else { return }
        terminalStatuses.removeAll()
        let finalContent = ActivityContent(
            state: CodingStatusAttributes.ContentState(
                activeImageName: "", activeDisplayName: "",
                activeColor: "", activeRunning: false,
                activeProject: "", otherAgents: []
            ),
            staleDate: nil
        )
        Task { await activity.end(finalContent, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    deinit {
        activityUpdatesTask?.cancel()
    }
}
