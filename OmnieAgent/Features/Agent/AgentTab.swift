import SwiftUI

struct AgentTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tokens) private var tokens
    @State private var showAgents = false

    var body: some View {
        NavigationStack {
            Group {
                if let agent = model.active {
                    AgentOverview(agent: agent).id(agent.id)
                } else {
                    ContentUnavailableView("No agent selected", systemImage: "cpu")
                }
            }
            .background(tokens.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { AgentSwitcherButton { showAgents = true } }
            }
        }
        .sheet(isPresented: $showAgents) {
            AgentPicker().presentationDetents([.medium, .large])
        }
    }
}

private struct AgentOverview: View {
    let agent: AgentConnection
    @Environment(\.tokens) private var tokens

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        StatusDot(state: agent.status.dot)
                        Text(statusText).font(.footnote).foregroundStyle(tokens.secondary)
                    }
                    DisplayTitle(agent.connection.name, size: 26)
                    Text("\(agent.connection.kind.title) · \(agent.connection.hostLabel)")
                        .font(.footnote)
                        .foregroundStyle(tokens.secondary)
                    if let info = agent.info {
                        HStack(spacing: 16) {
                            if let model = info.model { Stat(label: "Model", value: model) }
                            if let version = info.version, version != "unknown" { Stat(label: "Version", value: version) }
                            Stat(label: "Chats", value: "\(agent.sessions.count)")
                        }
                        .padding(.top, 4)
                        if let detail = info.detail {
                            Text(detail).font(.caption).foregroundStyle(tokens.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            if case .failed(let message) = agent.status {
                Section {
                    InlineNotice(text: message)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if agent.features.jobs {
                    NavigationLink { JobsView(agent: agent) } label: {
                        Label("Scheduled jobs", systemImage: "clock.arrow.circlepath")
                    }
                }
                if agent.features.skills {
                    NavigationLink { SkillsView(agent: agent) } label: {
                        Label("Skills", systemImage: "sparkles.rectangle.stack")
                    }
                }
                if agent.features.toolsets {
                    NavigationLink { ToolsetsView(agent: agent) } label: {
                        Label("Tools", systemImage: "wrench.and.screwdriver")
                    }
                }
                if agent.features.logs {
                    NavigationLink { LogsView(agent: agent) } label: {
                        Label("Logs", systemImage: "text.alignleft")
                    }
                }
            }
            .listRowBackground(tokens.surface)

            Section {
                Button {
                    Task { await agent.connect() }
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
            }
            .listRowBackground(tokens.surface)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await agent.connect() }
        .task { if agent.status == .idle { await agent.connect() } }
    }

    private var statusText: String {
        switch agent.status {
        case .idle: "Not connected"
        case .connecting: "Connecting"
        case .online: "Online"
        case .failed: "Unreachable"
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    @Environment(\.tokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(label)
            Text(value).font(.footnote.weight(.medium)).foregroundStyle(tokens.text).lineLimit(1)
        }
    }
}

// MARK: - Jobs

struct JobsView: View {
    let agent: AgentConnection
    @State private var jobs: [AgentJob] = []
    @State private var loading = true
    @State private var error: String?
    @State private var creating = false
    @Environment(\.tokens) private var tokens

    var body: some View {
        List {
            if let error {
                InlineNotice(text: error).listRowBackground(Color.clear)
            }
            ForEach(jobs) { job in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.name).font(.body.weight(.medium)).foregroundStyle(tokens.text)
                        Spacer()
                        if job.paused || !job.enabled {
                            Text("Paused").font(.caption2.weight(.semibold)).foregroundStyle(tokens.secondary)
                        }
                    }
                    Text(job.schedule).font(.caption.monospaced()).foregroundStyle(tokens.secondary)
                    if !job.prompt.isEmpty {
                        Text(job.prompt).font(.footnote).foregroundStyle(tokens.secondary).lineLimit(2)
                    }
                    if let next = job.nextRun {
                        Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(tokens.secondary)
                    }
                }
                .padding(.vertical, 4)
                .swipeActions {
                    Button(role: .destructive) { act(job, .delete) } label: { Label("Delete", systemImage: "trash") }
                    Button { act(job, job.paused ? .resume : .pause) } label: {
                        Label(job.paused ? "Resume" : "Pause", systemImage: job.paused ? "play" : "pause")
                    }
                    .tint(.gray)
                }
                .contextMenu {
                    Button { act(job, .run) } label: { Label("Run now", systemImage: "play.circle") }
                    Button { act(job, job.paused ? .resume : .pause) } label: {
                        Label(job.paused ? "Resume" : "Pause", systemImage: job.paused ? "play" : "pause")
                    }
                    Button(role: .destructive) { act(job, .delete) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if jobs.isEmpty && error == nil {
                ContentUnavailableView("No scheduled jobs", systemImage: "clock",
                                       description: Text("Ask the agent to schedule something, or add one here."))
            }
        }
        .navigationTitle("Scheduled jobs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New job")
            }
        }
        .sheet(isPresented: $creating) {
            NewJobSheet(agent: agent) { await load() }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            jobs = try await agent.backend.jobs()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func act(_ job: AgentJob, _ action: JobAction) {
        Task {
            do {
                try await agent.backend.job(job.id, action)
                Haptics.success()
                await load()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct NewJobSheet: View {
    let agent: AgentConnection
    let onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var schedule = "every day at 9am"
    @State private var prompt = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Name", text: $name)
                    TextField("Schedule", text: $schedule)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    TextField("What should the agent do?", text: $prompt, axis: .vertical)
                        .lineLimit(4...10)
                } header: {
                    Text("Prompt")
                } footer: {
                    Text("Schedules accept cron (0 9 * * *), intervals (every 2h) or plain phrases the agent understands.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.Semantic.danger).font(.footnote) }
                }
            }
            .navigationTitle("New job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saving = true
                        Task {
                            do {
                                try await agent.backend.createJob(name: name.isEmpty ? String(prompt.prefix(40)) : name,
                                                                  schedule: schedule, prompt: prompt)
                                await onDone()
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            saving = false
                        }
                    }
                    .disabled(prompt.isEmpty || schedule.isEmpty || saving)
                }
            }
        }
    }
}

// MARK: - Skills & tools

struct SkillsView: View {
    let agent: AgentConnection
    @State private var skills: [AgentSkill] = []
    @State private var search = ""
    @State private var loading = true
    @State private var error: String?
    @Environment(\.tokens) private var tokens

    var body: some View {
        List {
            if let error { InlineNotice(text: error).listRowBackground(Color.clear) }
            ForEach(grouped, id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { skill in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.name).font(.body.weight(.medium)).foregroundStyle(skill.enabled ? tokens.text : tokens.secondary)
                            if !skill.description.isEmpty {
                                Text(skill.description).font(.footnote).foregroundStyle(tokens.secondary).lineLimit(3)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .searchable(text: $search, prompt: "Search skills")
        .navigationTitle("Skills")
        .task {
            do { skills = try await agent.backend.skills() } catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    private var grouped: [(String, [AgentSkill])] {
        let query = search.lowercased()
        let filtered = skills.filter { query.isEmpty || $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query) }
        let groups = Dictionary(grouping: filtered) { $0.category?.capitalized ?? "General" }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.name < $1.name }) }
    }
}

struct ToolsetsView: View {
    let agent: AgentConnection
    @State private var toolsets: [AgentToolset] = []
    @State private var loading = true
    @State private var error: String?
    @Environment(\.tokens) private var tokens

    var body: some View {
        List {
            if let error { InlineNotice(text: error).listRowBackground(Color.clear) }
            ForEach(toolsets) { toolset in
                DisclosureGroup {
                    if !toolset.description.isEmpty {
                        Text(toolset.description).font(.footnote).foregroundStyle(tokens.secondary)
                    }
                    ForEach(toolset.tools, id: \.self) { tool in
                        Text(tool).font(.footnote.monospaced()).foregroundStyle(tokens.text)
                    }
                } label: {
                    HStack {
                        Text(toolset.label).foregroundStyle(tokens.text)
                        Spacer()
                        Text(toolset.enabled ? (toolset.configured ? "On" : "Needs setup") : "Off")
                            .font(.caption)
                            .foregroundStyle(tokens.secondary)
                    }
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .navigationTitle("Tools")
        .task {
            do {
                toolsets = try await agent.backend.toolsets().sorted { lhs, rhs in
                    lhs.enabled != rhs.enabled ? lhs.enabled : lhs.label < rhs.label
                }
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

struct LogsView: View {
    let agent: AgentConnection
    @State private var file = "agent"
    @State private var lines: [String] = []
    @State private var error: String?
    @State private var loading = false
    @Environment(\.tokens) private var tokens

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if let error { InlineNotice(text: error) }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(color(for: line))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .overlay { if loading && lines.isEmpty { ProgressView() } }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Log", selection: $file) {
                    Text("Agent").tag("agent")
                    Text("Errors").tag("errors")
                    Text("Gateway").tag("gateway")
                }
                .pickerStyle(.menu)
            }
        }
        .refreshable { await load() }
        .task(id: file) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            lines = try await agent.backend.logs(file: file, lines: 400)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func color(for line: String) -> Color {
        if line.contains("ERROR") || line.contains("CRITICAL") { return Palette.Semantic.danger }
        if line.contains("WARNING") { return Palette.Semantic.warning }
        return tokens.secondary
    }
}
