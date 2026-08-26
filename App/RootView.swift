import SwiftUI
import SurfCore

/// Three tabs, and Settings deliberately not among them.
///
/// Settings sits behind a toolbar button on Home because it is visited rarely,
/// while the sport profile — which people genuinely switch day to day if they
/// do two of these sports — is promoted to the Home toolbar instead.
@MainActor
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            HomeView(model: model)
                .tabItem { Label("בית", systemImage: "house.fill") }

            WeekView(model: model)
                .tabItem { Label("שבוע", systemImage: "calendar") }

            SpotsView(model: model)
                .tabItem { Label("חופים", systemImage: "mappin.and.ellipse") }
        }
        .tint(Aqua.aqua600)
    }
}

@MainActor
struct EmptyCatalogView: View {
    let theme: Theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.largeTitle)
                .foregroundStyle(theme.text2)
            Text("קטלוג החופים לא נטען")
                .font(SurfFont.headline)
                .foregroundStyle(theme.text1)
            Text("הקובץ spots.json חסר מהחבילה.")
                .font(SurfFont.meta)
                .foregroundStyle(theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page)
    }
}
