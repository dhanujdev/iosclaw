import SwiftUI
import SwiftData

@main
struct IOSClawApp: App {
    private let backgroundCoordinator = BackgroundExecutionCoordinator()
    @MainActor private let modelContainer = AppModelContainer.shared

    init() {
        backgroundCoordinator.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
