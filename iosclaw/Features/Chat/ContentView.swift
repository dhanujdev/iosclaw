import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var expandedRunIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusCard
                if let biometricStatusMessage = vm.biometricStatusMessage {
                    biometricStatusBanner(message: biometricStatusMessage)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            architectureCard
                            recentRunsCard
                            if !vm.pendingApprovals.isEmpty {
                                approvalsCard
                            }
                            if !vm.approvalHistory.isEmpty {
                                approvalHistoryCard
                            }

                            ForEach(vm.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) {
                        if let lastID = vm.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }

                composer
            }
            .navigationTitle("iOS Claw")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset", action: vm.resetThread)
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.statusTitle)
                .font(.headline)
            Text(vm.statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Model: \(vm.configuration.geminiModel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Storage: \(AppModelContainer.syncStatusDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let bootstrapIssue = AppModelContainer.bootstrapIssueDescription,
               !bootstrapIssue.isEmpty {
                Text("CloudKit issue: \(bootstrapIssue)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(vm.configuration.hasGeminiCredentials ? Color.green.opacity(0.18) : Color.yellow.opacity(0.18))
    }

    private var approvalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pending Approvals", systemImage: "checkmark.shield")
                    .font(.headline)
                Spacer()
                Text("\(vm.pendingApprovals.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.16))
                    .clipShape(Capsule())
            }

            ForEach(vm.pendingApprovals) { request in
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.summary)
                        .font(.subheadline)
                    Text(request.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack {
                        Button(vm.activeBiometricRequestID == request.id ? "Confirming..." : "Approve") {
                            Task {
                                await vm.approvePendingRequest(id: request.id)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.activeBiometricRequestID != nil)

                        Button("Deny", role: .destructive) {
                            vm.denyPendingRequest(id: request.id)
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.activeBiometricRequestID != nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recentRunsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent Runs", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(vm.recentRuns.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.teal.opacity(0.16))
                    .clipShape(Capsule())
            }

            if vm.recentRuns.isEmpty {
                Text("No agent runs yet. Send a prompt or execute a tool command to create the first execution record.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.recentRuns) { run in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            lifecycleBadge(for: run.lifecycleState)
                            Spacer()
                            Text(run.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(run.goal)
                            .font(.subheadline.weight(.semibold))

                        if let lastError = run.lastError, !lastError.isEmpty {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button(expandedRunIDs.contains(run.id) ? "Hide PLAN.json" : "Show PLAN.json") {
                            toggleRunExpansion(id: run.id)
                        }
                        .buttonStyle(.bordered)

                        if expandedRunIDs.contains(run.id) {
                            Text(run.planJSON)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.teal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func biometricStatusBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "faceid")
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss") {
                vm.dismissBiometricStatus()
            }
            .font(.caption.weight(.semibold))
        }
        .padding()
        .background(Color.orange.opacity(0.12))
    }

    private var approvalHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Approval History", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            ForEach(vm.approvalHistory) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.decision == .approved ? "Approved" : "Denied")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                (entry.decision == .approved ? Color.green : Color.red)
                                    .opacity(0.16)
                            )
                            .clipShape(Capsule())
                        Spacer()
                        Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(entry.summary)
                        .font(.subheadline)
                    Text(entry.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var architectureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Phase 1 Boundaries")
                .font(.headline)
            Text("App, configuration, feature UI, runtime, memory, and security layers are separated so the autonomous loop can grow without reshaping the project.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label("App entry: `App/`", systemImage: "app")
            Label("Configuration: `Core/Config/`", systemImage: "gearshape.2")
            Label("Runtime + loop: `Core/Agent/` and `Core/Runtime/`", systemImage: "arrow.triangle.branch")
            Label("Memory + tools: `Core/Memory/` and `Core/Tools/`", systemImage: "internaldrive")
            Label("Security checkpoints: `Core/Security/`", systemImage: "lock.shield")
            Label("Chat feature shell: `Features/Chat/`", systemImage: "text.bubble")
            Label("Agent integration boundary: `Services/Agent/`", systemImage: "bolt.horizontal")
            Label("Sync mode: `\(AppModelContainer.syncStatusDescription)`", systemImage: "icloud")
            Text("Try tool commands: `search: rust async await`, `read file: notes.txt`, `write file: notes.txt | draft`, `remind: Publish the next video`")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("File writes now enter a pending-approvals inbox, require biometric confirmation before execution, and leave a persistent approval audit trail.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Set `ENABLE_CLOUDKIT_SYNC=1` in the scheme or Info.plist to request a CloudKit-backed model container when entitlements are available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func lifecycleBadge(for state: AgentLifecycleState) -> some View {
        Text(lifecycleLabel(for: state))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(lifecycleColor(for: state).opacity(0.16))
            .foregroundStyle(lifecycleColor(for: state))
            .clipShape(Capsule())
    }

    private func toggleRunExpansion(id: UUID) {
        var updatedRunIDs = expandedRunIDs
        if expandedRunIDs.contains(id) {
            updatedRunIDs.remove(id)
        } else {
            updatedRunIDs.insert(id)
        }
        expandedRunIDs = updatedRunIDs
    }

    private func lifecycleLabel(for state: AgentLifecycleState) -> String {
        switch state {
        case .idle:
            "Idle"
        case .observing:
            "Observing"
        case .planning:
            "Planning"
        case .acting:
            "Acting"
        case .evaluating:
            "Evaluating"
        case .waitingForApproval:
            "Waiting"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        }
    }

    private func lifecycleColor(for state: AgentLifecycleState) -> Color {
        switch state {
        case .idle:
            .gray
        case .observing:
            .blue
        case .planning:
            .indigo
        case .acting:
            .orange
        case .evaluating:
            .teal
        case .waitingForApproval:
            .yellow
        case .completed:
            .green
        case .failed:
            .red
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask the agent or run a tool command", text: $vm.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isGenerating)
                .lineLimit(1...4)
                .submitLabel(.send)

            Button(vm.isGenerating ? "Working..." : "Send") {
                vm.attemptSend()
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isGenerating || vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.bar)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer()
                Text(message.text)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text(message.text)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(message.role == .system ? Color.orange.opacity(0.14) : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 24)
            }
        }
    }
}

#Preview {
    ContentView()
}
