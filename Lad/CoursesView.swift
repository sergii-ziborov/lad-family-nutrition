import SwiftUI

struct CollapsibleInfo<Content: View>: View {
    let title: String
    var icon = "info.circle"
    var tint: Color = Palette.sage
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content().padding(.top, 10)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(tint).foregroundStyle(tint)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ExpandableCourseText: View {
    let text: String
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 13)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.leading)
                .lineLimit(expanded || text.count <= 100 ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            if text.count > 100 {
                Button { expanded.toggle() } label: {
                    Label(L10n.text(expanded ? "Свернуть" : "Читать полностью"),
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                }.buttonStyle(.plain)
                    .accessibilityValue(L10n.text(expanded ? "Развёрнуто" : "Свёрнуто"))
            }
        }
    }
}

struct CourseTimingCard: View {
    let courses: [LadCourse]
    private var timedCourses: [LadCourse] { courses.filter { !$0.generalTimingRules.isEmpty } }
    private let kinds = ["Завтрак", "Обед", "Ужин"]
    private let icons = ["sunrise", "sun.max", "moon"]
    var body: some View {
        if !timedCourses.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("Рекомендуемые часы курса"), systemImage: "clock")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                ForEach(timedCourses) { course in
                    if courses.count > 1 {
                        Text(course.title).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(0..<3, id: \.self) { kind in
                        let rules = course.generalTimingRules.filter { $0.mealKind == kind }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Label(L10n.text(kinds[kind]), systemImage: icons[kind])
                                    .foregroundStyle(Palette.ink)
                                Spacer(minLength: 6)
                                Text(rules.isEmpty ? L10n.text("час не указан") : rules.compactMap(\.recommendedTimingLabel).joined(separator: " · "))
                                    .foregroundStyle(rules.isEmpty ? Palette.muted : Palette.sage)
                                    .multilineTextAlignment(.trailing)
                            }.font(.system(size: 13, weight: .medium))
                        }
                    }
                }
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct CourseRuleWarningPanel: View {
    @EnvironmentObject var store: LadStore
    let warnings: [CourseRuleWarning]

    var body: some View {
        if !warnings.isEmpty {
            CollapsibleInfo(title: L10n.format("Рекомендации для меню: %d", warnings.count),
                            icon: "info.circle", tint: Palette.terracotta) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(warnings) { warning in
                    Text("\(warning.day.map { store.dateLabel($0) + " · " } ?? "")\(warning.scope == "week" ? L10n.text("Неделя") + " · " : "")\(warning.text)")
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Это рекомендации источников, а не запрет: меню можно изменить или применить всё равно.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.terracotta)
            }
        }
    }
}

struct CatalogHubView: View {
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Каталог", selection: $section) {
                Text("Курсы").tag(0)
                Text("Рецепты").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 21)
            .padding(.top, 12)
            .padding(.bottom, 7)
            .background(Palette.canvas)
            if section == 0 { CoursesView() }
            else { RecipesView() }
        }
        .background(Palette.canvas.ignoresSafeArea())
    }
}

struct CoursesView: View {
    @EnvironmentObject var store: LadStore
    @State private var confirmDeselectAll = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageTitle(eyebrow: "ОДНА КУХНЯ", title: "Здоровое питание")
                if store.courses.contains(where: \.isCombinedDefaultMenu) { CompleteCourseOffer() }
                if store.selectedCourses.isEmpty {
                    Label("Ничего не выбрано · меню дня и недели пустое", systemImage: "circle.dashed")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.terracotta)
                }
                if !store.courses.isEmpty {
                    CollapsibleInfo(title: L10n.format("Выбрано курсов: %d", store.selectedCourses.count),
                                    icon: "checkmark.circle") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(store.selectedCourses) { course in
                                Text(course.title).font(.system(size: 13)).foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: 12) {
                                Button("Выбрать все") { store.selectAllCourses() }
                                    .disabled(store.selectedCourses.count == store.courses.count)
                                Button("Снять весь выбор") { confirmDeselectAll = true }
                                    .disabled(store.selectedCourses.isEmpty)
                            }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                        }
                    }
                }
                if store.courses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "books.vertical").font(.system(size: 27)).foregroundStyle(Palette.sage)
                        Text("Пока нет опубликованных курсов")
                            .font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                        Text("Подключите каталог или обновите его. Черновики и закрытые блюда без доступа здесь не показываются.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                } else {
                    ForEach(store.courses) { course in CourseCatalogueCard(course: course) }
                }
            }
            .padding(.horizontal, 21)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .refreshable { await store.refreshCourseCatalog() }
        .sheet(item: $store.replanPreview) { preview in ReplanPreviewSheet(preview: preview) }
        .confirmationDialog("Убрать все курсы из меню?", isPresented: $confirmDeselectAll) {
            Button("Очистить меню дня и недели") { store.deselectAllCourses() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Меню и покупки очистятся; уже отмеченные съеденными блюда останутся в истории.")
        }
    }
}

