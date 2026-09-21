import SwiftUI

struct WeekView: View {
    @EnvironmentObject var store: LadStore
    @State private var editingSlot: MealSlot?
    @State private var warning: String?
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 23) {
                PageTitle(eyebrow: "МЕНЮ ДЛЯ ВСЕХ", title: "Неделя без суеты")
                DayPicker()
                HStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack").font(.system(size: 23)).foregroundStyle(Palette.sage)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Готовим вместе").font(.system(size: 15, weight: .semibold))
                        Text("Блюда общие, порции у каждого свои").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 9) {
                    let dayRecipes = (0..<3).map { store.recipe(store.slot(store.selectedDay, $0)) }
                    let energy = dayRecipes.compactMap(\.kcal).reduce(0) { $0 + Int(Double($1) * store.currentMember.portion) }
                    let protein = dayRecipes.compactMap(\.protein).reduce(0) { $0 + Int(Double($1) * store.currentMember.portion) }
                    Text(dayRecipes.allSatisfy { $0.kcal != nil && $0.protein != nil } ?
                         "План для \(store.currentMember.name): ~\(energy) ккал · белок ~\(protein) г" :
                         "План для \(store.currentMember.name): нутриенты известны не для всех блюд")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    if let target = store.currentMember.dailyEnergyTarget, dayRecipes.allSatisfy({ $0.kcal != nil }), (store.currentMember.ageYears ?? 0) >= 18 {
                        Text("Ручной ориентир: \(target) ккал/день · разница \(energy - target) ккал")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Text("Калории и белок демо-блюд приблизительные. Для жиров, углеводов и микронутриентов пока нет проверенных исходных данных — неизвестно не означает ноль.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    HStack {
                        Button("Подобрать меню") { store.proposeDayMenu(store.selectedDay) }
                        Spacer()
                        if store.canUndoReplan { Button("Отменить подбор") { store.undoReplan() } }
                    }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
                SectionHeading(title: store.dateLabel(store.selectedDay).capitalized, trailing: "3 ПРИЁМА ПИЩИ")
                ForEach(0..<3, id: \.self) { kind in
                    let slot = store.slot(store.selectedDay, kind)
                    let recipe = store.recipe(slot)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 14) {
                            RecipePicture(recipe: recipe).frame(width: 94, height: 94).clipped().clipShape(RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.kinds[kind].uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Palette.terracotta)
                                Text(recipe.title).font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                                Text("\(recipe.minutes) мин · \(store.participating(slot).count) за столом").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                let match = store.readiness(recipe, portions: store.participating(slot).reduce(0) { $0 + $1.portion })
                                Text(match.missing.isEmpty && match.uncertain.isEmpty ? "Продукты есть дома" : "Не хватает: \((match.missing + match.uncertain).joined(separator: ", "))")
                                    .font(.system(size: 11)).foregroundStyle(match.missing.isEmpty && match.uncertain.isEmpty ? Palette.sage : Palette.terracotta)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 15)
                        HStack {
                            PersonDots(members: store.participating(slot))
                            Spacer()
                            Button("Изменить блюдо") { editingSlot = slot }
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                        }
                        Button("Не хочу в этот день — подобрать другое") { store.proposeNotToday(slot) }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.terracotta)
                            .padding(.top, 11)
                        HStack(spacing: 8) {
                            ForEach(store.state.members) { person in
                                Button { warning = store.toggleParticipant(person.id, in: slot) } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: slot.memberIDs.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                        Text(person.name)
                                    }.font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(slot.memberIDs.contains(person.id) ? Palette.sage : Palette.muted)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.top, 15)
                        if let issue = store.incompatibility(slot) {
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11)).foregroundStyle(Palette.terracotta).padding(.top, 9)
                        }
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 22))
                }
                Text("Участие задаётся для каждого приёма пищи. Изменения в плане автоматически отражаются в покупках.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 35)
        }.background(Palette.canvas.ignoresSafeArea())
            .sheet(item: $store.replanPreview) { preview in ReplanPreviewSheet(preview: preview) }
            .sheet(item: $editingSlot) { slot in RecipeChooser(slot: slot) { recipe in
                warning = store.assign(recipe, to: slot)
                if warning == nil { editingSlot = nil }
            }}
            .alert("Проверьте ограничения", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
                Button("Понятно", role: .cancel) { warning = nil }
            } message: { Text(warning ?? "") }
    }
}

