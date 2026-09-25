import SwiftUI

@main struct LadApp: App {
    @StateObject private var store = LadStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(store)
                .tint(Palette.sage)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshClock() }
                }
        }
    }
}

struct AppShell: View {
    @EnvironmentObject var store: LadStore
    @State private var selected = 0
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
            NavigationStack { TodayView() }.tabItem { Label("Сегодня", systemImage: "sun.max") }.tag(0)
            NavigationStack { WeekView() }.tabItem { Label("Неделя", systemImage: "calendar") }.tag(1)
            NavigationStack { CatalogHubView() }.tabItem { Label("Каталог", systemImage: "books.vertical") }.tag(2)
            NavigationStack { ShoppingView() }.tabItem { Label("Продукты", systemImage: "refrigerator") }.tag(3)
            NavigationStack { FamilyView() }.tabItem { Label("Семья", systemImage: "person.2") }.tag(4)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Palette.canvas, for: .tabBar)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            store.refreshClock(date)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.refreshClock()
        }
    }
}

struct PageTitle: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text(eyebrow).uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2.1).foregroundStyle(Palette.terracotta)
            Text(L10n.text(title)).font(.system(size: 34, weight: .semibold, design: .serif)).tracking(-1.1).foregroundStyle(Palette.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var editingSlot: MealSlot?
    @State private var warning: String?
    private var featuredSlot: MealSlot { store.suggestedSlot() }
    var body: some View {
        GeometryReader { screen in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("ЛАД · ЕДИМ ВМЕСТЕ").font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(2.1).foregroundStyle(Palette.terracotta)
                        Spacer(minLength: 8)
                        Button { showPersonPicker = true } label: {
                            Text(store.currentMember.initials).font(.system(size: 18, weight: .bold, design: .serif))
                                .foregroundStyle(Palette.sage).frame(width: 43, height: 43)
                                .background(Palette.paleSage, in: Circle())
                        }.accessibilityLabel("Выбрать человека")
                    }
                    Text(store.selectedDay == store.currentDay ? L10n.text("Хороший день\nначинается дома") :
                         L10n.format("План на %@", store.dateLabel(store.selectedDay)))
                        .font(.system(size: 34, weight: .semibold, design: .serif)).tracking(-1.1)
                        .lineLimit(2).minimumScaleFactor(0.75).foregroundStyle(Palette.ink)
                }
                DayPicker()
                VStack(alignment: .leading, spacing: 11) {
                    if store.hasSelectedCourses {
                        Text("Выбраны курсы: меню изменится только после подтверждения. Блюда вне курсов отмечены ниже.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { store.proposeDayMenu(store.selectedDay) } label: {
                        Label(store.hasSelectedCourses ? L10n.text("Меню дня из выбранных курсов") : L10n.text("Подобрать меню дня"),
                              systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { store.proposeWeekMenu() } label: {
                        Label("Пересчитать оставшуюся неделю", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.sage)
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 11) {
                        Image(systemName: "heart.text.clipboard").font(.system(size: 19)).foregroundStyle(Palette.sage)
                        Text("Одна кухня — разные порции").font(.system(size: 14, weight: .semibold))
                            .lineLimit(2).minimumScaleFactor(0.85)
                    }
                    HStack {
                        Text(L10n.format("Сегодня готовим для %d человек", store.state.members.count))
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Spacer(minLength: 8)
                        PersonDots(members: store.state.members, size: 27)
                    }
                }.foregroundStyle(Palette.ink).padding(16).background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 19))

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Следующее на кухне", trailing: featuredSlot.day == store.currentDay ? store.kinds[featuredSlot.kind].uppercased() : "СЛЕДУЮЩИЙ ДЕНЬ")
                    NavigationLink { RecipeDetailView(recipe: store.recipe(featuredSlot), slot: featuredSlot) } label: {
                        ZStack(alignment: .bottomLeading) {
                            RecipePicture(recipe: store.recipe(featuredSlot))
                                .frame(width: max(0, screen.size.width - 42), height: 260).clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) { Image(systemName: "clock"); Text(L10n.format("%d минут", store.recipe(featuredSlot).minutes)) }
                                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule()).environment(\.colorScheme, .dark)
                                Text(L10n.text(store.recipe(featuredSlot).title)).font(.system(size: 27, weight: .semibold, design: .serif))
                                    .lineLimit(2).minimumScaleFactor(0.85)
                                Text(store.availabilityTitle(for: featuredSlot))
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(2)
                                HStack {
                                    Text(L10n.format("%d порции · %@", store.participating(featuredSlot).count,
                                                     L10n.text(store.recipe(featuredSlot).cuisine))).font(.system(size: 13))
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .semibold))
                                }
                            }.foregroundStyle(.white).padding(20)
                        }.frame(width: max(0, screen.size.width - 42), height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                    }.buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 13) {
                    SectionHeading(title: "Ваш день", trailing: store.currentMember.name.uppercased())
                    ForEach(0..<3, id: \.self) { kind in
                        let slot = store.slot(store.selectedDay, kind)
                        MealRow(slot: slot) { editingSlot = $0 }
                    }
                    Text("План и съеденное отмечаются отдельно. Пищевая ценность в этой демоверсии приблизительная.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 3)
                }
                }
                .frame(width: max(0, screen.size.width - 42), alignment: .leading)
                .padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 35)
            }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .sheet(isPresented: $showPersonPicker) { PersonPickerSheet() .presentationDetents([.medium]) }
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
    }
}

