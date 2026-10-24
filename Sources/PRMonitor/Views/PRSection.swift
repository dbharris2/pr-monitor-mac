import SwiftUI

extension Color {
    static let gitHubOrange = Color(red: 247 / 255, green: 129 / 255, blue: 102 / 255)
}

enum SectionIcon {
    case sfSymbol(String)
    case asset(String)
}

private struct PRSupplementalStatus {
    enum Kind {
        case approval
        case changesRequested
        case mergeIssue
    }

    let symbol: String
    let text: String
    let color: Color
    let approvers: [Reviewer]
    let changeRequestors: [Reviewer]
    let mergeText: String?
    let kind: Kind
}

private struct PRSupplementalRow: View {
    let status: PRSupplementalStatus
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 4) {
            switch status.kind {
            case .approval:
                PRReviewOutcomeGroup(
                    symbol: status.symbol,
                    action: status.text,
                    color: .green,
                    reviewers: status.approvers,
                    isHovered: isHovered
                )

                if let mergeText = status.mergeText {
                    Text("·")
                        .foregroundStyle(isHovered ? .white.opacity(0.7) : .secondary)
                    Text(mergeText)
                        .foregroundStyle(isHovered ? .white.opacity(0.85) : status.color)
                }

            case .changesRequested:
                PRReviewOutcomeGroup(
                    symbol: status.symbol,
                    action: status.text,
                    color: status.color,
                    reviewers: status.changeRequestors,
                    isHovered: isHovered
                )

                if !status.approvers.isEmpty {
                    Text("·")
                        .foregroundStyle(isHovered ? .white.opacity(0.7) : .secondary)
                    PRReviewOutcomeGroup(
                        symbol: "checkmark.circle.fill",
                        action: "Accepted",
                        color: .green,
                        reviewers: status.approvers,
                        isHovered: isHovered
                    )
                }

            case .mergeIssue:
                statusLabel(
                    symbol: status.symbol,
                    text: status.text,
                    iconColor: isHovered ? .white.opacity(0.85) : status.color,
                    textColor: isHovered ? .white.opacity(0.85) : status.color
                )
            }
        }
        .menuFont(.caption)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func statusLabel(
        symbol: String,
        text: String,
        iconColor: Color,
        textColor: Color
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(iconColor)
            Text(text)
                .foregroundStyle(textColor)
        }
    }
}

private struct PRReviewOutcomeGroup: View {
    let symbol: String
    let action: String
    let color: Color
    let reviewers: [Reviewer]
    let isHovered: Bool

    private var label: String {
        guard !reviewers.isEmpty else { return action }
        return "\(action) by \(reviewers.map(\.displayName).joined(separator: ", "))"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(isHovered ? .white.opacity(0.85) : color)

            if reviewers.isEmpty {
                Text(action)
                    .foregroundStyle(isHovered ? .white.opacity(0.85) : color)
            } else {
                ReviewerAvatars(reviewers: reviewers, isHovered: isHovered)
                    .fixedSize()
            }
        }
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

struct PRSection: View {
    @Environment(\.menuFontScale) private var menuFontScale

    let title: String
    let prs: [PullRequest]
    @Binding var isExpanded: Bool
    var sectionIcon: SectionIcon?
    var sectionColor: Color?
    var showTopSeparator: Bool = false
    var statusColorOverride: Color?
    var onOpenPR: (() -> Void)?
    var onSnoozePR: ((PullRequest, SnoozeDuration) -> Void)?
    var onUnsnoozePR: ((PullRequest) -> Void)?
    var reviewerGroups: [ReviewerGroup] = []
    var canModifyPR: ((PullRequest) -> Bool)?
    var onRequestReviewers: ((PullRequest, ReviewerGroup) -> Void)?
    var onSetDraft: ((PullRequest, Bool) -> Void)?

    var body: some View {
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if showTopSeparator {
                    Divider()
                        .padding(.horizontal, 12)
                }

                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .menuFont(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)

                        if let sectionIcon {
                            switch sectionIcon {
                            case let .sfSymbol(name):
                                Image(systemName: name)
                                    .menuFont(.caption)
                                    .foregroundStyle(sectionColor ?? .primary)
                                    .frame(width: 16 * menuFontScale)
                            case let .asset(name):
                                Image(name)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14 * menuFontScale, height: 14 * menuFontScale)
                                    .foregroundStyle(sectionColor ?? .primary)
                            }
                        }

                        Text(title)
                            .menuFont(.headline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Spacer()

                        if let sectionColor {
                            Text("\(prs.count)")
                                .menuFont(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(sectionColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(sectionColor.opacity(0.15))
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if isExpanded {
                    ForEach(prs) { pr in
                        PRRow(
                            pr: pr,
                            statusColorOverride: statusColorOverride,
                            onOpen: onOpenPR,
                            onSnooze: onSnoozePR.map { callback in { pr, duration in callback(pr, duration) } },
                            onUnsnooze: onUnsnoozePR.map { callback in { pr in callback(pr) } },
                            reviewerGroups: reviewerGroups,
                            canModifyPR: canModifyPR,
                            onRequestReviewers: onRequestReviewers,
                            onSetDraft: onSetDraft
                        )
                    }
                }
            }
        }
    }
}

struct PRRow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.menuFontScale) private var menuFontScale

