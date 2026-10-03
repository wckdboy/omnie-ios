import SwiftUI

@main
struct OmnieAgentApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    model.handleDeepLink(url)
                }
        }
    }
}
