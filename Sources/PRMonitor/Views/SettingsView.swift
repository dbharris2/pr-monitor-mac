import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false
    @State private var showSignOutInstructions = false
    @State private var editingFilter: ReviewFilter?

    private let pollIntervalOptions: [(String, TimeInterval)] = [
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
    ]

    var body: some View {
        Form {
            Section {
                ghAuthSection
            } header: {
                Text("GitHub Authentication")
            }

            Section {
                Picker("Poll interval", selection: $appState.pollInterval) {
                    ForEach(pollIntervalOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                .onChange(of: appState.pollInterval) { _, _ in
                    appState.startPolling()
                }
            } header: {
                Text("Refresh")
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                Toggle("Notifications", isOn: $appState.notificationsEnabled)
                    .onChange(of: appState.notificationsEnabled) { _, newValue in
                        if newValue {
                            appState.requestNotificationPermissions()
                        }
                    }

                Picker("Menu bar indicator", selection: $appState.menuBarStyle) {
                    Text("Dots (compact)").tag("dots")
                    Text("Colored numbers").tag("numbers")
                }

                KeyboardShortcuts.Recorder("Global shortcut:", name: .toggleMenuBar)
            } header: {
                Text("General")
            }

            Section {
                if appState.customReviewFilters.isEmpty {
                    Text("Create filters for specific teams or review types.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.customReviewFilters) { filter in
                        HStack {
                            Text(filter.name)
                            Spacer()
                            Button("Edit") {
                                editingFilter = filter
                            }
                            .buttonStyle(.borderless)
                            Button {
                                appState.deleteReviewFilter(filter)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Add filter") {
                        editingFilter = ReviewFilter(
                            id: UUID().uuidString,
                            name: "New filter",
                            includesDirectRequests: true,
                            teams: []
                        )
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("Saved filters")
            } footer: {
                Text("Filters appear in the Filter menu and apply to review-related sections and notifications.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
        .sheet(item: $editingFilter) { filter in
            ReviewFilterEditor(filter: filter)
                .environmentObject(appState)
        }
        .task {
            await appState.refreshAuthStatus()
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert("Sign out of GitHub CLI", isPresented: $showSignOutInstructions) {
            Button("Copy command") { copy("gh auth logout") }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Run `gh auth logout` in your terminal to sign out. PR Monitor will detect the change on the next refresh.")
        }
    }

    @ViewBuilder
    private var ghAuthSection: some View {
        switch appState.ghAuthStatus {
        case .unknown:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub CLI…").foregroundStyle(.secondary)
            }
        case .ghMissing:
            authStateCard(
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "GitHub CLI not found",
                instruction: "Install with:",
                command: "brew install gh"
            )
        case .notAuthenticated:
            authStateCard(
                systemImage: "person.slash",
                tint: .orange,
                title: "Not signed in",
                instruction: "Run this in your terminal:",
                command: "gh auth login"
            )
        case let .authenticated(login):
            HStack {
                Label {
                    Text("Signed in as @\(login) via gh CLI")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button("Sign out") { showSignOutInstructions = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func authStateCard(systemImage: String, tint: Color, title: String, instruction: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            Text(instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Button("Copy") { copy(command) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                Spacer()
                Button("Re-check") {
                    Task {
                        await appState.refreshAuthStatus()
                        await appState.refresh()
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail - user can retry via the toggle
        }
    }
}

struct ReviewFilterEditor: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let filter: ReviewFilter
    @State private var name: String
    @State private var includesDirectRequests: Bool
    @State private var teams: [ReviewFilterTeam]
    @State private var repositories: [ReviewFilterRepository]
    @State private var authors: [ReviewFilterAuthor]
    @State private var newTeam = ""
    @State private var newAuthor = ""
    @State private var newRepository = ""

    init(filter: ReviewFilter) {
        self.filter = filter
        _name = State(initialValue: filter.name)
        _includesDirectRequests = State(initialValue: filter.includesDirectRequests)
        _teams = State(initialValue: filter.teams)
        _repositories = State(initialValue: filter.repositories)
        _authors = State(initialValue: filter.authors)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)

                Toggle("Also include direct requests", isOn: $includesDirectRequests)

                Section("Repositories") {
                    if repositories.isEmpty {
                        Text("All repositories are included.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(repositories.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField("", text: $repositories[index].repository)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 0)
                                IncludeExcludeButtons(isIncluded: $repositories[index].isIncluded)
                                Button {
                                    repositories.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    HStack {
                        TextField("", text: $newRepository, prompt: Text("owner/repository"))
                            .labelsHidden()
                        Button {
                            addRepository()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(normalizedNewRepository.isEmpty || hasRepository(normalizedNewRepository))
                    }
                }

                Section("Teams") {
                    if teams.isEmpty {
                        Text("All teams are included.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(teams.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField("", text: $teams[index].team)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 0)
                                IncludeExcludeButtons(isIncluded: $teams[index].isIncluded)
                                Button {
                                    teams.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    HStack {
                        TextField("", text: $newTeam, prompt: Text("org/team-slug"))
                            .labelsHidden()
                        Button {
                            addTeam()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(normalizedNewTeam.isEmpty || hasTeam(normalizedNewTeam))
                    }
                }

                Section("Authors") {
                    if authors.isEmpty {
                        Text("Add authors whose PRs this filter should include or exclude.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(authors.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                TextField("", text: $authors[index].username)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 0)
                                IncludeExcludeButtons(isIncluded: $authors[index].isIncluded)
                                Button {
                                    authors.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    HStack {
                        TextField("", text: $newAuthor, prompt: Text("GitHub username"))
                            .labelsHidden()
                        Button {
                            addAuthor()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(normalizedNewAuthor.isEmpty || hasAuthor(normalizedNewAuthor))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    appState.saveReviewFilter(ReviewFilter(
                        id: filter.id,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        includesDirectRequests: includesDirectRequests,
                        teams: normalizedTeams,
                        authors: normalizedAuthors,
                        repositories: normalizedRepositories
                    ))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }

    private var normalizedNewAuthor: String {
        newAuthor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedNewRepository: String {
        newRepository.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedNewTeam: String {
        newTeam.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedTeams: [ReviewFilterTeam] {
        var seen = Set<String>()
        return teams.compactMap { team in
            let key = team.team.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return ReviewFilterTeam(team: key, isIncluded: team.isIncluded)
        }
    }

    private var normalizedAuthors: [ReviewFilterAuthor] {
        var seen = Set<String>()
        return authors.compactMap { author in
            let username = author.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !username.isEmpty, seen.insert(username).inserted else { return nil }
            return ReviewFilterAuthor(username: username, isIncluded: author.isIncluded)
        }
    }

    private var normalizedRepositories: [ReviewFilterRepository] {
        var seen = Set<String>()
        return repositories.compactMap { repository in
            let name = repository.repository.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return ReviewFilterRepository(repository: name, isIncluded: repository.isIncluded)
        }
    }

    private func hasAuthor(_ username: String) -> Bool {
        normalizedAuthors.contains { $0.username.caseInsensitiveCompare(username) == .orderedSame }
    }

    private func hasRepository(_ repository: String) -> Bool {
        normalizedRepositories.contains { $0.repository.caseInsensitiveCompare(repository) == .orderedSame }
    }

    private func hasTeam(_ team: String) -> Bool {
        normalizedTeams.contains { $0.team.caseInsensitiveCompare(team) == .orderedSame }
    }

    private func addAuthor() {
        guard !normalizedNewAuthor.isEmpty, !hasAuthor(normalizedNewAuthor) else { return }
        authors.append(ReviewFilterAuthor(username: normalizedNewAuthor, isIncluded: true))
        newAuthor = ""
    }

    private func addRepository() {
        guard !normalizedNewRepository.isEmpty, !hasRepository(normalizedNewRepository) else { return }
        repositories.append(ReviewFilterRepository(repository: normalizedNewRepository, isIncluded: true))
        newRepository = ""
    }

    private func addTeam() {
        guard !normalizedNewTeam.isEmpty, !hasTeam(normalizedNewTeam) else { return }
        teams.append(ReviewFilterTeam(team: normalizedNewTeam, isIncluded: true))
        newTeam = ""
    }
}

struct IncludeExcludeButtons: View {
    @Binding var isIncluded: Bool

    var body: some View {
        HStack(spacing: 3) {
            Button {
                isIncluded = true
            } label: {
                Image(systemName: "checkmark")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isIncluded ? Color.white : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isIncluded ? Color.accentColor : Color.primary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .help("Include")

            Button {
                isIncluded = false
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isIncluded ? Color.secondary : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isIncluded ? Color.primary.opacity(0.1) : Color.red)
                    )
            }
            .buttonStyle(.plain)
            .help("Exclude")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.preview)
}
