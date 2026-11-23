import SwiftUI

struct IngredientPhoto: View {
    let name: String
    var body: some View {
        Group {
            if let product = IngredientCatalog.product(name) {
                Image(product.image).resizable().scaledToFill()
            } else {
                ZStack { Palette.paleSage; Image(systemName: "leaf").foregroundStyle(Palette.sage) }
            }
        }.clipped().accessibilityLabel(L10n.text(name))
    }
}

struct IngredientCatalogueView: View {
    @EnvironmentObject var store: LadStore
    @State private var search = ""
    var products: [IngredientProfile] {
        IngredientCatalog.all.filter { ProductNames.matches($0.name, query: search) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField(L10n.text("Поиск ингредиента"), text: $search)
            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
            Text("Фото, хранение, состав и цены")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            LazyVStack(spacing: 12) {
                ForEach(products) { product in
                    NavigationLink { IngredientDetailView(name: product.name) } label: {
                        HStack(spacing: 13) {
                            IngredientPhoto(name: product.name).frame(width: 68, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(product.title).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                                if let price = FoodCost.price(for: product.name, prices: store.ingredientPrices) {
                                    Text("\(price.reference == nil ? "" : "≈ ")\(FoodCost.money(price.packagePrice, currency: price.currency)) · \(price.packageQuantity.formatted()) \(L10n.text(price.packageUnit))")
                                        .font(.system(size: 12)).foregroundStyle(Palette.sage)
                                } else {
                                    Text(L10n.text(product.category)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Palette.sage)
                        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct IngredientDetailView: View {
    @EnvironmentObject var store: LadStore
    let name: String
    @State private var showAllNutrients = false
    @State private var showPriceEditor = false
    @State private var stockEditor: PantryItem?
    private var product: IngredientProfile? { IngredientCatalog.product(name) }
    private var nutrients: [String: NutrientValue] { product?.nutrients ?? [:] }
    private var stock: [PantryItem] {
        store.pantry.filter { ProductNames.canonical($0.name) == ProductNames.canonical(name) }
    }
    private func priceHeading(_ price: IngredientPrice?) -> String {
        guard let method = price?.reference?.method else { return "Моя цена" }
        return method == "statistical-category-average" ? "Средняя цена" : "Цена на полке"
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                IngredientPhoto(name: name).frame(height: 265).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                Text(L10n.text(name)).font(.system(size: 30, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                if let product {
                    Text(product.description.localized).font(.system(size: 15)).foregroundStyle(Palette.muted)
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(product.storage.localized)
                            Link("Правила безопасного хранения", destination: IngredientCatalog.storageSource)
                            Link("FoodKeeper: рекомендации по продуктам", destination: IngredientCatalog.foodKeeperSource)
                        }.font(.system(size: 13)).padding(.top, 10)
                    } label: { Label("Как хранить", systemImage: "refrigerator") }
                        .tint(Palette.sage).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 17))
                    DisclosureGroup {
                        Text(product.cooking.localized).font(.system(size: 13)).padding(.top, 10)
                    } label: { Label("Как использовать", systemImage: "frying.pan") }
                        .tint(Palette.sage).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
                let allergens = IngredientAllergens.inferred(from: [Ingredient(name: name, amount: 100, unit: "г", category: product?.category ?? "Другое")])
                if !allergens.isEmpty {
                    Label(L10n.format("Аллергены: %@", allergens.map(L10n.text).joined(separator: ", ")), systemImage: "leaf")
                        .font(.system(size: 13)).foregroundStyle(Palette.terracotta)
                }
                stockSection
                priceSection
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Состав на 100 г")
                    if let energy = EnergyEstimator.energyDensity(for: name) {
                        Label(L10n.format("%d ккал на 100 г", Int(energy.rounded())), systemImage: "flame")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                    }
                    ForEach(NutrientGuide.visibleKeys(available: Set(nutrients.keys), expanded: showAllNutrients), id: \.self) { key in
                        if let value = nutrients[key] {
                            HStack {
                                Text(NutrientGuide.name(key))
                                Spacer()
                                Text("\(value.amount.formatted(.number.precision(.fractionLength(0...2)))) \(L10n.text(value.unit))")
                                    .foregroundStyle(Palette.sage)
                            }.font(.system(size: 14))
                            NutrientRoleLine(key: key)
                            Divider()
                        }
                    }
                    if NutrientGuide.displayOrder.filter({ nutrients[$0] != nil }).count > 4 {
                        Button(showAllNutrients ? "Свернуть нутриенты" : "Все нутриенты") { showAllNutrients.toggle() }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                    }
                    if let source = product?.compositionSource {
                        Text("Справочный состав съедобной части. У конкретной марки он может отличаться.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Link("Источник состава: USDA", destination: source).font(.system(size: 11))
                    } else {
                        Text("Состав зависит от рецептуры и марки — смотрите этикетку.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 18))
            }.padding(21).padding(.bottom, 30)
        }.background(Palette.canvas.ignoresSafeArea()).navigationTitle(L10n.text("Ингредиент"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPriceEditor) { IngredientPriceEditor(name: name) }
            .sheet(item: $stockEditor) { item in PantryEditor(item: item) }
    }
    private var stockSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Что есть дома")
            ForEach(stock) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.quantity.map {
                            "\(item.quantityEstimated == true ? "≈" : "")\($0.formatted(.number.precision(.fractionLength(0...1)))) \(L10n.text(item.unit))"
                        } ?? L10n.text("количество неизвестно"))
                        if let date = item.expiresOn {
                            Text(L10n.format("Годен до %@", date.formatted(date: .abbreviated, time: .omitted)))
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                    }.font(.system(size: 14))
                    Spacer()
                    Button { stockEditor = item } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                        .accessibilityLabel(L10n.format("Изменить %@", L10n.text(name)))
                }
            }
            if stock.isEmpty {
                Button {
                    stockEditor = IngredientMeasures.normalized(PantryItem(name: product?.name ?? name, quantity: nil,
                                                                          unit: "г", category: product?.category ?? "Другое"))
                } label: { Label("Добавить в холодильник", systemImage: "plus.circle") }
                    .font(.system(size: 14, weight: .semibold))
            }
        }.foregroundStyle(Palette.sage).padding(17)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: priceHeading(FoodCost.price(for: name, prices: store.ingredientPrices)))
            if let price = FoodCost.price(for: name, prices: store.ingredientPrices) {
                Text("\(price.reference == nil ? "" : "≈ ")\(FoodCost.money(price.packagePrice, currency: price.currency)) / \(price.packageQuantity.formatted()) \(L10n.text(price.packageUnit))")
                    .font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(Palette.sage)
                if let reference = price.reference {
                    Text(L10n.format("Данные за %@", reference.period))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    if reference.isStale() {
                        Text("Источник давно не обновлялся").font(.system(size: 12)).foregroundStyle(Palette.terracotta)
                    }
                    if let url = URL(string: reference.sourceURL) {
                        Link(reference.publisher, destination: url).font(.system(size: 12))
                    }
                    DisclosureGroup("Категория источника") {
                        Text(reference.sourceLabel).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        if let license = URL(string: reference.licenseURL) {
                            Link("Условия использования данных", destination: license).font(.system(size: 12))
                        }
                    }.font(.system(size: 12)).foregroundStyle(Palette.sage)
                }
            } else {
                Text("Укажите цену и размер упаковки — рассчитаем стоимость порции.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            Button { showPriceEditor = true } label: { Label("Цена упаковки", systemImage: "pencil") }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.sage)
        }.padding(17).background(Palette.paleSage.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct IngredientPriceEditor: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    let name: String
    @State private var price = ""
    @State private var quantity = ""
    @State private var unit = "г"
    @State private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var validation = ""
    private var currencies: [String] { Array(Set([currency, "ILS", "UAH", "USD", "EUR", "GBP", "RUB", "PLN", "CAD", "AUD"])).sorted() }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(L10n.text(name)).font(.headline) }
                Section("Цена упаковки") {
                    TextField(L10n.text("Стоимость всей упаковки"), text: $price).keyboardType(.decimalPad)
                    Picker("Валюта", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Размер упаковки") {
                    TextField(L10n.text("Количество в упаковке"), text: $quantity).keyboardType(.decimalPad)
                    Picker("Единица", selection: $unit) {
                        ForEach(["г", "кг", "мл", "л", "шт."], id: \.self) { Text(L10n.text($0)).tag($0) }
                    }
                    Text("Стоимость блюда — за использованное количество.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                if !validation.isEmpty { Text(L10n.text(validation)).foregroundStyle(Palette.terracotta) }
                if FoodCost.price(for: name, prices: store.personalIngredientPrices) != nil {
                    Button("Удалить цену", role: .destructive) { store.removeIngredientPrice(name); dismiss() }
                }
            }.navigationTitle(L10n.text("Моя цена"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.bold() }
                }
                .onAppear {
                    if let saved = FoodCost.price(for: name, prices: store.personalIngredientPrices) {
                        price = saved.packagePrice.formatted(.number.grouping(.never))
                        quantity = saved.packageQuantity.formatted(.number.grouping(.never))
                        unit = saved.packageUnit; currency = saved.currency
                    }
                }
        }
    }
    private func save() {
        guard let amount = QuantityInput.parse(price), amount.isFinite, amount >= 0,
              let size = QuantityInput.parse(quantity), size.isFinite, size > 0 else {
            validation = "Введите цену от нуля и количество больше нуля."; return
        }
        store.setIngredientPrice(IngredientPrice(productName: name, packagePrice: amount, packageQuantity: size,
                                                packageUnit: unit, currency: currency))
        dismiss()
    }
}

struct RecipeCostSummary: View {
    @EnvironmentObject var store: LadStore
    let recipe: Recipe
    let servings: Double
    /// People at the table when the cost is for a planned meal.
    var people: Int? = nil
    private var cost: RecipeCost { FoodCost.recipe(recipe, prices: store.ingredientPrices, servings: servings) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Стоимость ингредиентов", systemImage: "banknote").font(.system(size: 14, weight: .semibold))
            if cost.hasPrices {
                ForEach(cost.totals.keys.sorted(), id: \.self) { code in
                    let minimum = cost.totals[code] ?? 0
                    let maximum = cost.maximums[code] ?? minimum
                    Text((cost.approximate ? "≈ " : "") + FoodCost.money(minimum, currency: code) +
                         (maximum - minimum > 0.005 ? " – " + FoodCost.money(maximum, currency: code) : ""))
                        .font(.system(size: 21, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                }
                Text(people.map { L10n.format("На всех за столом: %d чел.", $0) } ?? L10n.text("За одну порцию рецепта"))
                    .font(.system(size: 12))
                if cost.totals.count > 1 { Text("Разные валюты показаны отдельно, без пересчёта курса.").font(.system(size: 11)) }
            }
            if !cost.missingNames.isEmpty {
                ForEach(cost.missingNames, id: \.self) { name in
                    NavigationLink { IngredientDetailView(name: name) } label: {
                        Text(L10n.format("%@ — нет цены", name))
                            .font(.system(size: 13)).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if !cost.hasPrices {
                Text("Добавить цены ингредиентов").font(.system(size: 12))
            }
            Picker("Страна цен", selection: Binding(
                get: { store.referencePriceCountrySource },
                set: { store.setReferencePriceCountry($0) }
            )) {
                ForEach(["system", "IL", "UA", "US", "personal"], id: \.self) { source in
                    Text(LadStore.priceCountrySourceTitle(source)).tag(source)
                }
            }.pickerStyle(.menu).font(.system(size: 13))
        }.foregroundStyle(Palette.sage).tint(Palette.sage).padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paleSage.opacity(0.55), in: RoundedRectangle(cornerRadius: 17))
    }
}
