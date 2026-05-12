import ActivityKit
import SwiftUI
import WidgetKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !hex.isEmpty, hex.count == 6, let value = UInt64(hex, radix: 16) else {
            self.init(.clear)
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

@available(iOS 17.0, *)
struct CodingStatusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodingStatusAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottomView(context: context)
                }
            } compactLeading: {
                if !context.state.activeImageName.isEmpty {
                    Image(context.state.activeImageName)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(Color(hex: context.state.activeColor))
                        .frame(width: 20, height: 20)
                }
            } compactTrailing: {
                if context.state.activeRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            } minimal: {
                if !context.state.activeImageName.isEmpty {
                    Image(context.state.activeImageName)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(Color(hex: context.state.activeColor))
                        .frame(width: 20, height: 20)
                }
            }
        }
    }

    // MARK: - Expanded Bottom View

    @ViewBuilder
    private func expandedBottomView(context: ActivityViewContext<CodingStatusAttributes>) -> some View {
        if context.state.activeImageName.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                // Active agent (first row)
                HStack(spacing: 10) {
                    Image(context.state.activeImageName)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(Color(hex: context.state.activeColor))
                        .frame(width: 22, height: 22)
                    Text(context.state.activeDisplayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(context.state.activeProject)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if context.state.activeRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .modifier(PulsingDot())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Other agents (same row style)
                if !context.state.otherAgents.isEmpty {
                    Divider()
                        .padding(.horizontal, 18)

                    ForEach(context.state.otherAgents) { agent in
                        HStack(spacing: 10) {
                            Image(agent.imageName)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(Color(hex: agent.color))
                                .frame(width: 20, height: 20)
                            Text(agent.displayName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(agent.project)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            if agent.running {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<CodingStatusAttributes>) -> some View {
        if context.state.activeImageName.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    Image(context.state.activeImageName)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(Color(hex: context.state.activeColor))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.activeDisplayName)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(context.state.activeProject)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if context.state.activeRunning {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .modifier(PulsingDot())
                    }
                }

                // Other agents summary with icons
                if !context.state.otherAgents.isEmpty {
                    Divider()
                    HStack(spacing: 6) {
                        let shown = min(context.state.otherAgents.count, 3)
                        ForEach(Array(context.state.otherAgents.prefix(shown))) { agent in
                            Image(agent.imageName)
                                .resizable()
                                .renderingMode(.template)
                                .foregroundColor(Color(hex: agent.color))
                                .frame(width: 16, height: 16)
                        }
                        let remaining = context.state.otherAgents.count - shown
                        if remaining > 0 {
                            Text("+\(remaining) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding()
        }
    }
}

struct PulsingDot: ViewModifier {
    @State private var isPulsing = false
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