struct RecipeChooser: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    let slot: MealSlot
    let onChoose: (Recipe) -> Void
    @State private var visibleCount = 12
    private var candidates: [Recipe] {
        store.allRecipes.filter { $0.mealKinds.contains(slot.kind) }
            .sorted {
                let left = store.readiness($0, portions: store.participating(slot).reduce(0) { $0 + $1.portion })
                let right = store.readiness($1, portions: store.participating(slot).reduce(0) { $0 + $1.portion })
                return left.missing.count + left.uncertain.count < right.missing.count + right.uncertain.count
            }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(candidates.prefix(visibleCount))) { recipe in
                        Button { onChoose(recipe) } label: {
                            HStack(spacing: 12) {
                                RecipePicture(recipe: recipe).frame(width: 75, height: 75).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(recipe.title).font(.system(size: 16, weight: .semibold))
                                    Text("\(recipe.minutes) мин · \(recipe.cuisine)").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    let match = store.readiness(recipe, portions: store.participating(slot).reduce(0) { $0 + $1.portion })
                                    Text(match.missing.isEmpty && match.uncertain.isEmpty ? "Всё есть дома" : "Не хватает: \((match.missing + match.uncertain).joined(separator: ", "))")
                                        .font(.system(size: 11)).foregroundStyle(match.missing.isEmpty && match.uncertain.isEmpty ? Palette.sage : Palette.terracotta)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Palette.sage)
                            }.foregroundStyle(Palette.ink).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                    if visibleCount < candidates.count {
                        ProgressView("Загружаем ещё блюда…")
                            .padding(12)
                            .onAppear { visibleCount = CatalogPaging.nextLimit(current: visibleCount, total: candidates.count, step: 12) }
                    }
                }.padding(20)
            }.background(Palette.canvas.ignoresSafeArea()).navigationTitle("Выбрать блюдо")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}

