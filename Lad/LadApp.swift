import SwiftUI

@main struct LadApp: App {
    @StateObject private var store = LadStore()
    var body: some Scene {
        WindowGroup {
            AppShell()
                .environmentObject(store)
                .tint(Palette.sage)
                .preferredColorScheme(.light)
        }
    }
}

struct AppShell: View {
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
            NavigationStack { RecipesView() }.tabItem { Label("Рецепты", systemImage: "book.closed") }.tag(2)
            NavigationStack { ShoppingView() }.tabItem { Label("Покупки", systemImage: "basket") }.tag(3)
            NavigationStack { FamilyView() }.tabItem { Label("Семья", systemImage: "person.2") }.tag(4)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Palette.canvas, for: .tabBar)
    }
}

struct PageTitle: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(2.1).foregroundStyle(Palette.terracotta)
            Text(title).font(.system(size: 34, weight: .semibold, design: .serif)).tracking(-1.1).foregroundStyle(Palette.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionHeading: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 23, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted) }
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
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { day in
                Button { withAnimation(.easeInOut(duration: 0.2)) { store.selectedDay = day } } label: {
                    VStack(spacing: 9) {
                        Text(store.dayLabels[day]).font(.system(size: 11, weight: .medium))
                        Text(store.dayNumber(day)).font(.system(size: 18, weight: .semibold, design: .rounded))
                        Circle().fill(day == store.selectedDay ? .white : (day == 0 ? Palette.terracotta : .clear)).frame(width: 4, height: 4)
                    }
                    .foregroundStyle(day == store.selectedDay ? .white : Palette.ink)
                    .frame(maxWidth: .infinity).frame(height: 76)
                    .background(day == store.selectedDay ? Palette.sage : .white, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
            }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject var store: LadStore
    @State private var showPersonPicker = false
    private var dinner: MealSlot { store.slot(store.selectedDay, 2) }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .top) {
                    PageTitle(eyebrow: "ЛАД · ЕДИМ ВМЕСТЕ", title: store.selectedDay == store.currentDay ? "Хороший день\nначинается дома" : "План на \(store.dateLabel(store.selectedDay))")
                    Button { showPersonPicker = true } label: {
                        Text(store.currentMember.initials).font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundStyle(Palette.sage).frame(width: 43, height: 43)
                            .background(Palette.paleSage, in: Circle())
                    }.accessibilityLabel("Выбрать человека")
                }
                DayPicker()
                HStack(spacing: 11) {
                    Image(systemName: "heart.text.clipboard").font(.system(size: 19)).foregroundStyle(Palette.sage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Одна кухня — разные порции").font(.system(size: 14, weight: .semibold))
                        Text("Сегодня готовим для \(store.state.members.count) человек").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    PersonDots(members: store.state.members, size: 27)
                }.foregroundStyle(Palette.ink).padding(16).background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 19))

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "В центре стола", trailing: "СЕГОДНЯ НА УЖИН")
                    NavigationLink { RecipeDetailView(recipe: store.recipe(dinner), slot: dinner) } label: {
                        ZStack(alignment: .bottomLeading) {
                            RecipePicture(recipe: store.recipe(dinner)).frame(height: 260).frame(maxWidth: .infinity).clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) { Image(systemName: "clock"); Text("\(store.recipe(dinner).minutes) минут") }
                                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule()).environment(\.colorScheme, .dark)
                                Text(store.recipe(dinner).title).font(.system(size: 27, weight: .semibold, design: .serif))
                                HStack {
                                    Text("\(store.participating(dinner).count) порции · \(store.recipe(dinner).cuisine)").font(.system(size: 13))
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .semibold))
                                }
                            }.foregroundStyle(.white).padding(20)
                        }.frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 25))
                    }.buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 13) {
                    SectionHeading(title: "Ваш день", trailing: store.currentMember.name.uppercased())
                    ForEach(0..<3, id: \.self) { kind in
                        let slot = store.slot(store.selectedDay, kind)
                        MealRow(slot: slot)
                    }
                    Text("План и съеденное отмечаются отдельно. Пищевая ценность в этой демоверсии приблизительная.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 3)
                }
            }.padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 35)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .sheet(isPresented: $showPersonPicker) { PersonPickerSheet() .presentationDetents([.medium]) }
    }
}

struct MealRow: View {
    @EnvironmentObject var store: LadStore
    let slot: MealSlot
    var body: some View {
        let recipe = store.recipe(slot)
        HStack(spacing: 13) {
            NavigationLink { RecipeDetailView(recipe: recipe, slot: slot) } label: {
                RecipePicture(recipe: recipe).frame(width: 72, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.kinds[slot.kind].uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(Palette.terracotta)
                Text(recipe.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text(recipe.isUnavailable ? "Подключите закрытый каталог" : "~\(Int(Double(recipe.kcal) * store.currentMember.portion)) ккал · \(recipe.minutes) мин")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Button { store.toggleEaten(slot) } label: {
                Image(systemName: store.isEaten(slot) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .light)).foregroundStyle(store.isEaten(slot) ? Palette.sage : Palette.line)
            }.accessibilityLabel(store.isEaten(slot) ? "Убрать отметку о съеденном" : "Отметить как съеденное")
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
