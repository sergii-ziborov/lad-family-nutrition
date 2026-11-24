import SwiftUI
import Charts

/// Daily reference intakes from the National Academies DRI tables, as
/// published by NIH ODS: RDA where one exists, otherwise AI. They describe
/// what covers most healthy people of that age and sex. They are a scale for
/// charts and a ranking hint, not a personal prescription.
enum NutrientNorms {
    static let sourceURL = URL(string: "https://ods.od.nih.gov/HealthInformation/nutrientrecommendations.aspx")!
    static let keys = ["vitamin_a", "vitamin_c", "vitamin_d", "vitamin_e", "vitamin_k",
                       "vitamin_b1", "vitamin_b2", "vitamin_b3", "vitamin_b6", "vitamin_b12",
                       "folate", "choline", "calcium", "iron", "magnesium", "phosphorus",
                       "potassium", "zinc", "selenium"]

    private static func row(_ values: [Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: zip(keys, values))
    }

    /// Nil under 1 year and during pregnancy or breastfeeding, which have
    /// their own tables that the app does not use.
    static func daily(for member: FamilyMember) -> [String: Double]? {
        guard let age = member.ageYears, age >= 1, member.energyContext != .pregnancyOrLactation else { return nil }
        let male: [Double]
        let female: [Double]
        //           A    C   D   E   K    B1   B2   B3  B6   B12  Fol  Chol  Ca    Fe  Mg   P     K     Zn  Se
        switch age {
        case 1...3:
            male = [300, 15, 15, 6, 30, 0.5, 0.5, 6, 0.5, 0.9, 150, 200, 700, 7, 80, 460, 2000, 3, 20]
            female = male
        case 4...8:
            male = [400, 25, 15, 7, 55, 0.6, 0.6, 8, 0.6, 1.2, 200, 250, 1000, 10, 130, 500, 2300, 5, 30]
            female = male
        case 9...13:
            male = [600, 45, 15, 11, 60, 0.9, 0.9, 12, 1.0, 1.8, 300, 375, 1300, 8, 240, 1250, 2500, 8, 40]
            female = [600, 45, 15, 11, 60, 0.9, 0.9, 12, 1.0, 1.8, 300, 375, 1300, 8, 240, 1250, 2300, 8, 40]
        case 14...18:
            male = [900, 75, 15, 15, 75, 1.2, 1.3, 16, 1.3, 2.4, 400, 550, 1300, 11, 410, 1250, 3000, 11, 55]
            female = [700, 65, 15, 15, 75, 1.0, 1.0, 14, 1.2, 2.4, 400, 400, 1300, 15, 360, 1250, 2300, 9, 55]
        case 19...30:
            male = [900, 90, 15, 15, 120, 1.2, 1.3, 16, 1.3, 2.4, 400, 550, 1000, 8, 400, 700, 3400, 11, 55]
            female = [700, 75, 15, 15, 90, 1.1, 1.1, 14, 1.3, 2.4, 400, 425, 1000, 18, 310, 700, 2600, 8, 55]
        case 31...50:
            male = [900, 90, 15, 15, 120, 1.2, 1.3, 16, 1.3, 2.4, 400, 550, 1000, 8, 420, 700, 3400, 11, 55]
            female = [700, 75, 15, 15, 90, 1.1, 1.1, 14, 1.3, 2.4, 400, 425, 1000, 18, 320, 700, 2600, 8, 55]
        case 51...70:
            male = [900, 90, 15, 15, 120, 1.2, 1.3, 16, 1.7, 2.4, 400, 550, 1000, 8, 420, 700, 3400, 11, 55]
            female = [700, 75, 15, 15, 90, 1.1, 1.1, 14, 1.5, 2.4, 400, 425, 1200, 8, 320, 700, 2600, 8, 55]
        default:
            male = [900, 90, 20, 15, 120, 1.2, 1.3, 16, 1.7, 2.4, 400, 550, 1200, 8, 420, 700, 3400, 11, 55]
            female = [700, 75, 20, 15, 90, 1.1, 1.1, 14, 1.5, 2.4, 400, 425, 1200, 8, 320, 700, 2600, 8, 55]
        }
        switch member.energySex {
        case .male: return row(male)
        case .female: return row(female)
        case nil: return row(zip(male, female).map { ($0 + $1) / 2 })
        }
    }

