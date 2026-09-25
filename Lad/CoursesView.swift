import SwiftUI

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
    @State private var showServer = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageTitle(eyebrow: "ПРОГРАММЫ ПИТАНИЯ", title: "Курсы для вашего стола")
                Text("Курс объединяет блюда и тему: домашняя кухня, кухни мира или индивидуальная программа. Выбранные курсы служат источником будущего меню; уже составленная неделя меняется только после подтверждения.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showServer = true } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "server.rack").foregroundStyle(Palette.sage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Каталог программ").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                            Text(L10n.text(store.courseCatalogStatus)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").foregroundStyle(Palette.sage)
                    }
                    .padding(15)
                    .background(Palette.paleSage.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
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
                    if !store.activeCourseIDs.isEmpty {
                        Button { store.proposeWeekMenu() } label: {
                            Label("Подобрать блюда из выбранных курсов", systemImage: "calendar.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .foregroundStyle(.white)
                                .background(Palette.sage, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                    ForEach(store.courses) { course in
                        NavigationLink { CourseDetailView(courseID: course.id) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(course.isFree ? "БЕСПЛАТНО" : "ПО ДОСТУПУ")
                                            .font(.system(size: 10, weight: .bold)).tracking(1.2)
                                            .foregroundStyle(Palette.terracotta)
                                        Text(course.title)
                                            .font(.system(size: 22, weight: .semibold, design: .serif))
                                            .foregroundStyle(Palette.ink)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right").foregroundStyle(Palette.sage)
                                }
                                Text(course.summary)
                                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(L10n.format("Блюд в программе: %d", course.recipeIDs.count))
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.sage)
                                if store.activeCourseIDs.contains(course.id) {
                                    Label("Используется для подбора меню", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 12)).foregroundStyle(Palette.sage)
                                }
                            }
                            .padding(19)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 21)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .refreshable { await store.refreshCourseCatalog() }
        .sheet(isPresented: $showServer) { CourseServerSheet() }
        .sheet(item: $store.replanPreview) { preview in ReplanPreviewSheet(preview: preview) }
    }
}

struct CourseDetailView: View {
    @EnvironmentObject var store: LadStore
    let courseID: String

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
                    Text(course.isFree ? "БЕСПЛАТНЫЙ КУРС" : "КУРС ПО ДОСТУПУ")
                        .font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.terracotta)
                    Text(course.title)
                        .font(.system(size: 32, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(course.summary)
                        .font(.system(size: 15)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if course.category == "weight-management" {
                        Label("Калорийность и порции уточняются: в исходных страницах не указаны веса части продуктов и выход блюд. Пока это подборка рецептов, а не рассчитанная программа снижения веса.",
                              systemImage: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .background(Palette.peach.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button { store.toggleCourse(course.id) } label: {
                        Label(store.activeCourseIDs.contains(course.id) ? "Убрать из подбора меню" : "Добавить в подбор меню",
                              systemImage: store.activeCourseIDs.contains(course.id) ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .foregroundStyle(.white)
                            .background(Palette.sage, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                    Text("Блюда программы")
                        .font(.system(size: 23, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    Text("Завтрак, обед и ужин — теги блюд; курс не закрепляет блюда за конкретным днём.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    ForEach(0..<3, id: \.self) { kind in
                        let tagged = recipes.filter { $0.mealKinds.contains(kind) }
                        if !tagged.isEmpty {
                            Text(store.kinds[kind])
                                .font(.system(size: 19, weight: .semibold, design: .serif))
                                .foregroundStyle(Palette.ink)
                            ForEach(tagged) { recipe in
                                NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                                    HStack(spacing: 13) {
                                        RecipePicture(recipe: recipe).frame(width: 78, height: 78)
                                            .clipShape(RoundedRectangle(cornerRadius: 13))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(L10n.text(recipe.title))
                                                .font(.system(size: 16, weight: .semibold, design: .serif))
                                                .foregroundStyle(Palette.ink)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(L10n.format("%d мин", recipe.minutes))
                                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                            if !recipe.isPlanEligible {
                                                Text("Количества или аллергены требуют проверки")
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