struct RecipesView: View {
    @EnvironmentObject var store: LadStore
    @State private var query = ""
    @State private var filter = "Все"
    @State private var showPrivateAccess = false
    @State private var visibleCount = 12
    private let filters = ["Все", "Есть дома", "Не хватает", "Любимые", "Закрытые", "Домашняя", "Средиземноморская"]
    private var results: [Recipe] {
        store.allRecipes.filter { recipe in
            (query.isEmpty || recipe.title.localizedCaseInsensitiveContains(query)) &&
            (filter == "Все" || (filter == "Любимые" ? store.isFavorite(recipe.id) :
                (filter == "Закрытые" ? recipe.isPrivate :
                (filter == "Есть дома" ? store.readiness(recipe).missing.isEmpty && store.readiness(recipe).uncertain.isEmpty :
                (filter == "Не хватает" ? !store.readiness(recipe).missing.isEmpty || !store.readiness(recipe).uncertain.isEmpty : recipe.cuisine == filter)))))
        }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                PageTitle(eyebrow: "ИДЕИ ДЛЯ СТОЛА", title: "Готовить с радостью")
                Button { showPrivateAccess = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield").font(.system(size: 21)).foregroundStyle(Palette.sage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Закрытая библиотека").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                            Text(store.privateCatalogStatus).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                    }.padding(15).background(Palette.paleSage.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Найти блюдо", text: $query).font(.system(size: 15))
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 15))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { name in
                            Button { filter = name } label: {
                                Text(name).font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 15).padding(.vertical, 10)
                                    .background(filter == name ? Palette.sage : .white, in: Capsule())
                                    .foregroundStyle(filter == name ? .white : Palette.ink)
                            }
                        }
                    }
                }.contentMargins(.trailing, 21)
                SectionHeading(title: "Идеи для первых недель", trailing: "\(results.count) БЛЮДА")
                Text("Открытые блюда демонстрационные, а закрытый каталог берётся с Hetzner. Состав и пищевая ценность требуют проверки перед использованием как рекомендаций.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("♥ — нравится; 👎 — не нравится для \(store.currentMember.name). Неподходящие блюда исключаются из нового подбора, а не удаляются из каталога.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                ForEach(Array(results.prefix(visibleCount))) { recipe in
                    ZStack(alignment: .bottomTrailing) {
                        NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                RecipePicture(recipe: recipe).frame(height: 190).frame(maxWidth: .infinity).clipped()
                                VStack(alignment: .leading, spacing: 6) {
                                    Text((recipe.isPrivate ? "ЗАКРЫТАЯ · " : "ДЕМО · ") + recipe.cuisine.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(Palette.terracotta)
                                    Text(recipe.title).font(.system(size: 21, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                                    Text(recipe.kcal.map { "\(recipe.minutes) минут · ~\($0) ккал на базовую порцию" } ?? "\(recipe.minutes) минут · калорийность не рассчитана")
                                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    let match = store.readiness(recipe)
                                    Text(match.missing.isEmpty && match.uncertain.isEmpty ? "Можно приготовить из запасов" : "Не хватает: \((match.missing + match.uncertain).joined(separator: ", "))")
                                        .font(.system(size: 11)).foregroundStyle(match.missing.isEmpty && match.uncertain.isEmpty ? Palette.sage : Palette.terracotta)
                                        .lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).padding(.trailing, 62)
                            }.background(.white, in: RoundedRectangle(cornerRadius: 22)).clipShape(RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                        VStack(spacing: 2) {
                            Button { store.toggleFavorite(recipe.id) } label: {
                                Image(systemName: store.isFavorite(recipe.id) ? "heart.fill" : "heart")
                                    .font(.system(size: 19)).foregroundStyle(Palette.terracotta).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(store.isFavorite(recipe.id) ? "Убрать из любимых" : "Нравится")
                            Button { store.toggleDislike(recipe.id) } label: {
                                Image(systemName: store.isDisliked(recipe.id) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                    .font(.system(size: 18)).foregroundStyle(store.isDisliked(recipe.id) ? Palette.terracotta : Palette.muted)
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(store.isDisliked(recipe.id) ? "Убрать отметку не нравится" : "Не нравится")
                        }.padding(8)
                    }
                }
                if visibleCount < results.count {
                    ProgressView("Загружаем ещё рецепты…")
                        .frame(maxWidth: .infinity).padding(14)
                        .onAppear { visibleCount = CatalogPaging.nextLimit(current: visibleCount, total: results.count, step: 12) }
                }
                if results.isEmpty { Text(filter == "Закрытые" ? "Подключите закрытую библиотеку или обновите каталог." : "Пока ничего не нашли. Попробуйте другой запрос.").foregroundStyle(Palette.muted) }
            }.padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 35)
        }.background(Palette.canvas.ignoresSafeArea())
            .onChange(of: query) { _, _ in visibleCount = 12 }
            .onChange(of: filter) { _, _ in visibleCount = 12 }
            .onChange(of: store.allRecipes.count) { _, _ in visibleCount = 12 }
            .sheet(isPresented: $showPrivateAccess) { PrivateCatalogSheet() }
    }
}

struct RecipeDetailView: View {
    @EnvironmentObject var store: LadStore
    let recipe: Recipe
    var slot: MealSlot? = nil
    @State private var showCooking = false
    private var portions: Double { slot.map { store.participating($0).reduce(0) { $0 + $1.portion } } ?? 1 }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 21) {
                RecipePicture(recipe: recipe).frame(height: 310).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                VStack(alignment: .leading, spacing: 9) {
                    Text(recipe.cuisine.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.8).foregroundStyle(Palette.terracotta)
                    Text(recipe.title).font(.system(size: 33, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    Text(recipe.caption).font(.system(size: 15)).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 18) {
                    Button { store.toggleFavorite(recipe.id) } label: {
                        Label(store.isFavorite(recipe.id) ? "Нравится" : "Нравится?", systemImage: store.isFavorite(recipe.id) ? "heart.fill" : "heart")
                    }
                    Button { store.toggleDislike(recipe.id) } label: {
                        Label(store.isDisliked(recipe.id) ? "Не нравится" : "Не нравится?", systemImage: store.isDisliked(recipe.id) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                HStack(spacing: 0) {
                    detailMetric("ВРЕМЯ", "\(recipe.minutes) мин")
                    Spacer()
                    detailMetric("НА ПОРЦИЮ", recipe.kcal.map { "~\($0) ккал" } ?? "нет данных")
                    Spacer()
                    detailMetric("БЕЛОК", recipe.protein.map { "~\($0) г" } ?? "нет данных")
                }.padding(19).background(.white, in: RoundedRectangle(cornerRadius: 19))
                if let slot {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Одна готовка, разные тарелки").font(.system(size: 19, weight: .semibold, design: .serif))
                        ForEach(store.participating(slot)) { member in
                            HStack {
                                Text(member.name).font(.system(size: 14))
                                Spacer()
                                Text(recipe.kcal.map { "\(Int(member.portion * 100))% · ~\(Int(Double($0) * member.portion)) ккал" } ?? "\(Int(member.portion * 100))% · ккал неизвестны")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.sage)
                            }
                        }
                    }.padding(18).background(Palette.paleSage.opacity(0.65), in: RoundedRectangle(cornerRadius: 19))
                    Button("Не хочу это блюдо в выбранный день — подобрать другое") {
                        store.proposeNotToday(slot)
                    }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.terracotta)
                }
                if !recipe.allergens.isEmpty {
                    Label("Указаны аллергены: \(recipe.allergens.joined(separator: ", "))", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(Palette.terracotta)
                }
                if recipe.isPrivate && !recipe.allergensVerified {
                    Label("Данные об аллергенах ещё не проверены. Планирование и готовка заблокированы.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(Palette.terracotta)
                }
                if let slot, let issue = store.incompatibility(slot) {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.terracotta)
                        .padding(15).background(Palette.peach.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Нутриенты")
                    if recipe.nutrients.isEmpty {
                        Text("Жиры, углеводы, клетчатка, витамины и минералы: данных пока нет. Неизвестное значение не считается нулём.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    } else {
                        ForEach(recipe.nutrients.keys.sorted(), id: \.self) { key in
                            if let value = recipe.nutrients[key] {
                                HStack {
                                    Text(nutrientLabel(key)).foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text("\((value.amount * portions).formatted(.number.precision(.fractionLength(0...1)))) \(value.unit)")
                                        .foregroundStyle(Palette.sage)
                                }.font(.system(size: 13))
                                Text("Источник: \(value.source) · полнота \(Int(value.coverage * 100))%")
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Ингредиенты", trailing: slot == nil ? "1 ПОРЦИЯ" : "НА ВСЕХ")
                    ForEach(recipe.ingredients) { ingredient in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ingredient.name).font(.system(size: 15))
                                let stock = PlanningCore.stock(for: ingredient, pantry: store.pantry)
                                if let amount = ingredient.amount, amount > 0 {
                                    Text(stock.known >= amount * portions ? "Есть дома" : (stock.uncertain ? "Есть, проверьте количество" : "Нужно докупить"))
                                        .font(.system(size: 11)).foregroundStyle(stock.known >= amount * portions ? Palette.sage : Palette.terracotta)
                                } else {
                                    Text(stock.known > 0 || stock.uncertain ? "Есть дома, количество уточняется" : "Проверьте наличие и количество")
                                        .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                                }
                            }
                            Spacer()
                            if let amount = ingredient.amount, amount > 0 {
                                Text("\((amount * portions).formatted(.number.precision(.fractionLength(0...1)))) \(ingredient.unit)")
                                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.sage)
                            } else {
                                Text("уточнить").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                            }
                        }.padding(.vertical, 5)
                        Rectangle().fill(Palette.line).frame(height: 1)
                    }
                }
                Button { showCooking = true } label: {
                    HStack { Image(systemName: "flame"); Text("Начать готовить"); Spacer(); Image(systemName: "arrow.right") }
                        .font(.system(size: 15, weight: .semibold)).padding(19).foregroundStyle(.white)
                        .background(Palette.sage, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain).disabled(recipe.isUnavailable || (recipe.isPrivate && !recipe.allergensVerified) || (slot.map { store.incompatibility($0) != nil } ?? false))
                    .opacity(recipe.isUnavailable || (recipe.isPrivate && !recipe.allergensVerified) || (slot.map { store.incompatibility($0) != nil } ?? false) ? 0.5 : 1)
                Text("Демо-рецепты и расчёты ориентировочные. Указанные аллергены не заменяют проверку полного состава и условий приготовления.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 21).padding(.top, 12).padding(.bottom, 38)
        }.background(Palette.canvas.ignoresSafeArea()).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCooking) { CookingView(recipe: recipe, portions: portions) }
            .sheet(item: $store.replanPreview) { preview in ReplanPreviewSheet(preview: preview) }
    }
    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
        }
    }
    private func nutrientLabel(_ id: String) -> String {
        ["fat": "Жиры", "carbohydrate": "Углеводы", "fiber": "Клетчатка", "iron": "Железо", "calcium": "Кальций", "vitamin_d": "Витамин D", "potassium": "Калий", "sodium": "Натрий"][id] ?? id
    }
}

struct CookingView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let portions: Double
    @State private var step = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Готовим вместе").font(.system(size: 27, weight: .semibold, design: .serif))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 27)).foregroundStyle(Palette.muted) }
            }
            Text(recipe.title).font(.system(size: 15)).foregroundStyle(Palette.muted)
            ProgressView(value: Double(step + 1), total: Double(recipe.steps.count)).tint(Palette.sage)
            Text("ШАГ \(step + 1) ИЗ \(recipe.steps.count)").font(.system(size: 12, weight: .bold)).tracking(1.7).foregroundStyle(Palette.terracotta)
            Text(recipe.steps[step]).font(.system(size: 27, weight: .medium, design: .serif)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("Ингредиенты рассчитаны на \(portions.formatted(.number.precision(.fractionLength(0...1)))) базовых порций")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Button {
                if step + 1 < recipe.steps.count { step += 1 } else { dismiss() }
            } label: {
                Text(step + 1 < recipe.steps.count ? "Следующий шаг" : "Готово")
                    .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(18)
                    .background(Palette.sage, in: RoundedRectangle(cornerRadius: 17)).foregroundStyle(.white)
            }
        }.padding(25).padding(.top, 14).background(Palette.canvas.ignoresSafeArea())
            .presentationDragIndicator(.visible)
    }
}

