import SwiftUI

@main
struct OmnieAgentApp: App {
    @State private var model = AppModel()
    @State private var theme = BrandTheme()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(theme)
                .onOpenURL { url in
                    model.handleDeepLink(url)
                }
        }
    }
}
