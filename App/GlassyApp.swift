import SwiftUI
import SurfCore

@main
@MainActor
struct GlassyApp: App {
    @State private var viewModel = ForecastViewModel.live()

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: viewModel)
                // Hebrew is the primary locale and the slang is the product's
                // real vocabulary, so the layout mirrors from the first screen
                // rather than as a retrofit. Forced here rather than left to
                // the device language, because this app is Hebrew-first even
                // on an English phone.
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
