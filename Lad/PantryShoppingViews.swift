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
            .sorted {
                if $0.category != $1.category { return $0.category.localizedStandardCompare($1.category) == .orderedAscending }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
    private var visibleSuggestions: [Ingredient] { Array(suggestions.prefix(visibleSuggestionCount)) }
    private var toBuy: [ShoppingNeed] { store.shoppingNeeds.filter { $0.missing > 0.001 || $0.amountUnknown } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageTitle(eyebrow: "ПРОДУКТЫ ДОМА И ДЛЯ МЕНЮ", title: "Наша кухня")
                Picker("Раздел", selection: $section) {
                    Text("Холодильник").tag(0)
                    Text("Покупки").tag(1)
                }.pickerStyle(.segmented)
                if section == 0 { pantryContent } else { shoppingContent }
            }.padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 35)
        }.background(Palette.canvas.ignoresSafeArea())
            .onChange(of: search) { _, _ in visibleSuggestionCount = 24 }
            .onChange(of: store.allRecipes.count) { _, _ in visibleSuggestionCount = 24 }
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
                    .accessibilityLabel("Добавить новый продукт")
            }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 15))
            if !filteredPantry.isEmpty {
                SectionHeading(title: "В запасе", trailing: L10n.format("%d ПОЗ.", filteredPantry.count))
                ForEach(filteredPantry) { item in
                    HStack(spacing: 11) {
                        Image(systemName: item.quantity == 0 ? "minus.circle" : "checkmark.circle.fill")
                            .foregroundStyle(item.quantity == 0 ? Palette.terracotta : Palette.sage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text(item.name)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
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
                Text(L10n.format("Ингредиенты из %d открытых и %d загруженных закрытых рецептов.%@",
                                 Recipe.all.count, store.privateRecipes.count,
                                 store.privateRecipes.isEmpty ? L10n.text(" Закрытый каталог пока не загружен.") : ""))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                SectionHeading(title: "Добавить из рецептов", trailing: L10n.format("%d ПОЗ.", suggestions.count))
                ForEach(Array(Set(visibleSuggestions.map(\.category))).sorted(), id: \.self) { category in
                    Text(L10n.text(category).uppercased())
                        .font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Palette.muted)
                    ForEach(visibleSuggestions.filter { $0.category == category }) { ingredient in
                        Button {
                            editorItem = PantryItem(name: ingredient.name, quantity: nil, unit: ingredient.unit, category: ingredient.category)
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle").foregroundStyle(Palette.sage)
                                Text(L10n.text(ingredient.name)).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(L10n.text(ingredient.unit)).foregroundStyle(Palette.muted)
                            }.font(.system(size: 14)).padding(13).background(.white, in: RoundedRectangle(cornerRadius: 13))
                        }.buttonStyle(.plain)
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

    private var shoppingContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "basket.fill").font(.system(size: 24)).foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("%d продуктов докупить", toBuy.count))
                        .font(.system(size: 17, weight: .semibold, design: .serif))
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
                SectionHeading(title: L10n.text(category))
                ForEach(toBuy.filter { $0.category == category }) { need in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top) {
                            Text(L10n.text(need.name)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(need.amountUnknown ? L10n.text("уточнить") : "\(format(need.missing)) \(L10n.text(need.unit))")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.sage)
                        }
                        if need.required > 0 {
                            Text(L10n.format("Известная потребность %@ · выделено из запасов %@ %@",
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
            if toBuy.isEmpty { Text("Нет рассчитанных покупок. Проверьте недоступные блюда и фактические остатки.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted) }
            Text("Расчёт не учитывает фасовку, пищевые отходы и уже приготовленные блюда. Неизвестный остаток не считается полным запасом.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }

    private func stockLabel(_ item: PantryItem) -> String {
        let quantity = item.quantity.map { "\(format($0)) \(L10n.text(item.unit))" } ?? L10n.text("количество неизвестно")
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
        let amount = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !amount.isEmpty {
            guard let value = QuantityInput.parse(amount) else { validation = "Введите неотрицательное количество."; return }
            item.quantity = value
        } else { item.quantity = nil }
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
                    Text(need.name)
                    TextField("Фактическое количество, \(need.unit)", text: $quantityText)
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
                        Label("В предложении есть рецепты с оценочными граммовками, порциями или непроверенными аллергенами. Перед готовкой проверьте состав и количества.",
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
                            Button(L10n.text("Показать проверенные блюда вне курса")) {
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
                                Text("\(L10n.text(store.allRecipes.first { $0.id == change.previousID }?.title ?? Recipe.unplanned.title)) → \(L10n.text(store.allRecipes.first { $0.id == change.nextID }?.title ?? Recipe.unplanned.title))")
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                if preview.reviewRecipeIDs.contains(change.nextID) {
                                    Text("Требует проверки перед готовкой")
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.terracotta)
                                }
                            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        }
                    }
                    if !preview.shoppingDelta.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Как изменятся покупки").font(.system(size: 19, weight: .semibold, design: .serif))
                            ForEach(Array(preview.shoppingDelta.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(size: 12)).foregroundStyle(Palette.ink)
                            }
                        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 17))
                    }
                    if !preview.changes.isEmpty {
                        Button(preview.changes.count == 1 ? L10n.text("Применить замену") : L10n.format("Применить изменения: %d", preview.changes.count)) {
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