    /// Protein RDA: fixed values for children, 0.8 g per kg for adults.
    static func protein(for member: FamilyMember) -> Double? {
        guard let age = member.ageYears, age >= 1, member.energyContext != .pregnancyOrLactation else { return nil }
        switch age {
        case 1...3: return 13
        case 4...8: return 19
        case 9...13: return 34
        case 14...18:
            switch member.energySex { case .male: return 52; case .female: return 46; case nil: return 49 }
        default:
            if let weight = member.weightKg, weight.isFinite, (30...300).contains(weight) {
                return WeightGap.proteinGramsPerKilogram * weight
            }
            switch member.energySex { case .male: return 56; case .female: return 46; case nil: return 51 }
        }
    }

    static let units: [String: String] = [
        "protein": "г", "fat": "г", "carbohydrate": "г", "fiber": "г",
        "vitamin_a": "мкг", "vitamin_c": "мг", "vitamin_d": "мкг", "vitamin_e": "мг", "vitamin_k": "мкг",
        "vitamin_b1": "мг", "vitamin_b2": "мг", "vitamin_b3": "мг", "vitamin_b6": "мг", "vitamin_b12": "мкг",
        "folate": "мкг", "choline": "мг", "calcium": "мг", "iron": "мг", "magnesium": "мг",
        "phosphorus": "мг", "potassium": "мг", "zinc": "мг", "selenium": "мкг"
    ]

    /// Energy the person's plate is sized to, when the profile gives one.
    static func energy(for member: FamilyMember) -> Double? {
        WeightGap.targets(for: member)?.energy ?? PersonalPortions.profileDailyEnergy(member)
    }
}

struct DayIntake: Identifiable {
    let day: Int
    var kcal: Double = 0
    var nutrients: [String: Double] = [:]
    var hasFood = false
    var id: Int { day }
}

enum IntakeSource: String, CaseIterable, Identifiable {
    case plan, eaten
    var id: String { rawValue }
    var title: String { self == .plan ? "По плану" : "Съедено" }
}

struct NutritionStatsView: View {
    @EnvironmentObject var store: LadStore
    @State private var memberID: String?
    @State private var source: IntakeSource = .plan
    @State private var showAllNutrients = false

    private var member: FamilyMember {
        store.state.members.first { $0.id == memberID } ?? store.currentMember
    }

