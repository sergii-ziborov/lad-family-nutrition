import SwiftUI

private struct OpenCatalogueTabKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openCatalogueTab: () -> Void {
        get { self[OpenCatalogueTabKey.self] }
        set { self[OpenCatalogueTabKey.self] = newValue }
    }
}

@main struct LadApp: App {
    @StateObject private var store = LadStore()
    @StateObject private var purchases = AppPurchases.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(store)
                .tint(Palette.sage)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshClock(); store.personalServicesForeground()
                        Task {
                            await purchases.refreshEntitlements()
                            await purchases.refreshPurchaseAvailability()
                            await store.refreshReferencePrices(announce: false)
                        }
                    }
                }
                .task {
                    store.startPersonalServices()
                    await purchases.start()
                    await store.refreshCourseCatalog()
                    await store.refreshReferencePrices(announce: false)
                }
                .onChange(of: purchases.catalogProof) { _, proof in
                    if proof == nil { store.returnToFreeCatalog() }
                    Task { await store.refreshCourseCatalog() }
                }
        }
    }
}

struct AppShell: View {
    @EnvironmentObject var store: LadStore
    @AppStorage(L10n.languageKey) private var language = "system"
    @State private var selected = 0
    private var screenshotRecipe: Recipe? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--screenshot-recipe"), args.indices.contains(index + 1) {
            return store.allRecipes.first { $0.id == args[index + 1] }
        }
        #endif
        return nil
    }
    private var screenshotCourseID: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--screenshot-course"), args.indices.contains(index + 1) {
            return args[index + 1]
        }
        #endif
        return nil
    }
    private var screenshotMember: FamilyMember? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-profile") { return store.state.members.first }
        #endif
        return nil
    }
    private var screenshotPage: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        for page in ["diary", "entry", "ready", "settings", "leftovers", "ingredient", "price-editor", "weight", "legal", "stats", "meal"] where args.contains("--screenshot-" + page) { return page }
        #endif
        return nil
    }
    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--screenshot-tab"), args.indices.contains(index + 1),
           let tab = Int(args[index + 1]), (0...4).contains(tab) {
            _selected = State(initialValue: tab)
        }
        #endif
    }
    var body: some View {
        TabView(selection: $selected) {
            NavigationStack {
                if screenshotPage == "diary" { FoodDiaryReport() }
                else if screenshotPage == "entry", let entry = store.diary.first { DiaryEntryEditor(entry: entry) }
                else if screenshotPage == "ready", let recipe = Recipe.all.first(where: { $0.id == "pancakes" }) { ReadyDishSheet(recipe: recipe, portions: 3) }
                else if screenshotPage == "settings" { LanguageSettingsSheet() }
                else if screenshotPage == "leftovers" { PreparedFoodView() }
                else if screenshotPage == "ingredient" { IngredientDetailView(name: "Йогурт греческий") }
                else if screenshotPage == "price-editor" { IngredientPriceEditor(name: "Йогурт греческий") }
                else if screenshotPage == "weight" { WeightHistoryView() }
                else if screenshotPage == "legal" { LegalDocumentView(page: .privacy) }
                else if screenshotPage == "stats" { NutritionStatsView() }
                else if screenshotPage == "meal" { RecipeDetailView(recipe: store.recipe(store.slot(store.currentDay, 2)), slot: store.slot(store.currentDay, 2)) }
                else if let screenshotRecipe { RecipeDetailView(recipe: screenshotRecipe) }
                else { TodayView() }
            }.tabItem { Label("Сегодня", systemImage: "sun.max") }.tag(0)
            NavigationStack { WeekView() }.tabItem { Label("Неделя", systemImage: "calendar") }.tag(1)
            NavigationStack {
                if let screenshotCourseID { CourseDetailView(courseID: screenshotCourseID) }
                else { CatalogHubView() }
            }.tabItem { Label("Каталог", systemImage: "books.vertical") }.tag(2)
            NavigationStack { ShoppingView() }.tabItem { Label("Продукты", systemImage: "refrigerator") }.tag(3)
            NavigationStack {
                if let screenshotMember { MemberEditor(member: screenshotMember) }
                else { FamilyView() }
            }.tabItem { Label("Семья", systemImage: "person.2") }.tag(4)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if selected == 2 { CatalogAdvertisement() }
        }
        .toolbarBackground(Palette.canvas, for: .tabBar)
        .environment(\.locale, Locale(identifier: language == "system" ? L10n.languageCode : language))
        .environment(\.openCatalogueTab) { selected = 2 }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            store.refreshClock(date)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.refreshClock()
        }
    }
}

