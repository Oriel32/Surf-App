import SwiftUI
import SurfCore

@main
@MainActor
struct GlassyApp: App {
    @State private var model = AppModel.live()
    @Environment(\.colorScheme) private var colorScheme

    var body: some Scene {
        WindowGroup {
            Group {
                if model.spots.isEmpty {
                    EmptyCatalogView(theme: Theme.current(colorScheme))
                } else {
                    RootView(model: model)
                }
            }
            // Hebrew is the primary locale and the slang is the product's real
            // vocabulary, so the layout mirrors from the first screen rather
            // than as a retrofit. Forced here rather than left to the device
            // language, because this app is Hebrew-first even on an English
            // phone.
            .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
