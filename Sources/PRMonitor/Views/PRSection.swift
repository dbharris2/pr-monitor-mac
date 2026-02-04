import SwiftUI

extension Color {
    static let gitHubOrange = Color(red: 247 / 255, green: 129 / 255, blue: 102 / 255)
}

struct PRSection: View {
    let title: String
    let prs: [PullRequest]
    @Binding var isExpanded: Bool
    var statusColorOverride: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text("\(title) (\(prs.count))")
                        .foregroundStyle(prs.isEmpty ? .secondary : .primary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if isExpanded, !prs.isEmpty {
                ForEach(prs) { pr in
                    PRRow(pr: pr, statusColorOverride: statusColorOverride)
                }
            }
        }
    }
}

struct PRRow: View {
    let pr: PullRequest
    var statusColorOverride: Color?
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
            NSWorkspace.shared.open(pr.url)
        } label: {
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
                    Text(pr.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isHovered ? .white : .primary)

                    Text("\(pr.repository) #\(String(pr.number))")
                        .font(.caption)
                        .foregroundStyle(isHovered ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
    }
}

#Preview {
    VStack {
        PRSection(
            title: "Needs your review",
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
                    isDraft: false,
                    reviewDecision: nil
                )
            ],
            isExpanded: .constant(true)
        )

        PRSection(
            title: "Drafts",
            prs: [],
            isExpanded: .constant(false)
        )
    }
    .frame(width: 380)
}