struct CourseCatalogueCard: View {
    @EnvironmentObject var store: LadStore
    let course: LadCourse
    private var isSelected: Bool { store.activeCourseIDs.contains(course.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                Label(course.availabilityLabel, systemImage: course.isFree ? "gift" : "checkmark.shield")
                Spacer(minLength: 4)
                Label(L10n.text(isSelected ? "Выбрано" : "Не выбрано"),
                      systemImage: isSelected ? "checkmark.circle.fill" : "circle")
            }.font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Palette.sage : Palette.muted)
            NavigationLink { CourseDetailView(courseID: course.id) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(course.title).font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").foregroundStyle(Palette.sage).padding(.top, 5)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !course.isCombinedDefaultMenu {
                Text(course.summary)
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L10n.format("Блюд в программе: %d", course.recipeIDs.count))
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(isSelected ? Palette.sage : .clear, lineWidth: 1.5))
    }
}

struct CourseDetailView: View {
    @EnvironmentObject var store: LadStore
    let courseID: String
    @State private var confirmRemoval = false

    private var course: LadCourse? { store.courses.first { $0.id == courseID } }
    private var recipes: [Recipe] {
        guard let course else { return [] }
        return course.recipeIDs.compactMap { id in
            store.allRecipes.first { $0.id == id || $0.id == "private:\(id)" }
        }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                if let course {
                    Label(course.availabilityLabel, systemImage: course.isFree ? "gift" : "checkmark.shield")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                    Text(course.title)
                        .font(.system(size: 32, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if store.activeCourseIDs.contains(course.id) { confirmRemoval = true }
                        else { store.toggleCourse(course.id) }
                    } label: {
                        Label(store.activeCourseIDs.contains(course.id) ? "Убрать из подбора меню" : "Добавить в подбор меню",
                              systemImage: store.activeCourseIDs.contains(course.id) ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .foregroundStyle(.white)
                            .background(Palette.sage, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                    Text(course.isCombinedDefaultMenu
                         ? L10n.text("Одна кухня на всю семью. Порции у каждого свои.")
                         : course.summary)
                        .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    Text("Блюда программы")
                        .font(.system(size: 23, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    ForEach(0..<3, id: \.self) { kind in
                        let tagged = recipes.filter { $0.mealKinds.contains(kind) }
                        if !tagged.isEmpty {
                            Text(store.kinds[kind])
                                .font(.system(size: 19, weight: .semibold, design: .serif))
                                .foregroundStyle(Palette.ink)
                            ForEach(tagged) { recipe in
                                NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                                    HStack(spacing: 13) {
                                        RecipePicture(recipe: recipe, thumbnail: true).frame(width: 78, height: 78)
                                            .clipShape(RoundedRectangle(cornerRadius: 13))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(L10n.text(recipe.title))
                                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                                .foregroundStyle(Palette.ink)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(L10n.format("%d мин", recipe.minutes))
                                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                            Text(L10n.text(DishVoice.cuisine(for: recipe)))
                                                .font(.system(size: 11)).foregroundStyle(Palette.sage)
                                            if !recipe.isPlanEligible {
                                                Text("Уточните количества ингредиентов")
                                                    .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                                            }
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.right").foregroundStyle(Palette.sage)
                                    }
                                    .padding(12)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 17))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if recipes.isEmpty {
                        Text("В курсе пока нет доступных блюд.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                } else {
                    Text("Программа больше не доступна в текущем каталоге.")
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 21)
            .padding(.top, 22)
            .padding(.bottom, 35)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Убрать курс из подбора?", isPresented: $confirmRemoval) {
            Button("Убрать курс и очистить его блюда") { store.toggleCourse(courseID) }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Уже отмеченные съеденными блюда сохранятся. Остальные блюда этого курса исчезнут из плана и покупок.")
        }
    }

}

struct CourseServerSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = CourseCatalogAccess.savedURL ?? ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Адрес каталога") {
                    TextField("https://example.com", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Text("Бесплатные курсы доступны без ключа. Закрытый доступ подключается отдельно в разделе рецептов.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                Section {
                    Text(L10n.text(store.courseCatalogStatus)).font(.footnote).foregroundStyle(Palette.muted)
                    Button("Обновить каталог") {
                        saving = true
                        Task {
                            await store.setCourseCatalogURL(url)
                            saving = false
                            if !store.courses.isEmpty { dismiss() }
                        }
                    }.disabled(saving || url.isEmpty)
                }
            }
            .navigationTitle("Каталог программ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}
