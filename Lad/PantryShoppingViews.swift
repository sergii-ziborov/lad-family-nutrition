import SwiftUI

struct ShoppingView: View {
    @EnvironmentObject var store: LadStore
    @State private var section = 0
    @State private var search = ""
    @State private var editorItem: PantryItem?
    @State private var manualName = ""
    @State private var showManual = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshot-shopping") {
            _section = State(initialValue: 1)
        }
        #endif
    }

    private var filteredPantry: [PantryItem] {
        store.pantry.filter { ProductNames.matches($0.name, query: search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var suggestions: [Ingredient] {
        PlanningCore.ingredientSuggestions(recipes: store.allRecipes, pantry: store.pantry, query: search)
    }
    private var toBuy: [ShoppingNeed] { store.shoppingNeeds.filter { $0.missing > 0.001 } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(eyebrow: "ПРОДУКТЫ ДОМА И ДЛЯ МЕНЮ", title: "Наша кухня")
                Picker("Раздел", selection: $section) {
                    Text("Холодильник").tag(0)
                    Text("Покупки").tag(1)
                }.pickerStyle(.segmented)
                if section == 0 { pantryContent } else { shoppingContent }
            }.padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 35)
        }.background(Palette.canvas.ignoresSafeArea())
            .sheet(item: $editorItem) { item in PantryEditor(item: item) }
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
                TextField("Поиск продукта", text: $search)
                    .textInputAutocapitalization(.sentences)
                Button {
                    editorItem = PantryItem(name: search, quantity: nil, unit: "г", category: "Другое")
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Palette.sage) }
                    .accessibilityLabel("Добавить новый продукт")
            }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 15))
            if !filteredPantry.isEmpty {
                SectionHeading(title: "В запасе", trailing: "\(filteredPantry.count) ПОЗ.")
                ForEach(filteredPantry) { item in
                    HStack(spacing: 11) {
                        Image(systemName: item.quantity == 0 ? "minus.circle" : "checkmark.circle.fill")
                            .foregroundStyle(item.quantity == 0 ? Palette.terracotta : Palette.sage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                            Text(stockLabel(item)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 4)
                        if item.quantity != 0 {
                            Button("Закончилось") { store.markOut(item) }
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.terracotta)
                        }
                        Button { editorItem = item } label: {
                            Image(systemName: "pencil").foregroundStyle(Palette.sage).frame(width: 28, height: 40)
                        }.accessibilityLabel("Изменить \(item.name)")
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
            }
            if !suggestions.isEmpty {
                Text("Ингредиенты из \(Recipe.all.count) открытых и \(store.privateRecipes.count) загруженных закрытых рецептов.\(store.privateRecipes.isEmpty ? " Закрытый каталог пока не загружен." : "")")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                SectionHeading(title: "Добавить из рецептов", trailing: "\(suggestions.count) ПОЗ.")
                ForEach(Array(Set(suggestions.map(\.category))).sorted(), id: \.self) { category in
                    Text(category.uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Palette.muted)
                    ForEach(suggestions.filter { $0.category == category }) { ingredient in
                        Button {
                            editorItem = PantryItem(name: ingredient.name, quantity: nil, unit: ingredient.unit, category: ingredient.category)
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle").foregroundStyle(Palette.sage)
                                Text(ingredient.name).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(ingredient.unit).foregroundStyle(Palette.muted)
                            }.font(.system(size: 14)).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 13))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if store.pantry.isEmpty { Text("Добавьте продукты — подбор блюд покажет, что уже можно приготовить и чего не хватает.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted) }
        }
    }

    private var shoppingContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "basket.fill").font(.system(size: 24)).foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(toBuy.count) продуктов докупить").font(.system(size: 17, weight: .semibold, design: .serif))
                    Text("Потребность на неделю минус известный запас дома")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { showManual = true } label: {
                    Image(systemName: "plus").foregroundStyle(.white).frame(width: 40, height: 40)
                        .background(Palette.sage, in: Circle())
                }.accessibilityLabel("Добавить покупку вручную")
            }.padding(17).background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
            if store.state.slots.contains(where: { store.recipe($0).isUnavailable }) {
                Label("Часть закрытых блюд не загружена. Расчёт покупок неполный.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Palette.terracotta)
            }
            if store.canUndoReplan {
                Button("Отменить последнее изменение меню") { store.undoReplan() }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
            }
            if !store.state.extraShopping.isEmpty {
                SectionHeading(title: "Добавлено вручную")
                ForEach(store.state.extraShopping, id: \.self) { name in
                    HStack {
                        Button {
                            if store.state.boughtNames.contains(name) { store.state.boughtNames.remove(name) }
                            else { store.state.boughtNames.insert(name) }
                        } label: {
                            Label(name, systemImage: store.state.boughtNames.contains(name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Palette.ink)
                        }.buttonStyle(.plain)
                        Spacer()
                        Button { store.state.extraShopping.removeAll { $0 == name } } label: {
                            Image(systemName: "trash").foregroundStyle(Palette.muted)
                        }.accessibilityLabel("Удалить \(name)")
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
                }
            }
            ForEach(Array(Set(toBuy.map(\.category))).sorted(), id: \.self) { category in
                SectionHeading(title: category)
                ForEach(toBuy.filter { $0.category == category }) { need in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top) {
                            Text(need.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(format(need.missing)) \(need.unit)")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.sage)
                        }
                        Text("Нужно \(format(need.required)) · дома \(format(need.available)) \(need.unit)")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        if need.amountUnknown {
                            Label("Есть запас без точного количества или в другой единице — проверьте перед покупкой", systemImage: "questionmark.circle")
                                .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                        }
                        Text(sourceLabel(need)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Button("Куплено → в холодильник") { store.addPurchasedToPantry(need) }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            if toBuy.isEmpty { Text("Для текущего меню всё есть дома — или количество запасов ещё не указано.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted) }
            Text("Расчёт не учитывает фасовку, пищевые отходы и уже приготовленные блюда. Неизвестный остаток не считается полным запасом.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }

    private func stockLabel(_ item: PantryItem) -> String {
        let quantity = item.quantity.map { "\(format($0)) \(item.unit)" } ?? "количество неизвестно"
        if let date = item.expiresOn { return "\(quantity) · до \(date.formatted(date: .abbreviated, time: .omitted))" }
        return quantity
    }
    private func sourceLabel(_ need: ShoppingNeed) -> String {
        let sources = need.sourceSlots.prefix(2).compactMap { id -> String? in
            guard let slot = store.state.slots.first(where: { $0.id == id }) else { return nil }
            return "\(store.dateLabel(slot.day)), \(store.kinds[slot.kind].lowercased())"
        }
        return "Для: \(sources.joined(separator: "; "))\(need.sourceSlots.count > 2 ? " и ещё \(need.sourceSlots.count - 2)" : "")"
    }
    private func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
}

private struct PantryEditor: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State var item: PantryItem
    @State private var quantityText = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date()
    @State private var validation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $item.name)
                    TextField("Количество", text: $quantityText).keyboardType(.decimalPad)
                    TextField("Единица (г, мл, шт.)", text: $item.unit)
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
            quantityText = item.quantity.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            hasExpiry = item.expiresOn != nil
            expiryDate = item.expiresOn ?? .now
        }
    }
    private func save() {
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.name.isEmpty, !item.unit.isEmpty else { validation = "Укажите название и единицу."; return }
        let amount = quantityText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if !amount.isEmpty {
            guard let value = Double(amount), value >= 0, value.isFinite else { validation = "Введите неотрицательное количество."; return }
            item.quantity = value
        } else { item.quantity = nil }
        item.expiresOn = hasExpiry ? expiryDate : nil
        store.savePantryItem(item)
        dismiss()
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
                    if preview.changes.isEmpty {
                        Text("Безопасной замены с меньшим числом недостающих продуктов не нашлось. Текущее меню остаётся, список покупок уже обновлён.")
                            .font(.system(size: 15)).foregroundStyle(Palette.ink)
                            .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 17))
                    }
                    ForEach(preview.changes) { change in
                        if let slot = store.state.slots.first(where: { $0.id == change.slotID }) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("\(store.dateLabel(slot.day)) · \(store.kinds[slot.kind])")
                                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.terracotta)
                                Text("\(store.allRecipes.first { $0.id == change.previousID }?.title ?? "Блюдо") → \(store.allRecipes.first { $0.id == change.nextID }?.title ?? "Блюдо")")
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                    }
                    if !preview.shoppingDelta.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Как изменятся покупки").font(.system(size: 19, weight: .semibold, design: .serif))
                            ForEach(preview.shoppingDelta.prefix(8), id: \.self) { line in
                                Text(line).font(.system(size: 12)).foregroundStyle(Palette.ink)
                            }
                            if preview.shoppingDelta.count > 8 {
                                Text("И ещё \(preview.shoppingDelta.count - 8) изменений")
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 17))
                    }
                    if !preview.changes.isEmpty {
                        Button("Применить \(preview.changes.count) изменений") {
                            store.applyReplan(preview)
                            dismiss()
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