    let pr: PullRequest
    var statusColorOverride: Color?
    var onOpen: (() -> Void)?
    var onSnooze: ((PullRequest, SnoozeDuration) -> Void)?
    var onUnsnooze: ((PullRequest) -> Void)?
    var reviewerGroups: [ReviewerGroup] = []
    var canModifyPR: ((PullRequest) -> Bool)?
    var onRequestReviewers: ((PullRequest, ReviewerGroup) -> Void)?
    var onSetDraft: ((PullRequest, Bool) -> Void)?
    @State private var isHovered = false

    private var statusColor: Color {
        if let override = statusColorOverride {
            return override
        }
        if pr.isDraft {
            return .secondary
        }
        if pr.reviewDecision == .changesRequested {
            return .red
        }
        if pr.hasApproval {
            return .green
        }
        return .gitHubOrange
    }

    private var supplementalStatus: PRSupplementalStatus? {
        let mergeStatus = pr.mergeStateStatus
        let mergeLabel: String? = switch mergeStatus {
        case .behind: nil
        case .blocked: nil
        case .clean: "Ready to merge"
        case .dirty: "Merge conflict"
        case .hasHooks: "Ready to merge"
        case .unknown: "Checking merge status"
        case .unstable: "Checks not passing"
        case nil: nil
        }

        if pr.reviewDecision == .changesRequested {
            let changeRequestors = pr.changeRequestors ?? []
            return PRSupplementalStatus(
                symbol: "xmark.circle.fill",
                text: "Changes requested",
                color: .red,
                approvers: pr.approvers,
                changeRequestors: changeRequestors,
                mergeText: nil,
                kind: .changesRequested
            )
        }

        if pr.hasApproval {
            let statusTint: Color = switch mergeStatus {
            case .unstable:
                .orange
            case .dirty:
                .red
            case .unknown:
                .secondary
            case .behind, .blocked, .clean, .hasHooks, nil:
                .green
            }
            return PRSupplementalStatus(
                symbol: "checkmark.circle.fill",
                text: "Accepted",
                color: statusTint,
                approvers: pr.approvers,
                changeRequestors: [],
                mergeText: mergeLabel,
                kind: .approval
            )
        }

        return switch mergeStatus {
        case .dirty:
            PRSupplementalStatus(
                symbol: "xmark.circle.fill",
                text: "Merge conflict",
                color: .red,
                approvers: [],
                changeRequestors: [],
                mergeText: nil,
                kind: .mergeIssue
            )
        case .unstable:
            PRSupplementalStatus(
                symbol: "clock.fill",
                text: "Checks not passing",
                color: .orange,
                approvers: [],
                changeRequestors: [],
                mergeText: nil,
                kind: .mergeIssue
            )
        case .behind, .blocked, .clean, .hasHooks, .unknown, nil:
            nil
        }
    }