struct MealRow: View {
    @EnvironmentObject var store: LadStore
    let slot: MealSlot
    let onEdit: (MealSlot) -> Void
    var body: some View {
        let recipe = store.recipe(slot)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 13) {
                NavigationLink { RecipeDetailView(recipe: recipe, slot: slot) } label: {
                    RecipePicture(recipe: recipe).frame(width: 72, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.kinds[slot.kind].uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(Palette.terracotta)
                    Text(L10n.text(recipe.title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recipe.isUnavailable ? L10n.text("Подключите закрытый каталог") :
                        (recipe.kcal.map { L10n.format("~%d ккал · %d мин", Int(Double($0) * store.currentMember.portion), recipe.minutes) } ??
                         L10n.format("Калорийность неизвестна · %d мин", recipe.minutes)))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if store.isOutsideSelectedCourses(slot.recipeID) {
                        Text("Вне выбранных курсов")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.terracotta)
                    }
                    Text(store.availabilityTitle(for: slot))
                        .font(.system(size: 11)).foregroundStyle(store.requirements(for: slot)?.isReady == true ? Palette.sage : Palette.terracotta)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.isPastWindow(slot) && !store.isEaten(slot) && !store.isSkipped(slot) {
                        Text("Обычное время прошло · можно отметить позже или пропустить")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 0)
                Button { store.toggleEaten(slot) } label: {
                    Image(systemName: store.isEaten(slot) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(store.isEaten(slot) ? Palette.sage : Palette.line)
                }.accessibilityLabel(store.isEaten(slot) ? "Убрать отметку о съеденном" : "Отметить как съеденное")
                    .disabled(!slot.memberIDs.contains(store.currentMember.id))
            }
            if store.isPastWindow(slot), !slot.memberIDs.isEmpty,
               !store.state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) {
                Button(store.isSkipped(slot) ? "Вернуть в план" : "Пропустить приём") {
                    store.toggleSkipped(slot)
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.terracotta)
            }
            if slot.day >= store.currentDay, !store.isSkipped(slot),
               !store.state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) {
                Button("Изменить блюдо") { onEdit(slot) }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.sage)
                Button {
                    store.proposeNotToday(slot)
                } label: {
                    Label(slot.day == store.currentDay
                          ? (store.isPastWindow(slot) ? "Поздний приём — подобрать другое" : "Сегодня не хочу — подобрать другое")
                          : "В этот день не хочу — подобрать другое",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 3)
                }.buttonStyle(.plain)
            }
        }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 20))
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
