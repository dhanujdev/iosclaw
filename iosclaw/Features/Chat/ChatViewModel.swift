import SwiftUI
import Combine

typealias Role = AgentService.Role

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct PendingApprovalRequest: Identifiable {
    let id: UUID
    let prompt: String
    let summary: String
    let createdAt: Date

    init(id: UUID = UUID(), prompt: String, summary: String, createdAt: Date = .now) {
        self.id = id
        self.prompt = prompt
        self.summary = summary
        self.createdAt = createdAt
    }
}

enum ApprovalDecision: String {
    case approved
    case denied
}

struct ApprovalAuditEntry: Identifiable {
    let id: UUID
    let requestID: UUID
    let prompt: String
    let summary: String
    let decision: ApprovalDecision
    let recordedAt: Date

    init(
        id: UUID = UUID(),
        requestID: UUID,
        prompt: String,
        summary: String,
        decision: ApprovalDecision,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.requestID = requestID
        self.prompt = prompt
        self.summary = summary
        self.decision = decision
        self.recordedAt = recordedAt
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isGenerating: Bool = false
    @Published var recentRuns: [RecentExecutionRun] = []
    @Published var pendingApprovals: [PendingApprovalRequest] = []
    @Published var approvalHistory: [ApprovalAuditEntry] = []
    @Published var activeBiometricRequestID: UUID?
    @Published var biometricStatusMessage: String?
    @Published private(set) var configuration: AppConfiguration

    private let service: AgentService
    private let approvalStore: ApprovalPersistenceController
    private let chatStore: ChatPersistenceController
    private let taskExecutionStore: TaskExecutionPersistenceController
    private let approvalCoordinator: ApprovalCoordinator
    private let toolRegistry: ToolRegistry
    private var cancellable: AnyCancellable?

    var statusTitle: String {
        configuration.hasGeminiCredentials ? "Gemini Live Transport Ready" : "Gemini Stub Mode"
    }

    var statusDetail: String {
        configuration.hasGeminiCredentials
        ? "Requests will target \(configuration.geminiModel) at \(configuration.geminiBaseURL.host() ?? configuration.geminiBaseURL.absoluteString)."
        : "Set GEMINI_API_KEY in the Xcode scheme environment or Info.plist. Until then, the agent runs with a local PLAN.json stub."
    }

    init() {
        self.configuration = .live
        self.service = AgentService(configuration: .live)
        self.approvalStore = ApprovalPersistenceController()
        self.chatStore = ChatPersistenceController()
        self.taskExecutionStore = TaskExecutionPersistenceController()
        self.approvalCoordinator = ApprovalCoordinator()
        self.toolRegistry = .secureDefault
        reset()
    }

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        self.service = AgentService(configuration: configuration)
        self.approvalStore = ApprovalPersistenceController()
        self.chatStore = ChatPersistenceController()
        self.taskExecutionStore = TaskExecutionPersistenceController()
        self.approvalCoordinator = ApprovalCoordinator()
        self.toolRegistry = .secureDefault
        reset()
    }

    func attemptSend() {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        if let command = ToolCommand.parse(from: trimmedInput), command.requiresClientApproval {
            let request = PendingApprovalRequest(
                prompt: trimmedInput,
                summary: command.approvalSummary
            )
            pendingApprovals.append(request)
            approvalStore.save(request)
            let approvalMessage = ChatMessage(
                role: .system,
                text: "Approval required before executing: \(command.approvalSummary)"
            )
            messages.append(approvalMessage)
            chatStore.saveOrUpdate(approvalMessage)
            input = ""
            return
        }

        commitSend(prompt: trimmedInput)
    }

    func approvePendingRequest(id: UUID) async {
        guard let request = pendingApprovals.first(where: { $0.id == id }) else { return }
        activeBiometricRequestID = id
        biometricStatusMessage = nil
        defer { activeBiometricRequestID = nil }

        let approvalResult = await requestBiometricApproval(for: request)
        guard approvalResult.approved else {
            let failureText = approvalResult.message ?? "Face ID confirmation failed or is unavailable. The action stayed queued."
            let failedMessage = ChatMessage(
                role: .system,
                text: "\(failureText) Pending action: \(request.summary)"
            )
            biometricStatusMessage = failureText
            messages.append(failedMessage)
            chatStore.saveOrUpdate(failedMessage)
            SafetyAuditPersistenceController().record(
                category: .approval,
                severity: .warning,
                message: "Biometric approval failed for queued action: \(request.summary). Reason: \(failureText)"
            )
            return
        }

        pendingApprovals.removeAll { $0.id == id }
        approvalStore.delete(id: id)
        approvalStore.recordDecision(for: request, decision: .approved)
        approvalHistory = approvalStore.loadApprovalHistory()
        let approvalMessage = ChatMessage(
            role: .system,
            text: "Approval granted. Executing queued action: \(request.summary)"
        )
        biometricStatusMessage = nil
        messages.append(approvalMessage)
        chatStore.saveOrUpdate(approvalMessage)
        SafetyAuditPersistenceController().record(
            category: .approval,
            severity: .info,
            message: "Biometric approval granted for queued action: \(request.summary)"
        )
        commitSend(prompt: request.prompt)
    }

