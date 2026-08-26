import SwiftUI
import SurfCore

/// Layer 1. One screen that answers "do I get in the car, right now?" in under
/// three seconds, without scrolling or tapping.
@MainActor
struct HomeView: View {
    @Bindable var viewModel: ForecastViewModel
    @Environment(\.colorScheme) private var colorScheme

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
            .navigationTitle(viewModel.selectedSpot?.nameHebrew ?? "גלאסי")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await viewModel.refresh() }
            .toolbar { toolbarContent }
        }
        .task(id: viewModel.reloadKey) {
            await viewModel.load()
        }
    }

    // MARK: - The four states

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            LoadingSection(theme: theme)

        case .failed(let reason):
            FailureSection(reason: reason, theme: theme) {
                await viewModel.load()
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
        if let hour = viewModel.currentHour {
            ForEach(hour.alerts, id: \.kind.rawValue) { alert in
                SafetyBanner(alert: alert)
            }
            HeroSection(hour: hour, theme: theme)
        }

        BestWindowSection(window: forecast.bestWindowToday, theme: theme)
        HourlyStrip(hours: viewModel.today, theme: theme)
        BuoySection(status: forecast.buoy, theme: theme)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("חוף", selection: $viewModel.selectedSpotID) {
                    ForEach(viewModel.spots) { spot in
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
                Picker("ספורט", selection: $viewModel.profile.sport) {
                    ForEach(Sport.allCases, id: \.self) { sport in
                        Text(sport.hebrew).tag(sport)
                    }
                }
                Picker("רמה", selection: $viewModel.profile.skill) {
                    ForEach(SkillLevel.allCases, id: \.self) { skill in
                        Text(skill.hebrew).tag(skill)
                    }
                }
            } label: {
                Image(systemName: "figure.surfing")
            }
            .accessibilityLabel("בחירת ספורט ורמה")
        }
    }
}