struct PrivateCatalogSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var token = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34)).foregroundStyle(Palette.sage)
                        .frame(width: 68, height: 68).background(Palette.paleSage, in: RoundedRectangle(cornerRadius: 20))
                    Text("Облако для семьи").font(.system(size: 27, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    Text("Семейный профиль и закрытые рецепты загружаются по HTTPS после проверки ключа. Профиль сохраняется в локальном аккаунте этого iPhone, ключ — в Keychain. Личные данные не входят в публичный репозиторий.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("https://адрес-сервера", text: $serverURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).textContentType(.URL)
                            .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 13))
                        SecureField("Личный ключ доступа", text: $token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    }
                    Text(store.privateCatalogStatus).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text(store.familyCloudStatus).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Button {
                        busy = true
                        Task {
                            await store.connectPrivateCatalog(url: serverURL, token: token)
                            token = ""
                            busy = false
                        }
                    } label: {
                        Text(busy ? "Подключаем…" : "Подключить облако")
                            .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(17)
                            .foregroundStyle(.white).background(Palette.sage, in: RoundedRectangle(cornerRadius: 15))
                    }.disabled(busy)
                    if PrivateRecipeAccess.isConfigured {
                        HStack {
                            Button("Обновить") {
                                Task {
                                    await store.refreshPrivateRecipes()
                                    await store.refreshFamily()
                                }
                            }
                            Spacer()
                            Button("Отключить", role: .destructive) { store.disconnectPrivateCatalog(); token = "" }
                        }.font(.system(size: 14, weight: .semibold)).padding(.top, 4)
                    }
                    Text("Доступ к серверу можно отозвать. Получивший рецепт пользователь всё равно сможет сохранить его содержимое вне приложения — серверная авторизация не делает уже выданные данные необратимо секретными.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 12)
                }.padding(21)
            }.background(Palette.canvas.ignoresSafeArea())
                .navigationTitle("Облако Лада").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }.onAppear { serverURL = store.privateCatalogURL }
    }
}
