import SwiftUI

extension Color {
    static let gitHubOrange = Color(red: 247 / 255, green: 129 / 255, blue: 102 / 255)
}

enum SectionIcon {
    case sfSymbol(String)
    case asset(String)
}

struct PRSection: View {
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

    var body: some View {
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    if let sectionIcon {
                        switch sectionIcon {
                        case let .sfSymbol(name):
                            if prs.isEmpty {
                                Image(systemName: name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 16)
                            } else {
                                Image(systemName: name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(sectionColor ?? .primary)
                                    .frame(width: 16)
                            }
                        case let .asset(name):
                            if prs.isEmpty {
                                Image(name)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Image(name)
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(sectionColor ?? .primary)
                            }
                        }
                    }

                    Text(title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(prs.isEmpty ? .secondary : .primary)

                    Spacer()

                    if !prs.isEmpty, let sectionColor {
                        Text("\(prs.count)")
                            .font(.caption)
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

            if isExpanded, !prs.isEmpty {
                ForEach(prs) { pr in
                    PRRow(
                        pr: pr,
                        statusColorOverride: statusColorOverride,
                        onOpen: onOpenPR,
                        onSnooze: onSnoozePR.map { callback in { pr, duration in callback(pr, duration) } },
                        onUnsnooze: onUnsnoozePR.map { callback in { pr in callback(pr) } }
                    )
                }
            }
        }
    }
}

struct PRRow: View {
    let pr: PullRequest
    var statusColorOverride: Color?
    var onOpen: (() -> Void)?
    var onSnooze: ((PullRequest, SnoozeDuration) -> Void)?
    var onUnsnooze: ((PullRequest) -> Void)?
    @State private var isHovered = false

    private var statusColor: Color {
        if let override = statusColorOverride {
            return override
        }
        if pr.isDraft {
            return .secondary
        }
        switch pr.reviewDecision {
        case .changesRequested:
            return .red
        case .approved:
            return .green
        default:
            return .gitHubOrange
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
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(pr.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(isHovered ? .white : .primary)

                            Spacer()

                            Text(relativeTime(from: pr.updatedAt))
                                .font(.caption)
                                .foregroundStyle(isHovered ? .white.opacity(0.7) : .secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }

                        HStack(spacing: 6) {
                            Text("\(pr.repository) #\(String(pr.number))")
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
                        .font(.caption)
                        .foregroundStyle(isHovered ? .white.opacity(0.8) : .secondary)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
            }
            .frame(minHeight: 50)
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
                    ForEach(Array(visible.enumerated()), id: \.element.login) { index, reviewer in
                        AsyncImage(url: reviewer.avatarURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .foregroundStyle(isHovered ? .white.opacity(0.6) : .secondary)
                        }
                        .frame(width: avatarSize, height: avatarSize)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(
                            isHovered ? Color(nsColor: .selectedContentBackgroundColor) : Color(nsColor: .windowBackgroundColor),
                            lineWidth: 1.5
                        ))
                        .offset(x: CGFloat(index) * (avatarSize - overlap))
                    }
                }
                .frame(width: avatarSize + CGFloat(max(visible.count - 1, 0)) * (avatarSize - overlap), alignment: .leading)

                if reviewers.count > maxVisible {
                    Text("+\(reviewers.count - maxVisible)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isHovered ? .white.opacity(0.7) : .secondary)
                        .padding(.leading, 2)
                }
            }
        }
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
                    additions: 1404,
                    deletions: 99,
                    changedFiles: 17,
                    totalComments: 3,
                    reviewers: [
                        Reviewer(login: "bob", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/2?v=4")),
                        Reviewer(login: "carol", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/3?v=4")),
                        Reviewer(login: "dave", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/4?v=4")),
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
}