    func denyPendingRequest(id: UUID) {
        guard let request = pendingApprovals.first(where: { $0.id == id }) else { return }
        biometricStatusMessage = nil
        pendingApprovals.removeAll { $0.id == id }
        approvalStore.delete(id: id)
        approvalStore.recordDecision(for: request, decision: .denied)
        approvalHistory = approvalStore.loadApprovalHistory()
        let denialMessage = ChatMessage(
            role: .system,
            text: "Approval denied. The queued action was not executed: \(request.summary)"
        )
        messages.append(denialMessage)
        chatStore.saveOrUpdate(denialMessage)
        SafetyAuditPersistenceController().record(
            category: .approval,
            severity: .info,
            message: "Queued action was denied by the user: \(request.summary)"
        )
    }

    private func commitSend(prompt: String) {
        let userMessage = ChatMessage(role: .user, text: prompt)
        messages.append(userMessage)
        chatStore.saveOrUpdate(userMessage)
        input = ""

        isGenerating = true

        let requestMessages = messages.map { msg in
            AgentService.Message(role: msg.role, content: msg.text)
        }

        var assistantText = ""
        let assistantId = UUID()

        cancellable = service.generateResponse(to: requestMessages)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isGenerating = false
                self?.reloadRecentRuns()
                self?.cancellable = nil
            }, receiveValue: { [weak self] chunk in
                guard let self = self else { return }
                assistantText += chunk
                if let index = self.messages.firstIndex(where: { $0.id == assistantId }) {
                    self.messages[index] = ChatMessage(id: assistantId, role: .assistant, text: assistantText)
                    self.chatStore.saveOrUpdate(self.messages[index])
                } else {
                    let assistantMessage = ChatMessage(id: assistantId, role: .assistant, text: assistantText)
                    self.messages.append(assistantMessage)
                    self.chatStore.saveOrUpdate(assistantMessage)
                }
                self.reloadRecentRuns()
            })
    }

    func reset() {
        reloadRecentRuns()
        pendingApprovals = approvalStore.loadPendingApprovals()
        approvalHistory = approvalStore.loadApprovalHistory()
        biometricStatusMessage = nil
        let persistedMessages = chatStore.loadMessages()
        if persistedMessages.isEmpty {
            let seedMessage = makeSeedMessage()
            messages = [seedMessage]
            chatStore.resetThread(with: seedMessage)
        } else {
            messages = persistedMessages
        }
        input = ""
        isGenerating = false
        cancellable?.cancel()
        cancellable = nil
    }

    func resetThread() {
        let seedMessage = makeSeedMessage()
        messages = [seedMessage]
        chatStore.resetThread(with: seedMessage)
        reloadRecentRuns()
        pendingApprovals = approvalStore.loadPendingApprovals()
        approvalHistory = approvalStore.loadApprovalHistory()
        biometricStatusMessage = nil
        input = ""
        isGenerating = false
        cancellable?.cancel()
        cancellable = nil
    }

    func dismissBiometricStatus() {
        biometricStatusMessage = nil
    }

    private func requestBiometricApproval(for request: PendingApprovalRequest) async -> BiometricApprovalResult {
        guard
            let command = ToolCommand.parse(from: request.prompt),
            let tool = toolRegistry.tool(named: command.toolID)
        else {
            return BiometricApprovalResult(
                approved: false,
                message: "The queued action could not be validated. The action stayed queued."
            )
        }

        let requirement = approvalCoordinator.requirement(for: tool)
        switch requirement {
        case .none:
            return BiometricApprovalResult(approved: true, message: nil)
        case let .biometric(reason):
            return await approvalCoordinator.requestBiometricApproval(reason: reason)
        }
    }

    private func makeSeedMessage() -> ChatMessage {
        ChatMessage(
            role: .system,
            text: "Project shell ready. This build includes the app shell, Gemini transport wiring, agent planning state, persistence scaffolds, and a SwiftData-backed pending approvals inbox with approval audit history for high-risk file writes."
        )
    }

    private func reloadRecentRuns() {
        recentRuns = taskExecutionStore.loadRecentRuns()
    }
}
