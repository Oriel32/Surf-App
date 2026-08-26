import SwiftUI
import SurfCore

/// Support, not product. Everything here is set once and forgotten — which is
/// why it sits behind a toolbar button rather than taking a fourth tab from
/// Home, Week and Spots.
@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        NavigationStack {
            Form {
                sportSection
                skillSection
                unitsSection
                favouritesSection
                verificationSection
                aboutSection
            }
            .navigationTitle("הגדרות")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var sportSection: some View {
        Section("ספורט") {
            Picker("ענף", selection: $model.settings.sport) {
                ForEach(Sport.allCases, id: \.self) { sport in
                    Text(sport.hebrew).tag(sport)
                }
            }
        }
    }

    /// Skill level is not cosmetic, and the footer says so. It modulates both
    /// the Match Score and how aggressively the safety alert fires: the same
    /// glassy offshore morning is a career-best session for an advanced surfer
    /// and a drowning risk for a beginner on a SUP.
    private var skillSection: some View {
        Section {
            Picker("רמה", selection: $model.settings.skill) {
                ForEach(SkillLevel.allCases, id: \.self) { skill in
                    Text(skill.hebrew).tag(skill)
                }
            }
        } header: {
            Text("רמת ניסיון")
        } footer: {
            Text("הרמה משנה גם את הציון וגם את סף האזהרות. ברירת המחדל היא מתחיל — עדיף להזהיר יותר מדי מאשר מעט מדי.")
        }
    }

    private var unitsSection: some View {
        Section {
            Picker("גובה גלים", selection: $model.settings.heightUnit) {
                Text("מטרים").tag(HeightUnit.meters)
                Text("רגל").tag(HeightUnit.feet)
            }
        } header: {
            Text("יחידות")
        } footer: {
            Text("מהירות רוח מוצגת תמיד בקשרים — זו יחידת התקן בכל מערכת ימית.")
        }
    }

    private var favouritesSection: some View {
        Section {
            if model.favouriteSpots.isEmpty {
                Text("אין חופים מועדפים. סמנו כוכב בלשונית החופים.")
                    .font(SurfFont.meta)
                    .foregroundStyle(theme.text2)
            } else {
                ForEach(model.favouriteSpots) { spot in
                    HStack {
                        Text(spot.nameHebrew)
                        Spacer(minLength: 0)
                        if spot.id == model.settings.defaultSpotID {
                            Text("ברירת מחדל")
                                .font(SurfFont.label)
                                .foregroundStyle(Aqua.aqua600)
                        }
                    }
                }
                .onMove { source, destination in
                    model.settings.favouriteSpotIDs.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    model.settings.favouriteSpotIDs.remove(atOffsets: offsets)
                }
            }
        } header: {
            Text("חופים מועדפים")
        } footer: {
            Text("המועדף הראשון הוא החוף שנפתח במסך הבית.")
        }
    }

    private var verificationSection: some View {
        Section {
            Toggle("מדידות מצוף", isOn: $model.settings.showBuoy)
            Toggle("מצלמות חוף", isOn: $model.settings.showWebcams)
        } header: {
            Text("אימות")
        } footer: {
            Text("שכבת האימות מציגה מדידות אמיתיות לצד התחזית. מצלמות עדיין לא מחוברות.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("שפה", value: "עברית")
            LabeledContent("מקור תחזית", value: "Open-Meteo")
            LabeledContent("מקור מדידות", value: "ISRAMAR")
        } header: {
            Text("אודות")
        } footer: {
            Text("התחזית מותאמת לכל חוף בנפרד לפי מקדם חשיפה, רדידה ושבירה — היא אינה ערך גולמי של מודל.")
        }
    }
}
