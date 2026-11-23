import SwiftUI

struct ShoppingView: View {
    @EnvironmentObject var store: LadStore
    @State private var section = 0
    @State private var search = ""
    @State private var editorItem: PantryItem?
    @State private var purchaseNeed: ShoppingNeed?
    @State private var manualName = ""
    @State private var showManual = false
    @State private var visibleSuggestionCount = 24
    /// Nil shows the whole week; a number shows that plan day only.
    @State private var shoppingDay: Int?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-shopping") {
            _section = State(initialValue: 1)
        }
        if ProcessInfo.processInfo.arguments.contains("--screenshot-shopping-day") {
            _section = State(initialValue: 1)
            _shoppingDay = State(initialValue: 1)
        }
        if ProcessInfo.processInfo.arguments.contains("--screenshot-ingredients") {
            _section = State(initialValue: 2)
        }
        #endif
    }

    private var filteredPantry: [PantryItem] {
        store.pantry.filter { ProductNames.matches($0.name, query: search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var suggestions: [Ingredient] {
        PlanningCore.ingredientSuggestions(recipes: store.allRecipes, pantry: store.pantry, query: search)
            .sorted {
                if $0.category != $1.category { return $0.category.localizedStandardCompare($1.category) == .orderedAscending }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
    private var visibleSuggestions: [Ingredient] { Array(suggestions.prefix(visibleSuggestionCount)) }
    private var toBuy: [ShoppingNeed] {
        if let shoppingDay { return dayNeeds(shoppingDay) }
        return store.shoppingNeeds.filter { $0.missing > 0.001 || $0.amountUnknown }
    }
    /// What the open meals of one day still need after stock already set
    /// aside for earlier meals. Past, eaten and skipped meals are left out.
    private func dayNeeds(_ day: Int) -> [ShoppingNeed] {
        let plan = store.planRequirements
        var totals: [String: (line: ResolvedIngredient, required: Double, allocated: Double, unknown: Bool, slots: [String])] = [:]
        for slot in store.state.slots where slot.day == day {
            guard let result = plan.slots[slot.id],
                  result.availability == .active || result.availability == .needsReview else { continue }
            for line in result.ingredients {
                var entry = totals[line.id] ?? (line, 0, 0, false, [])
                if let required = line.required { entry.required += required } else { entry.unknown = true }
                entry.allocated += line.allocated
                entry.unknown = entry.unknown || line.uncertain
                if !entry.slots.contains(slot.id) { entry.slots.append(slot.id) }
                totals[line.id] = entry
            }
        }
        return totals.map { id, entry in
            ShoppingNeed(id: id, name: entry.line.name, unit: entry.line.unit, category: entry.line.category,
                         required: entry.required, available: entry.allocated, amountUnknown: entry.unknown,
                         aiEstimated: false, sourceSlots: entry.slots)
        }
        .filter { $0.missing > 0.001 || $0.amountUnknown }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageTitle(eyebrow: "ПРОДУКТЫ ДОМА И ДЛЯ МЕНЮ", title: "Продукты")
                Picker("Раздел", selection: $section) {
                    Text("Холодильник").tag(0)
                    Text("Покупки").tag(1)
                    Text("Ингредиенты").tag(2)
                }.pickerStyle(.segmented)
                if section == 0 { pantryContent }
                else if section == 1 { shoppingContent }
                else { IngredientCatalogueView() }
            }.padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 35)
        }.background(Palette.canvas.ignoresSafeArea())
            .onChange(of: search) { _, _ in visibleSuggestionCount = 24 }
            .onChange(of: store.allRecipes.count) { _, _ in visibleSuggestionCount = 24 }
            .onAppear { store.maintainsDayMenu = true; store.scheduleDayMenuFill() }
            .sheet(item: $editorItem) { item in PantryEditor(item: item) }
            .sheet(item: $purchaseNeed) { need in PurchaseEntrySheet(need: need) }
            .sheet(item: $store.replanPreview) { preview in ReplanPreviewSheet(preview: preview) }
            .alert("Добавить вручную", isPresented: $showManual) {
                TextField("Например, яблоки", text: $manualName)
                Button("Добавить") {
                    let name = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty && !store.state.extraShopping.contains(name) { store.state.extraShopping.append(name) }
                    manualName = ""
                }
                Button("Отмена", role: .cancel) { manualName = "" }
            } message: { Text("Ручные покупки не пропадают при пересчёте меню.") }
    }

    private var pantryContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "refrigerator.fill").font(.system(size: 25)).foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Что есть дома").font(.system(size: 17, weight: .semibold, design: .serif))
                    Text("Количество можно указать позже — неизвестный остаток не вычитаем из покупок.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField(L10n.text("Поиск продукта"), text: $search)
                    .textInputAutocapitalization(.sentences)
                Button {
                    editorItem = PantryItem(name: search, quantity: nil, unit: "г", category: "Другое")
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Palette.sage) }
                    .accessibilityLabel(L10n.text("Добавить новый продукт"))
            }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 15))
            if !filteredPantry.isEmpty {
                SectionHeading(title: "В запасе", trailing: L10n.format("%d ПОЗ.", filteredPantry.count))
                ForEach(filteredPantry) { item in
                    HStack(spacing: 11) {
                        NavigationLink { IngredientDetailView(name: item.name) } label: {
                            HStack(spacing: 11) {
                                IngredientPhoto(name: item.name).frame(width: 46, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.text(item.name)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                                    Text(stockLabel(item)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.sage)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if item.quantity != 0 {
                            Button("Закончилось") { store.markOut(item) }
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.terracotta)
                        }
                        Button { editorItem = item } label: {
                            Image(systemName: "pencil").foregroundStyle(Palette.sage).frame(width: 28, height: 40)
                        }.accessibilityLabel(L10n.format("Изменить %@", L10n.text(item.name)))
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
            }
            if !suggestions.isEmpty {
                Text(L10n.format("Ингредиенты из %d открытых и %d загруженных закрытых рецептов.%@",
                                 Recipe.all.count, store.privateRecipes.count,
                                 store.privateRecipes.isEmpty ? L10n.text(" Закрытый каталог пока не загружен.") : ""))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                SectionHeading(title: "Добавить из рецептов", trailing: L10n.format("%d ПОЗ.", suggestions.count))
                ForEach(Array(Set(visibleSuggestions.map(\.category))).sorted(), id: \.self) { category in
                    Text(L10n.text(category).uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Palette.muted)
                    ForEach(visibleSuggestions.filter { $0.category == category }) { ingredient in
                        HStack(spacing: 12) {
                            NavigationLink { IngredientDetailView(name: ingredient.name) } label: {
                                HStack(spacing: 11) {
                                    IngredientPhoto(name: ingredient.name).frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 11))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L10n.text(ingredient.name)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                                        if let product = IngredientCatalog.product(ingredient.name) {
                                            Text(product.description.localized).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                                        }
                                    }
                                    Spacer(minLength: 2)
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.sage)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button {
                                editorItem = PantryItem(name: ingredient.name, quantity: nil, unit: ingredient.unit, category: ingredient.category)
                            } label: {
                                Image(systemName: "plus.circle").font(.system(size: 23)).foregroundStyle(Palette.sage)
                                    .frame(width: 36, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(L10n.format("Добавить %@", L10n.text(ingredient.name)))
                        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                if visibleSuggestionCount < suggestions.count {
                    HStack { Spacer(); ProgressView(); Text("Загружаем ещё продукты…"); Spacer() }
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(12)
                        .onAppear {
                            visibleSuggestionCount = CatalogPaging.nextLimit(current: visibleSuggestionCount,
                                                                            total: suggestions.count, step: 24)
                        }
                }
            }
            if store.pantry.isEmpty { Text("Добавьте продукты — подбор блюд покажет, что уже можно приготовить и чего не хватает.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted) }
        }
    }

    private var shoppingDayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                dayChip(title: L10n.text("Неделя"), detail: L10n.text("всё"), selected: shoppingDay == nil) { shoppingDay = nil }
                ForEach(0..<7, id: \.self) { day in
                    dayChip(title: store.dayLabels[day], detail: store.dayNumber(day), selected: shoppingDay == day,
                            today: day == store.currentDay, past: day < store.currentDay) { shoppingDay = day }
                }
            }
        }
    }

    private func dayChip(title: String, detail: String, selected: Bool, today: Bool = false, past: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1)
            }
            .frame(minWidth: 44).padding(.horizontal, 8).padding(.vertical, 8)
            .foregroundStyle(selected ? .white : (today ? Palette.terracotta : Palette.ink))
            .background(selected ? Palette.sage : .white, in: RoundedRectangle(cornerRadius: 14))
            .opacity(past && !selected ? 0.55 : 1)
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func dayMenu(_ day: Int) -> some View {
        let kinds = store.mealKinds(on: day)
        SectionHeading(title: "Меню дня", trailing: store.dateLabel(day).uppercased())
        if kinds.isEmpty || kinds.allSatisfy({ store.recipe(store.slot(day, $0)).isUnplanned }) {
            Text("На этот день блюда ещё не выбраны. Выберите курс в каталоге — неделя заполнится сама.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        ForEach(kinds, id: \.self) { kind in
            let slot = store.slot(day, kind)
            let recipe = store.recipe(slot)
            NavigationLink { RecipeDetailView(recipe: recipe, slot: slot) } label: {
                HStack(spacing: 11) {
                    RecipePicture(recipe: recipe, thumbnail: true).frame(width: 46, height: 46).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.kinds[kind].uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.1)
                            .foregroundStyle(Palette.terracotta)
                        Text(L10n.text(recipe.title)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        let extras = store.recipes(slot).dropFirst().filter { !$0.isBeverage }
                        Text(store.isSkipped(slot) ? L10n.text("Приём пропущен") :
                                (extras.isEmpty ? L10n.format("%d за столом", store.participating(slot).count) :
                                    L10n.format("%d за столом · + %@", store.participating(slot).count,
                                                extras.map { L10n.text($0.title) }.joined(separator: ", "))))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.sage)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).disabled(recipe.isUnplanned)
        }
    }

    private var shoppingContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            shoppingDayChips
            HStack(spacing: 12) {
                Image(systemName: "basket.fill").font(.system(size: 24)).foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("%d продуктов докупить", toBuy.count))
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                    Text(shoppingDay.map { L10n.format("На %@: блюда дня минус то, что уже есть дома", store.dateLabel($0)) }
                         ?? L10n.text("Потребность на неделю минус известный запас дома"))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { showManual = true } label: {
                    Image(systemName: "plus").foregroundStyle(.white).frame(width: 40, height: 40)
                        .background(Palette.sage, in: Circle())
                }.accessibilityLabel(L10n.text("Добавить покупку вручную"))
            }.padding(17).background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
            if store.state.slots.contains(where: { store.recipe($0).isUnavailable }) {
                Label("Часть закрытых блюд не загружена. Расчёт покупок неполный.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Palette.terracotta)
            }
            if store.canUndoReplan {
                Button("Отменить последнее изменение меню") { store.undoReplan() }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
            }
            if let shoppingDay { dayMenu(shoppingDay) }
            if shoppingDay == nil, !store.state.extraShopping.isEmpty {
                SectionHeading(title: "Добавлено вручную")
                ForEach(store.state.extraShopping, id: \.self) { name in
                    HStack {
                        Button {
                            if store.state.boughtNames.contains(name) { store.state.boughtNames.remove(name) }
                            else { store.state.boughtNames.insert(name) }
                        } label: {
                            Label(L10n.text(name), systemImage: store.state.boughtNames.contains(name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Palette.ink)
                        }.buttonStyle(.plain)
                        Spacer()
                        Button { store.state.extraShopping.removeAll { $0 == name } } label: {
                            Image(systemName: "trash").foregroundStyle(Palette.muted)
                        }.accessibilityLabel(L10n.format("Удалить %@", L10n.text(name)))
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
                }
            }
            ForEach(Array(Set(toBuy.map(\.category))).sorted(), id: \.self) { category in
                SectionHeading(title: L10n.text(category))
                ForEach(toBuy.filter { $0.category == category }) { need in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top) {
                            NavigationLink { IngredientDetailView(name: need.name) } label: {
                                HStack(spacing: 10) {
                                    IngredientPhoto(name: need.name).frame(width: 46, height: 46)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(L10n.text(need.name)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Spacer()
                            Text(need.required > 0 ? "\(need.aiEstimated ? "≈" : "")\(format(need.missing)) \(L10n.text(need.unit))" : L10n.text("уточнить"))
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.sage)
                        }
                        if need.required > 0 {
                            Text(L10n.format("Расчётная потребность %@ · выделено из запасов %@ %@",
                                             format(need.required), format(need.available), L10n.text(need.unit)))
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        if need.amountUnknown {
                            Label("Количество рецепта или остатка неизвестно — проверьте перед покупкой", systemImage: "questionmark.circle")
                                .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                        }
                        Text(sourceLabel(need)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Button("Внести фактическую покупку") { purchaseNeed = need }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            if toBuy.isEmpty {
                Text(shoppingDay == nil ? "Нет рассчитанных покупок. Проверьте недоступные блюда и фактические остатки."
                     : "На этот день докупать ничего не нужно.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            Text("Расчёт не учитывает фасовку, пищевые отходы и уже приготовленные блюда. Неизвестный остаток не считается полным запасом.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }

    private func stockLabel(_ item: PantryItem) -> String {
        let quantity = item.quantity.map { "\(item.quantityEstimated == true ? "≈" : "")\(format($0)) \(L10n.text(item.unit))" } ?? L10n.text("количество неизвестно")
        if let date = item.expiresOn { return L10n.format("%@ · до %@", quantity, date.formatted(date: .abbreviated, time: .omitted)) }
        return quantity
    }
    private func sourceLabel(_ need: ShoppingNeed) -> String {
        let sources = need.sourceSlots.prefix(2).compactMap { id -> String? in
            guard let slot = store.state.slots.first(where: { $0.id == id }) else { return nil }
            return "\(store.dateLabel(slot.day)), \(store.kinds[slot.kind].lowercased())"
        }
        return L10n.format("Для: %@%@", sources.joined(separator: "; "),
                           need.sourceSlots.count > 2 ? L10n.format(" и ещё %d", need.sourceSlots.count - 2) : "")
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

struct PantryEditor: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State var item: PantryItem
    @State private var quantityText = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date()
    @State private var validation = ""
    @State private var initialQuantityText = ""
    @State private var initialUnit = ""
    private var units: [String] { Array(Set(["г", "кг", "мл", "л", item.unit])).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                if let product = IngredientCatalog.product(item.name) {
                    Section {
                        NavigationLink { IngredientDetailView(name: item.name) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                IngredientPhoto(name: item.name).frame(height: 170).frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(product.description.localized).font(.system(size: 13)).foregroundStyle(Palette.muted)
                                Text("Фото, хранение, состав и ваша цена упаковки")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                            }
                        }
                    }
                }
                Section {
                    TextField("Название", text: $item.name)
                    TextField("Количество", text: $quantityText).keyboardType(.decimalPad)
                    Picker("Единица", selection: $item.unit) {
                        ForEach(units, id: \.self) { Text(L10n.text($0)).tag($0) }
                    }
                    TextField("Категория", text: $item.category)
                } header: { Text("Продукт") } footer: { Text("Оставьте количество пустым, если знаете только, что продукт есть дома.") }
                Section("Срок годности") {
                    Toggle("Указать дату", isOn: $hasExpiry).tint(Palette.sage)
                    if hasExpiry { DatePicker("Годен до", selection: $expiryDate, displayedComponents: .date) }
                }
                if !validation.isEmpty { Text(validation).foregroundStyle(Palette.terracotta) }
                if store.pantry.contains(where: { $0.id == item.id }) {
                    Button("Удалить продукт", role: .destructive) { store.removePantryItem(item.id); dismiss() }
                }
            }.scrollContentBackground(.hidden).background(Palette.canvas)
                .navigationTitle("Продукт дома")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Сохранить") { save() }.bold() }
                }
        }.onAppear {
            item = IngredientMeasures.normalized(item)
            quantityText = item.quantity.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            initialQuantityText = quantityText
            initialUnit = item.unit
            hasExpiry = item.expiresOn != nil
            expiryDate = item.expiresOn ?? .now
        }
    }
    private func save() {
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.name.isEmpty, !item.unit.isEmpty else { validation = "Укажите название и единицу."; return }
        let amount = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !amount.isEmpty {
            guard let value = QuantityInput.parse(amount) else { validation = "Введите неотрицательное количество."; return }
            item.quantity = value
        } else { item.quantity = nil }
        if amount != initialQuantityText || item.unit != initialUnit { item.quantityEstimated = nil }
        item.expiresOn = hasExpiry ? expiryDate : nil
        store.savePantryItem(item)
        dismiss()
    }
}

private struct PurchaseEntrySheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    let need: ShoppingNeed
    @State private var quantityText = ""
    @State private var validation = ""
    @State private var commandID = UUID().uuidString

    var body: some View {
        NavigationStack {
            Form {
                Section("Что купили") {
                    Text(L10n.text(need.name))
                    TextField(L10n.format("Фактическое количество, %@", L10n.text(need.unit)), text: $quantityText)
                        .keyboardType(.decimalPad)
                    Text("Запишите количество с упаковки или фактически купленное. Покупка создаст новую партию без унаследованного срока годности.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                if !validation.isEmpty { Text(validation).foregroundStyle(Palette.terracotta) }
            }
            .navigationTitle("Покупка")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Добавить") {
                        guard let amount = QuantityInput.parse(quantityText), amount > 0 else {
                            validation = "Укажите положительное количество."
                            return
                        }
                        store.addPurchasedToPantry(need, quantity: amount, commandID: commandID)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            quantityText = need.missing > 0.001
                ? need.missing.formatted(.number.precision(.fractionLength(0...1))) : ""
        }
    }
}

struct ReplanPreviewSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    let preview: ReplanPreview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(preview.explanation).font(.system(size: 14)).foregroundStyle(Palette.muted)
                    if !preview.reviewRecipeIDs.isEmpty {
                        Label("Для расчёта покупок укажите недостающие количества ингредиентов.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .background(Palette.peach.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    }
                    if preview.changes.isEmpty {
                        Text(preview.emptyMessage)
                            .font(.system(size: 15)).foregroundStyle(Palette.ink)
                            .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 17))
                        if let slotID = preview.outsideCourseSlotID,
                           let slot = store.state.slots.first(where: { $0.id == slotID }) {
                            Button(L10n.text("Показать блюда вне курса")) {
                                store.proposeNotToday(slot, includeOutsideCourses: true)
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(17)
                            .foregroundStyle(Palette.sage)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    ForEach(preview.changes) { change in
                        if let slot = store.state.slots.first(where: { $0.id == change.slotID }) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("\(store.dateLabel(slot.day)) · \(store.kinds[slot.kind])")
                                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.terracotta)
                                Text(change.previousID == change.nextID
                                     ? L10n.format("Блюдо остаётся: %@", L10n.text(store.allRecipes.first { $0.id == change.nextID }?.title ?? Recipe.unplanned.title))
                                     : "\(L10n.text(store.allRecipes.first { $0.id == change.previousID }?.title ?? Recipe.unplanned.title)) → \(L10n.text(store.allRecipes.first { $0.id == change.nextID }?.title ?? Recipe.unplanned.title))")
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                if change.extrasChanged {
                                    if let extras = change.nextExtraRecipeIDs, !extras.isEmpty {
                                        Text(L10n.format("Дополнение: %@", extras.compactMap { id in
                                            store.allRecipes.first(where: { $0.id == id }).map { L10n.text($0.title) }
                                        }.joined(separator: ", ")))
                                            .font(.system(size: 12)).foregroundStyle(Palette.sage)
                                    } else {
                                        Text(L10n.text("Дополнение убрано"))
                                            .font(.system(size: 12)).foregroundStyle(Palette.sage)
                                    }
                                }
                                if change.beverageChanged {
                                    let titles = (change.nextBeverageIDs ?? []).compactMap { id in
                                        CourseBeverages.all.first(where: { $0.id == id }).map { L10n.text($0.title) }
                                    }
                                    Text(L10n.format("Напитки: %@", titles.isEmpty ? L10n.text("не выбраны") : titles.joined(separator: ", ")))
                                        .font(.system(size: 12)).foregroundStyle(Palette.sage)
                                }
                                if preview.reviewRecipeIDs.contains(change.nextID) ||
                                   (change.nextExtraRecipeIDs ?? []).contains(where: { preview.reviewRecipeIDs.contains($0) }) {
                                    Text(L10n.text("Уточните количества ингредиентов"))
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.terracotta)
                                }
                            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                    }
                    if !preview.shoppingDelta.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("Как изменятся покупки")).font(.system(size: 19, weight: .semibold, design: .serif))
                            ForEach(Array(preview.shoppingDelta.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(size: 12)).foregroundStyle(Palette.ink)
                            }
                        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 17))
                    }
                    if !preview.changes.isEmpty {
                        Button(preview.changes.count == 1 && preview.changes[0].previousID != preview.changes[0].nextID &&
                               !preview.changes[0].extrasChanged && !preview.changes[0].beverageChanged
                               ? L10n.text("Применить замену") : L10n.format("Применить изменения: %d", preview.changes.count)) {
                            store.applyReplan(preview)
                        }.font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity)
                            .padding(17).foregroundStyle(.white).background(Palette.sage, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Button("Оставить меню") { store.replanPreview = nil; dismiss() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.sage)
                }.padding(21)
            }.background(Palette.canvas.ignoresSafeArea())
                .navigationTitle(preview.title).navigationBarTitleDisplayMode(.inline)
        }
    }
}
