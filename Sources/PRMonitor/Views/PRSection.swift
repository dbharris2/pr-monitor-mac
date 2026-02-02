import SwiftUI

extension Color {
    static let gitHubOrange = Color(red: 247/255, green: 129/255, blue: 102/255)
}

struct PRSection: View {
    let title: String
    let prs: [PullRequest]
    @Binding var isExpanded: Bool

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

            if isExpanded && !prs.isEmpty {
                ForEach(prs) { pr in
                    PRRow(pr: pr)
                }
            }
        }
    }
}

struct PRRow: View {
    let pr: PullRequest
    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(pr.isDraft ? Color.secondary : (pr.reviewDecision == .changesRequested ? Color.red : Color.gitHubOrange))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(pr.number): \(pr.title)")
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(pr.repository)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
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
    .frame(width: 320)
}