    private func intake(day: Int) -> DayIntake {
        var result = DayIntake(day: day)
        switch source {
        case .plan:
            for item in store.dayRecipes(for: member, day: day) {
                result.hasFood = result.hasFood || !item.recipe.isBeverage
                result.kcal += Double(item.recipe.kcal ?? 0) * item.portion
                for (key, value) in item.recipe.nutrients {
                    result.nutrients[key, default: 0] += value.amount * item.portion
                }
                if item.recipe.nutrients["protein"] == nil, let protein = item.recipe.protein {
                    result.nutrients["protein", default: 0] += Double(protein) * item.portion
                }
            }
        case .eaten:
            guard let start = Calendar.current.date(byAdding: .day, value: day, to: store.state.startDate),
                  let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return result }
            for entry in store.diary where entry.memberID == member.id && entry.eatenAt >= start && entry.eatenAt < end {
                for food in entry.foods {
                    result.hasFood = result.hasFood || !food.isBeverage
                    result.kcal += food.kcal ?? 0
                    for (key, value) in food.nutrients { result.nutrients[key, default: 0] += value.amount }
                }
            }
        }
        return result
    }

    /// Everything the cards show, computed once per render.
    private struct Snapshot {
        let days: [DayIntake]
        let counted: [DayIntake]
        let coverage: [Coverage]
    }

    private func makeSnapshot() -> Snapshot {
        let days = (0..<7).map(intake)
        let counted = days.filter { $0.hasFood && (source == .plan || $0.day <= store.currentDay) }
        func average(_ key: String) -> Double? {
            let values = counted.compactMap { $0.nutrients[key] }
            guard !counted.isEmpty, !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(counted.count)
        }
        var rows: [Coverage] = []
        if let norm = NutrientNorms.protein(for: member), let amount = average("protein") {
            rows.append(Coverage(key: "protein", amount: amount, norm: norm, unit: "г"))
        }
        if let energy = NutrientNorms.energy(for: member), let amount = average("fiber") {
            rows.append(Coverage(key: "fiber", amount: amount, norm: energy / 1000 * WeightGap.fiberGramsPerThousandKcal, unit: "г"))
        }
        if let norms = NutrientNorms.daily(for: member) {
            for key in NutrientNorms.keys {
                guard let norm = norms[key], let amount = average(key) else { continue }
                rows.append(Coverage(key: key, amount: amount, norm: norm, unit: NutrientNorms.units[key] ?? ""))
            }
        }
        return Snapshot(days: days, counted: counted, coverage: rows)
    }

    private struct Coverage: Identifiable {
        let key: String
        let amount: Double
        let norm: Double
        let unit: String
        var id: String { key }
        var ratio: Double { norm > 0 ? amount / norm : 0 }
        var missing: Double { max(0, norm - amount) }
    }


    private func sources(for key: String) -> [Recipe] {
        let disliked = store.state.dislikes ?? []
        return store.visibleRecipes.filter { recipe in
            !recipe.isBeverage && !recipe.isUnplanned && !recipe.isUnavailable &&
                store.isSelectedCourseRecipe(recipe.id) && !disliked.contains("\(member.id)|\(recipe.id)") &&
                (recipe.nutrients[key]?.amount ?? 0) > 0
        }
        .sorted { ($0.nutrients[key]?.amount ?? 0) > ($1.nutrients[key]?.amount ?? 0) }
        .prefix(3).map { $0 }
    }

    private func number(_ value: Double) -> String {
        value >= 10 ? String(Int(value.rounded())) : value.formatted(.number.precision(.fractionLength(0...1)))
    }

    var body: some View {
        let snapshot = makeSnapshot()
        ScrollViewReader { scroll in
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                peoplePicker
                Picker("Источник", selection: $source) {
                    ForEach(IntakeSource.allCases) { Text(L10n.text($0.title)).tag($0) }
                }.pickerStyle(.segmented)
                if member.hidesEnergyNumbers {
                    Text("Калории этого человека не показываются: в профиле отмечено расстройство пищевого поведения.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    energyCard(snapshot)
                    macroCard(snapshot)
                }
                deficitCard(snapshot).id("deficits")
                micronutrientCard(snapshot)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Нормы — рекомендуемое или достаточное суточное потребление по данным Национальных академий США для возраста и пола (NIH ODS). Расчёт идёт по известным ингредиентам рецептов, это ориентир, а не анализ и не назначение добавок.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(L10n.text("Источник норм"), destination: NutrientNorms.sourceURL)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                }
            }.padding(.horizontal, 21).padding(.top, 12).padding(.bottom, 40)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationTitle(L10n.text("Статистика"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if memberID == nil { memberID = store.currentMember.id }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--screenshot-deficits") {
                DispatchQueue.main.async { scroll.scrollTo("deficits", anchor: .top) }
            }
            #endif
        }
        }
    }

    private var peoplePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.state.members) { person in
                    Button { memberID = person.id } label: {
                        Text(person.name).font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(person.id == member.id ? .white : Palette.ink)
                            .background(person.id == member.id ? Palette.sage : .white, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(title)).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func energyCard(_ snapshot: Snapshot) -> some View {
        let target = NutrientNorms.energy(for: member)
        let values = snapshot.days
        return card("Калории по дням", subtitle: target.map { L10n.format("Ориентир: ~%d ккал в день", Int($0.rounded())) }
                    ?? L10n.text("Укажите возраст в профиле, чтобы увидеть ориентир.")) {
            Chart {
                ForEach(values) { day in
                    BarMark(x: .value("День", store.dayLabels[day.day]), y: .value("ккал", day.kcal))
                        .foregroundStyle(day.day == store.currentDay ? Palette.terracotta : Palette.sage)
                        .cornerRadius(5)
                }
                if let target {
                    RuleMark(y: .value("Ориентир", target))
                        .foregroundStyle(Palette.ink.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
            let counted = snapshot.counted
            if !counted.isEmpty {
                let mean = counted.reduce(0) { $0 + $1.kcal } / Double(counted.count)
                Text(target.map { L10n.format("В среднем ~%d ккал в день · %d%% ориентира", Int(mean.rounded()), Int((mean / $0 * 100).rounded())) }
                     ?? L10n.format("В среднем ~%d ккал в день", Int(mean.rounded())))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
            } else {
                Text(source == .plan ? "В плане недели пока нет блюд для этого человека." : "В дневнике пока нет записей за эту неделю.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }
    }

    private struct MacroPoint: Identifiable {
        let day: String
        let name: String
        let kcal: Double
        var id: String { day + name }
    }

    private func macroCard(_ snapshot: Snapshot) -> some View {
        let points: [MacroPoint] = snapshot.days.flatMap { day -> [MacroPoint] in
            let label = store.dayLabels[day.day]
            return [
                MacroPoint(day: label, name: NutrientGuide.name("protein"), kcal: (day.nutrients["protein"] ?? 0) * 4),
                MacroPoint(day: label, name: NutrientGuide.name("fat"), kcal: (day.nutrients["fat"] ?? 0) * 9),
                MacroPoint(day: label, name: NutrientGuide.name("carbohydrate"), kcal: (day.nutrients["carbohydrate"] ?? 0) * 4)
            ]
        }
        return card("Белки, жиры, углеводы", subtitle: L10n.text("Энергия из каждого источника по дням, ккал")) {
            Chart(points) { point in
                BarMark(x: .value("День", point.day), y: .value("ккал", point.kcal))
                    .foregroundStyle(by: .value("Нутриент", point.name))
            }
            .chartForegroundStyleScale([
                NutrientGuide.name("protein"): Palette.sage,
                NutrientGuide.name("fat"): Palette.terracotta,
                NutrientGuide.name("carbohydrate"): Palette.ink.opacity(0.45)
            ])
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
        }
    }

    private func deficitCard(_ snapshot: Snapshot) -> some View {
        let short = snapshot.coverage.filter { $0.ratio < 0.8 }.sorted { $0.ratio < $1.ratio }
        return card("Чего не хватает", subtitle: NutrientNorms.daily(for: member) == nil
                    ? L10n.text("Для норм нужен возраст в профиле. Для беременности и кормления нормы не показываем.")
                    : L10n.text("В среднем за день по сравнению с нормой для возраста и пола")) {
            if snapshot.counted.isEmpty {
                Text("Нет данных за неделю.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            } else if short.isEmpty {
                Label(L10n.text("Всё, что удаётся посчитать, покрыто хотя бы на 80%."), systemImage: "checkmark.seal")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
            } else {
                ForEach(short.prefix(6)) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(NutrientGuide.name(row.key)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(L10n.format("%d%% нормы", Int((row.ratio * 100).rounded())))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.terracotta)
                        }
                        Text(L10n.format("Не хватает ~%@ в день", "\(number(row.missing)) \(L10n.text(row.unit))"))
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        let options = sources(for: row.key)
                        if !options.isEmpty {
                            Text(L10n.format("Больше всего в: %@", options.map { L10n.text($0.title) }.joined(separator: ", ")))
                                .font(.system(size: 12)).foregroundStyle(Palette.sage)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if row.id != short.prefix(6).last?.id { Rectangle().fill(Palette.line).frame(height: 1) }
                }
            }
        }
    }

    private func micronutrientCard(_ snapshot: Snapshot) -> some View {
        let rows = snapshot.coverage.sorted { $0.ratio < $1.ratio }
        let visible = showAllNutrients ? rows : Array(rows.prefix(8))
        return card("Витамины и минералы", subtitle: L10n.text("Доля суточной нормы в среднем за день")) {
            if rows.isEmpty {
                Text("Нет данных для расчёта.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            ForEach(visible) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(NutrientGuide.name(row.key)).font(.system(size: 13)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(number(row.amount)) / \(number(row.norm)) \(L10n.text(row.unit))")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.line)
                            Capsule().fill(row.ratio < 0.8 ? Palette.terracotta : Palette.sage)
                                .frame(width: max(4, width * min(1, row.ratio)))
                        }
                    }.frame(height: 7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NutrientGuide.name(row.key))
                .accessibilityValue(L10n.format("%d%% нормы", Int((row.ratio * 100).rounded())))
            }
            if rows.count > 8 {
                Button(showAllNutrients ? L10n.text("Свернуть") : L10n.format("Ещё нутриенты: %d", rows.count - 8)) {
                    withAnimation { showAllNutrients.toggle() }
                }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
            }
        }
    }
}