struct MenuSourceEmptyState: View {
    @Environment(\.openCatalogueTab) private var openCatalogueTab

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: "books.vertical.circle")
                .font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Palette.sage)
            Text("Меню пока пустое")
                .font(.system(size: 23, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
            Text("Выберите кухню или курс в каталоге. Пока ничего не выбрано, блюда не появятся ни в дне, ни в неделе.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openCatalogueTab) {
                Label("Выбрать меню в каталоге", systemImage: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(14)
                    .foregroundStyle(.white)
                    .background(Palette.sage, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(21)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PageTitle: View {
    let eyebrow: String
    let title: String
    var body: some View {
        Text(L10n.text(title))
            .font(.system(size: 22, weight: .semibold, design: .serif))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.text(title)).font(.system(size: 23, weight: .semibold, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(Palette.ink)
            Spacer(minLength: 6)
            if let trailing {
                Text(L10n.text(trailing)).font(.system(size: 12, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(Palette.muted)
            }
        }
    }
}

struct PersonDots: View {
    let members: [FamilyMember]
    var size: CGFloat = 30
    var body: some View {
        HStack(spacing: -7) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                Text(member.initials).font(.system(size: size * 0.39, weight: .bold, design: .rounded))
                    .frame(width: size, height: size)
                    .background([Palette.paleSage, Palette.peach, Color(red: 0.87, green: 0.84, blue: 0.73)][index % 3], in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .foregroundStyle(Palette.ink)
                    .accessibilityLabel(member.name)
            }
        }
    }
}

struct DayPicker: View {
    @EnvironmentObject var store: LadStore
    var body: some View {
        GeometryReader { geometry in
            let cellWidth = max(0, (geometry.size.width - 30) / 7)
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { day in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { store.selectedDay = day } } label: {
                        VStack(spacing: 9) {
                            Text(store.dayLabels[day]).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            Text(store.dayNumber(day)).font(.system(size: 18, weight: .semibold, design: .rounded))
                            Circle().fill(day == store.selectedDay ? .white : (day == 0 ? Palette.terracotta : .clear)).frame(width: 4, height: 4)
                        }
                        .foregroundStyle(day == store.selectedDay ? .white : Palette.ink)
                        .frame(width: cellWidth, height: 76)
                        .background(day == store.selectedDay ? Palette.sage : .white, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 76)
    }
}

struct TodayView: View {
    @EnvironmentObject var store: LadStore
    @State private var showPersonPicker = false
    @State private var showMealTimes = false
    @State private var editingSlot: MealSlot?
    @State private var warning: String?
    @State private var confirmClearOutside = false
    private var featuredSlot: MealSlot { store.suggestedSlot(on: store.currentDay) }
    var body: some View {
        GeometryReader { screen in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("LADLEKIN").font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2.1).foregroundStyle(Palette.terracotta)
                    Spacer(minLength: 8)
                    NavigationLink { NutritionStatsView() } label: {
                        Label(L10n.text("Статистика"), systemImage: "chart.bar.xaxis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.sage)
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(Palette.paleSage, in: Capsule())
                    }.accessibilityHint(L10n.text("Графики, витамины и нехватка за неделю"))
                    Button { showPersonPicker = true } label: {
                        Text(store.currentMember.initials).font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(Palette.sage).frame(width: 36, height: 36)
                            .background(Palette.paleSage, in: Circle())
                    }.accessibilityLabel(L10n.text("Выбрать человека"))
                }
                if store.hasSelectedCourses {
                OptionalSnackControl(day: store.currentDay)

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Следующее на кухне", trailing: featuredSlot.day == store.currentDay ? store.kinds[featuredSlot.kind].uppercased() : "СЛЕДУЮЩИЙ ДЕНЬ")
                    if store.recipe(featuredSlot).isUnplanned {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 30)).foregroundStyle(Palette.sage)
                            Text("Блюдо пока не выбрано").font(.system(size: 22, weight: .semibold, design: .serif))
                            Text("Подходящих блюд для этого приёма пока нет.")
                                .font(.system(size: 13)).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(23).background(.white, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                    NavigationLink { RecipeDetailView(recipe: store.recipe(featuredSlot), slot: featuredSlot) } label: {
                        ZStack(alignment: .bottomLeading) {
                            RecipePicture(recipe: store.recipe(featuredSlot))
                                .frame(width: max(0, screen.size.width - 42), height: 196).clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) { Image(systemName: "clock"); Text(L10n.format("%d минут", store.recipe(featuredSlot).minutes)) }
                                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.ultraThinMaterial, in: Capsule()).environment(\.colorScheme, .dark)
                                Text(L10n.text(store.recipe(featuredSlot).title)).font(.system(size: 22, weight: .semibold, design: .serif))
                                    .lineLimit(2).minimumScaleFactor(0.85)
                                if let notice = store.mealCardNotice(for: featuredSlot) {
                                    Text(notice).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                }
                                HStack {
                                    Text(L10n.format("%d за столом · %@", store.participating(featuredSlot).count,
                                                     L10n.text(DishVoice.cuisine(for: store.recipe(featuredSlot))))).font(.system(size: 13))
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .semibold))
                                }
                            }.foregroundStyle(.white).padding(14)
                        }.frame(width: max(0, screen.size.width - 42), height: 196)
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                    }.buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    MenuActionButton(title: "Время еды", icon: "clock") {
                        showMealTimes = true
                    }
                    if store.outsideFutureSlotCount > 0 {
                        Button { confirmClearOutside = true } label: {
                            Label(L10n.format("Убрать блюда вне курсов: %d", store.outsideFutureSlotCount),
                                  systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(Palette.terracotta)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.sage)
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 13) {
                    let daySlots = store.mealKinds(on: store.currentDay, forMember: store.currentMember.id).map { store.slot(store.currentDay, $0) }
                    let upcoming = daySlots.filter { !store.isPastWindow($0) }
                    let finished = daySlots.filter { store.isPastWindow($0) }
                    if !upcoming.isEmpty {
                        SectionHeading(title: "Ваш день", trailing: store.currentMember.name.uppercased())
                        ForEach(upcoming) { slot in
                            MealRow(slot: slot) { editingSlot = $0 }
                        }
                    }
                    if !finished.isEmpty {
                        SectionHeading(title: "Съедено за день", trailing: store.mealCutoffText(for: finished[0].kind))
                        ForEach(finished) { slot in
                            MealRow(slot: slot) { editingSlot = $0 }
                        }
                    }
                    DayNutrientSummary(day: store.currentDay)
                        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
                } else {
                    MenuSourceEmptyState()
                }
                TodayDiaryCard()
                }
                .frame(width: max(0, screen.size.width - 42), alignment: .leading)
                .padding(.horizontal, 21).padding(.top, 12).padding(.bottom, 24)
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .onAppear { store.maintainsDayMenu = true; store.scheduleDayMenuFill() }
        .sheet(isPresented: $showPersonPicker) { PersonPickerSheet() .presentationDetents([.medium]) }
        .sheet(isPresented: $showMealTimes) { MealTimesSheet() }
        .sheet(item: $store.replanPreview) { preview in ReplanPreviewSheet(preview: preview) }
        .sheet(item: $editingSlot) { slot in
            RecipeChooser(slot: slot) { recipe, allowDraft in
                warning = store.assign(recipe, to: slot, allowUnverifiedCourseDraft: allowDraft)
                if warning == nil { editingSlot = nil }
            }
        }
        .alert("Проверьте ограничения", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button("Понятно", role: .cancel) { warning = nil }
        } message: { Text(warning ?? "") }
        .confirmationDialog("Очистить будущие блюда вне выбранных курсов?", isPresented: $confirmClearOutside) {
            Button("Очистить будущий план") { store.clearFutureDishesOutsideCourses() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Отмеченные съеденными блюда останутся в истории. Пустые приёмы можно заполнить после выбора курса и пересчёта меню.")
        }
    }
}

struct MealRow: View {
    @EnvironmentObject var store: LadStore
    let slot: MealSlot
    let onEdit: (MealSlot) -> Void
    @State private var diaryDraft: DiaryEntry?
    var body: some View {
        let recipe = store.recipe(slot)
        let dishes = store.recipes(slot)
        let foodDishes = dishes.filter { !$0.isBeverage }
        let mealKcal = dishes.reduce(0.0) { $0 + Double($1.kcal ?? 0) * store.portion(for: store.currentMember, recipe: $1, slot: slot) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 13) {
                NavigationLink { RecipeDetailView(recipe: recipe, slot: slot) } label: {
                    RecipePicture(recipe: recipe, thumbnail: true).frame(width: 58, height: 58).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.kinds[slot.kind].uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(Palette.terracotta)
                    Text(L10n.text(recipe.title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if recipe.isUnplanned {
                        Text("Выберите курс и составьте меню").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    } else if recipe.isUnavailable {
                        Text("Подключите закрытый каталог").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    } else if dishes.allSatisfy({ $0.kcal != nil }) {
                        Text(foodDishes.count > 1
                             ? L10n.format("Блюд: %d · ~%d ккал", foodDishes.count, Int(mealKcal.rounded()))
                             : L10n.format("~%d ккал", Int(mealKcal.rounded())))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    if foodDishes.count > 1 {
                        Text(foodDishes.dropFirst().map { L10n.text($0.title) }.joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(Palette.sage)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if store.hasSelectedCourses, !recipe.isUnplanned {
                        MealBeveragesView(slot: slot)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.sage)
                    }
                    if !recipe.isUnplanned && store.isOutsideSelectedCourses(slot.recipeID, for: slot) {
                        Text("Вне выбранных курсов")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.terracotta)
                    }
                    if let notice = store.mealCardNotice(for: slot) {
                        Text(notice)
                            .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button { diaryDraft = store.diaryDraft(for: slot) } label: {
                    Image(systemName: store.isEaten(slot) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(store.isEaten(slot) ? Palette.sage : Palette.line)
                }.accessibilityLabel(store.isEaten(slot) ? "Изменить запись о съеденном" : "Отметить как съеденное")
                    .disabled(recipe.isUnplanned)
                    .disabled(slot.day > store.currentDay)
                    .disabled(!slot.memberIDs.contains(store.currentMember.id))
            }
            if let entry = store.diaryEntry(for: slot) {
                Text(L10n.format("Съел: %@", entry.foods.map(\.displayTitle).joined(separator: ", ")))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.sage)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MealActions(slot: slot, onEdit: onEdit) {
                diaryDraft = store.diaryDraft(for: slot)
            }
        }.padding(8).background(.white, in: RoundedRectangle(cornerRadius: 16))
            .sheet(item: $diaryDraft) { DiaryEntryEditor(entry: $0) }
    }
}

struct MealBeveragesView: View {
    @EnvironmentObject var store: LadStore
    let slot: MealSlot
    @State private var showPicker = false
    @State private var warning: String?
    private var currentSlot: MealSlot { store.state.slots.first { $0.id == slot.id } ?? slot }
    private var names: String {
        let titles = currentSlot.selectedBeverageIDs.compactMap { id in
            CourseBeverages.all.first { $0.id == id }.map { L10n.text($0.title) }
        }
        return titles.joined(separator: ", ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { showPicker = true } label: {
                Label(names.isEmpty ? L10n.text("Напитки") : L10n.format("Напитки: %@", names), systemImage: "cup.and.saucer")
                    .fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(.plain)
            if currentSlot.selectedBeverageIDs.contains("course-drink-red-wine") {
                Text(L10n.text("Алкоголь выбран вручную; при беременности его следует избегать. Проверьте индивидуальные противопоказания."))
                    .font(.system(size: 10)).foregroundStyle(Palette.terracotta)
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                List {
                    Section {
                        ForEach(CourseBeverages.all) { drink in
                            Button { warning = store.toggleBeverage(drink.id, for: currentSlot) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: currentSlot.selectedBeverageIDs.contains(drink.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Palette.sage)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L10n.text(drink.title)).foregroundStyle(Palette.ink)
                                        Text(drink.ingredients.map { ingredient in
                                            "\(L10n.text(ingredient.name)) \((ingredient.amount ?? 0).formatted(.number.precision(.fractionLength(0...1)))) \(L10n.text(ingredient.unit))"
                                        }.joined(separator: ", "))
                                            .font(.caption).foregroundStyle(Palette.muted)
                                    }
                                }
                            }
                        }
                    }
                    Button(L10n.text("Убрать все напитки")) { warning = store.setBeverages([], for: currentSlot) }
                }
                .font(.body)
                .navigationTitle(L10n.text("Напитки к приёму"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Готово")) { showPicker = false }
                } }
                .alert(L10n.text("Проверьте ограничения"), isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
                    Button(L10n.text("Понятно"), role: .cancel) { warning = nil }
                } message: { Text(warning ?? "") }
            }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--screenshot-drinks"), slot.day == store.currentDay, slot.kind == 0 {
                showPicker = true
            }
        }
        #endif
    }
}

struct MenuActionButton: View {
    enum Prominence { case primary, secondary, caution }
    let title: String
    let icon: String
    var prominence: Prominence = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.text(title), systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 34)
                .padding(.horizontal, 8)
                .foregroundStyle(prominence == .primary ? .white : prominence == .caution ? Palette.terracotta : Palette.sage)
                .background(prominence == .primary ? Palette.sage : prominence == .caution ? Palette.peach.opacity(0.45) : Palette.paleSage.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}

struct MealActions: View {
    @EnvironmentObject var store: LadStore
    let slot: MealSlot
    let onEdit: (MealSlot) -> Void
    let onPortion: () -> Void

    private var hasLoggedMeal: Bool { store.state.eatenIDs.contains { $0.hasPrefix("\(slot.id)-") } }
    private var canChange: Bool { slot.day >= store.currentDay && !hasLoggedMeal }
    private var portionDisabled: Bool { slot.day > store.currentDay || !slot.memberIDs.contains(store.currentMember.id) }

    var body: some View {
        VStack(spacing: 6) {
            if canChange && !store.isSkipped(slot) {
                HStack(spacing: 6) {
                    MenuActionButton(title: "Изменить блюдо", icon: "square.and.pencil") { onEdit(slot) }
                    if !store.recipe(slot).isUnplanned {
                        MenuActionButton(title: "Предложить другое", icon: "arrow.triangle.2.circlepath") {
                            store.proposeNotToday(slot)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                MenuActionButton(title: "Порция / съел другое", icon: "fork.knife") { onPortion() }
                    .disabled(portionDisabled)
                if canChange && !slot.memberIDs.isEmpty {
                    MenuActionButton(title: store.isSkipped(slot) ? "Вернуть в план" : "Пропустить приём",
                                     icon: store.isSkipped(slot) ? "arrow.uturn.backward" : "forward.end",
                                     prominence: store.isSkipped(slot) ? .secondary : .caution) {
                        store.toggleSkipped(slot)
                    }
                }
            }
        }
    }
}

struct PersonPickerSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Чей день смотрим?").font(.system(size: 25, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink).padding(.top, 20)
            ForEach(store.state.members) { member in
                Button {
                    store.state.selectedMemberID = member.id
                    dismiss()
                } label: {
                    HStack {
                        Text(member.initials).frame(width: 38, height: 38).background(Palette.paleSage, in: Circle())
                        VStack(alignment: .leading) {
                            Text(member.name).font(.system(size: 15, weight: .semibold))
                            Text(member.goal).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if member.id == store.state.selectedMemberID { Image(systemName: "checkmark").foregroundStyle(Palette.sage) }
                    }.foregroundStyle(Palette.ink).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 15))
                }.buttonStyle(.plain)
            }
            Spacer()
        }.padding(21).frame(maxWidth: .infinity, alignment: .leading).background(Palette.canvas.ignoresSafeArea())
    }
}