    var body: some View {
        Button {
            onOpen?()
            NSWorkspace.shared.open(pr.url)
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(statusColor)
                    .frame(width: 3)
                    .padding(.vertical, 3)

                HStack(spacing: 8) {
                    AsyncImage(url: pr.authorAvatarURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 24 * menuFontScale, height: 24 * menuFontScale)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(pr.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(isHovered ? .white : .primary)

                            Spacer()

                            Text(relativeTime(from: pr.updatedAt))
                                .menuFont(.caption)
                                .foregroundStyle(isHovered ? .white.opacity(0.7) : .secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }

                        HStack(spacing: 6) {
                            Text("\(appState.displayRepositoryName(pr.repository)) #\(String(pr.number))")
                                .lineLimit(1)
                                .truncationMode(.head)
                            Text("+\(pr.additions)")
                                .fixedSize()
                                .foregroundStyle(isHovered ? .white.opacity(0.8) : .green)
                            Text("-\(pr.deletions)")
                                .fixedSize()
                                .foregroundStyle(isHovered ? .white.opacity(0.8) : .red)
                            Text("@\(pr.changedFiles)")
                                .fixedSize()
                            HStack(spacing: 1) {
                                Image(systemName: "bubble.right")
                                Text("\(pr.totalComments)")
                            }
                            .fixedSize()

                            Spacer()

                            ReviewerAvatars(reviewers: pr.reviewers, isHovered: isHovered)
                                .fixedSize()
                        }
                        .menuFont(.caption)
                        .foregroundStyle(isHovered ? .white.opacity(0.8) : .secondary)

                        if let supplementalStatus {
                            PRSupplementalRow(status: supplementalStatus, isHovered: isHovered)
                        }
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
            }
            .frame(minHeight: supplementalStatus == nil ? 50 : 64)
            .padding(.leading, 12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if canModifyPR?(pr) == true {
                if let onRequestReviewers, !reviewerGroups.isEmpty {
                    Menu("Request reviewers") {
                        ForEach(reviewerGroups) { group in
                            Button(group.name) { onRequestReviewers(pr, group) }
                        }
                    }
                }

                if let onSetDraft {
                    Button(pr.isDraft ? "Mark ready for review" : "Convert to draft") {
                        onSetDraft(pr, !pr.isDraft)
                    }
                }
            }

            if let onSnooze {
                Menu("Snooze") {
                    ForEach(SnoozeDuration.allCases, id: \.self) { duration in
                        Button(duration.displayName) { onSnooze(pr, duration) }
                    }
                }
            }
            if let onUnsnooze {
                Button("Un-snooze") { onUnsnooze(pr) }
            }
        }
    }
}

// MARK: - Reviewer Avatars

private struct ReviewerAvatars: View {
    let reviewers: [Reviewer]
    let isHovered: Bool

    private let avatarSize: CGFloat = 18
    private let overlap: CGFloat = 6
    private let maxVisible = 3

    var body: some View {
        if reviewers.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                let visible = Array(reviewers.prefix(maxVisible))
                ZStack(alignment: .leading) {
                    ForEach(Array(visible.enumerated()), id: \.element) { index, reviewer in
                        avatarView(for: reviewer)
                            .offset(x: CGFloat(index) * (avatarSize - overlap))
                    }
                }
                .frame(width: avatarSize + CGFloat(max(visible.count - 1, 0)) * (avatarSize - overlap), alignment: .leading)

                if reviewers.count > maxVisible {
                    Text("+\(reviewers.count - maxVisible)")
                        .menuFont(.caption2)
                        .foregroundStyle(isHovered ? .white.opacity(0.7) : .secondary)
                        .padding(.leading, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func avatarView(for reviewer: Reviewer) -> some View {
        let shape: AnyShape = reviewer.kind == .team
            ? AnyShape(RoundedRectangle(cornerRadius: 4))
            : AnyShape(Circle())

        AsyncImage(url: reviewer.avatarURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: reviewer.kind == .team ? "person.2.fill" : "person.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(isHovered ? .white.opacity(0.6) : .secondary)
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(shape)
        .overlay(shape.stroke(
            isHovered ? Color(nsColor: .selectedContentBackgroundColor) : Color(nsColor: .windowBackgroundColor),
            lineWidth: 1.5
        ))
        .help(reviewer.kind == .team ? "\(reviewer.displayName) (team)" : reviewer.displayName)
    }
}

// MARK: - Relative Time

func relativeTime(from date: Date) -> String {
    let now = Date()
    let seconds = now.timeIntervalSince(date)

    if seconds < 60 {
        return "now"
    } else if seconds < 3600 {
        let minutes = Int(seconds / 60)
        return "\(minutes)m ago"
    } else if seconds < 86400 {
        let hours = Int(seconds / 3600)
        return "\(hours)h ago"
    } else if seconds < 604_800 {
        let days = Int(seconds / 86400)
        return "\(days)d ago"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

#Preview {
    VStack {
        PRSection(
            title: "Needs my review",
            prs: [
                PullRequest(
                    id: "1",
                    number: 42,
                    title: "feat: Add dark mode support with a really long title that should truncate",
                    url: URL(string: "https://github.com/owner/repo/pull/42")!,
                    repository: "owner/repo",
                    author: "alice",
                    authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4"),
                    createdAt: Date(),
                    updatedAt: Date().addingTimeInterval(-7200),
                    isDraft: false,
                    reviewDecision: nil,
                    viewerDidApprove: false,
                    hasAnyApproval: false,
                    additions: 1404,
                    deletions: 99,
                    changedFiles: 17,
                    totalComments: 3,
                    reviewers: [
                        Reviewer(kind: .user, id: "bob", displayName: "bob", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/2?v=4")),
                        Reviewer(
                            kind: .team,
                            id: "frontend",
                            displayName: "Frontend Team",
                            avatarURL: URL(string: "https://avatars.githubusercontent.com/t/1?v=4")
                        ),
                        Reviewer(
                            kind: .user,
                            id: "dave",
                            displayName: "dave",
                            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/4?v=4")
                        ),
                    ]
                )
            ],
            isExpanded: .constant(true),
            sectionIcon: .asset("CodeReviewIcon"),
            sectionColor: .gitHubOrange
        )

        PRSection(
            title: "Drafts",
            prs: [],
            isExpanded: .constant(false),
            sectionIcon: .sfSymbol("doc.text.fill"),
            sectionColor: .secondary,
            showTopSeparator: true
        )
    }
    .frame(width: 380)
    .environmentObject(AppState.preview)
}
