import SwiftUI
import SurfCore

/// Layer 1. One screen that answers "do I get in the car, right now?" in under
/// three seconds, without scrolling or tapping.
@MainActor
struct HomeView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSettings = false

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    stateContent
                }
                .padding(16)
            }
            .background(theme.page.ignoresSafeArea())
            .navigationTitle(model.selectedSpot?.nameHebrew ?? "גלאסי")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await model.refreshSelected() }
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingSettings) {
                SettingsView(model: model)
            }
        }
        .task(id: model.reloadKey) {
            await model.loadSelected()
        }
    }

    // MARK: - The four states

    @ViewBuilder
    private var stateContent: some View {
        switch model.selectedState {
        case .loading:
            LoadingSection(theme: theme)

        case .failed(let reason):
            FailureSection(reason: reason, theme: theme) { [model] in
                await model.loadSelected()
            }

        case .loaded(let forecast):
            loaded(forecast)

        case .stale(let forecast, let age):
            StaleNotice(age: age, theme: theme)
            loaded(forecast)
        }
    }

    @ViewBuilder
    private func loaded(_ forecast: SpotForecast) -> some View {
        // The banner sits above the score, always. Never let a high score
        // visually overwhelm an active safety warning.
        if let hour = model.currentHour {
            ForEach(hour.alerts, id: \.kind.rawValue) { alert in
                SafetyBanner(alert: alert, theme: theme)
            }
            HeroSection(hour: hour, heightUnit: model.settings.heightUnit, theme: theme)
        }

        BestWindowSection(window: forecast.bestWindowToday, theme: theme)
        HourlyStrip(hours: model.today, theme: theme)

        if model.settings.showBuoy {
            BuoySection(
                status: forecast.buoy,
                reference: forecast.buoyReference,
                heightUnit: model.settings.heightUnit,
                theme: theme
            )
        }

        // The one clear affordance into Layer 2.
        if let spot = model.selectedSpot {
            NavigationLink {
                DetailView(model: model, spot: spot, day: Date())
            } label: {
                HStack {
                    Text("כל הנתונים להיום")
                        .font(SurfFont.cardTitle)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote)
                        .flipsForRightToLeftLayoutDirection(true)
                }
                .foregroundStyle(Aqua.aqua600)
                .padding(16)
                .tappableRow()
                .surfCard(theme, radius: Metric.innerRadius)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("חוף", selection: $model.selectedSpotID) {
                    ForEach(model.spots) { spot in
                        Text(spot.nameHebrew).tag(spot.id)
                    }
                }
            } label: {
                Image(systemName: "mappin.and.ellipse")
            }
            .accessibilityLabel("בחירת חוף")
        }

        ToolbarItem(placement: .topBarTrailing) {
            // Switching sport is a normal daily action for anyone who does two
            // of them, not a buried preference. It changes every score at once.
            Menu {
                Picker("ספורט", selection: $model.settings.sport) {
                    ForEach(Sport.allCases, id: \.self) { sport in
                        Text(sport.hebrew).tag(sport)
                    }
                }
            } label: {
                Image(systemName: "figure.surfing")
            }
            .accessibilityLabel("בחירת ספורט")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("הגדרות")
        }
    }
}
