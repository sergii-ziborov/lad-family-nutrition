import SwiftUI
import Charts

struct FamilyView: View {
    @EnvironmentObject var store: LadStore
    @State private var newName = ""
    @State private var showAdd = false
    @State private var selectedPerson: FamilyMember?
    @State private var supplementName = ""
    @State private var showSupplement = false
    @State private var showMealTimes = false
    @State private var showSettings = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(eyebrow: "КАЖДОМУ СВОЁ", title: "Семья")
                Button { showSettings = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape").font(.system(size: 21)).foregroundStyle(Palette.sage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Мои настройки").font(.system(size: 15, weight: .semibold))
                            Text("Язык, напоминания и цены").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.sage)
                    }.foregroundStyle(Palette.ink).padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                NavigationLink { FoodDiaryReport() } label: {
                    Label("Дневник, отчёты и CSV", systemImage: "chart.bar.doc.horizontal")
                        .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).foregroundStyle(Palette.sage)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Одна кухня — разные порции")
                        .font(.system(size: 16, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(L10n.format("Сегодня готовим для %d человек", store.state.members.count))
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        PersonDots(members: store.state.members, size: 22)
                    }
                }
                .foregroundStyle(Palette.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                SectionHeading(title: "Люди", trailing: L10n.format("%d ПРОФИЛЯ", store.state.members.count))
                NavigationLink { WeightHistoryView() } label: {
                    Label("Вес и динамика", systemImage: "chart.xyaxis.line")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.sage)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                ForEach(Array(store.state.members.enumerated()), id: \.element.id) { index, member in
                    Button { selectedPerson = member } label: {
                        HStack(spacing: 14) {
                            Text(member.initials).font(.system(size: 22, weight: .semibold, design: .serif))
                                .frame(width: 50, height: 50)
                                .background([Palette.paleSage, Palette.peach, Color(red: 0.87, green: 0.84, blue: 0.73)][index % 3], in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(member.name).font(.system(size: 18, weight: .semibold, design: .serif))
                                Text([member.ageLabel, L10n.text(member.goal)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                if let height = member.heightCm, let weight = member.weightKg {
                                    Text(L10n.format("Рост %.0f см · вес %.1f кг", height, weight))
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                Text(portionCaption(member))
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                if !member.allergies.isEmpty {
                                    Text(L10n.format("Исключить: %@", member.allergies.map(L10n.text).joined(separator: ", ")))
                                        .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.muted)
                        }.padding(12).foregroundStyle(Palette.ink).background(.white, in: RoundedRectangle(cornerRadius: 19))
                    }.buttonStyle(.plain)
                }
                Button { showAdd = true } label: {
                    Label("Добавить человека", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.sage)
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: "iphone.gen3").foregroundStyle(Palette.sage)
                        Text("Ваши данные").font(.system(size: 16, weight: .semibold))
                    }
                    Text(L10n.text(ReleasePolicy.isStoreRelease ? "Меню и дневник сохраняются на этом iPhone." : "Данные на iPhone. Синхронизацию можно включить в настройках."))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text(L10n.format("Локально сохранено прошлых недель: %d", store.archivedWeekCount))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if let warning = store.storageWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                    }
                    Text(L10n.text(store.familyCloudStatus)).font(.system(size: 11)).foregroundStyle(Palette.sage)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 19))
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Время приёмов в меню")
                    Text(L10n.format("Завтрак до %@ · обед до %@ · ужин до %@",
                                     store.mealCutoffText(for: 0), store.mealCutoffText(for: 1),
                                     store.mealCutoffText(for: 2)))
                        .font(.system(size: 12)).foregroundStyle(Palette.ink)
                    Button("Изменить время") { showMealTimes = true }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 19))
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: L10n.format("Сегодня у %@", store.currentMember.name))
                    let dayKinds = store.mealKinds(on: store.currentDay, forMember: store.currentMember.id)
                    let eaten = dayKinds.filter { store.isEaten(store.slot(store.currentDay, $0)) }.count
                    let planned = dayKinds.filter {
                        let slot = store.slot(store.currentDay, $0)
                        return slot.memberIDs.contains(store.currentMember.id) && !store.isSkipped(slot)
                    }.count
                    Text(L10n.format("Отмечено приёмов пищи: %d из %d", eaten, planned))
                        .font(.system(size: 14)).foregroundStyle(Palette.ink)
                    ProgressView(value: Double(eaten), total: Double(max(1, planned))).tint(Palette.sage)
                }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 19))
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Мои добавки")
                    Text("Личный журнал приёма добавок.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    ForEach(store.state.supplementsByMember[store.currentMember.id] ?? [], id: \.self) { name in
                        Button {
                            let key = "\(store.currentMember.id)-\(name)-\(store.supplementStamp)"
                            if store.state.takenSupplements.contains(key) { store.state.takenSupplements.remove(key) }
                            else { store.state.takenSupplements.insert(key) }
                        } label: {
                            HStack {
                                Image(systemName: store.state.takenSupplements.contains("\(store.currentMember.id)-\(name)-\(store.supplementStamp)") ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22)).foregroundStyle(Palette.sage)
                                Text(name).foregroundStyle(Palette.ink)
                                Spacer()
                                Text("Сегодня").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
                        }
                    }
                    Button { showSupplement = true } label: {
                        Label("Записать добавку", systemImage: "plus.circle.fill").font(.system(size: 14, weight: .semibold))
                    }
                }
            }.padding(.horizontal, 21).padding(.top, 20).padding(.bottom, 35)
        }.background(Palette.canvas.ignoresSafeArea())
            .sheet(item: $selectedPerson) { member in MemberEditor(member: member) }
            .sheet(isPresented: $showMealTimes) { MealTimesSheet() }
            .sheet(isPresented: $showSettings) { LanguageSettingsSheet() }
            .alert("Новый профиль", isPresented: $showAdd) {
                TextField("Имя", text: $newName)
                Button("Добавить") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { store.addMember(trimmed) }
                    newName = ""
                }
                Button("Отмена", role: .cancel) { newName = "" }
            } message: { Text("Его участие в меню можно отметить отдельно для каждого приёма пищи.") }
            .alert("Добавка", isPresented: $showSupplement) {
                TextField("Название и дозировка", text: $supplementName)
                Button("Записать") {
                    let trimmed = supplementName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !(store.state.supplementsByMember[store.currentMember.id] ?? []).contains(trimmed) {
                        store.state.supplementsByMember[store.currentMember.id, default: []].append(trimmed)
                    }
                    supplementName = ""
                }
                Button("Отмена", role: .cancel) { supplementName = "" }
            } message: { Text("Прототип не проверяет состав, дозы и взаимодействия.") }
    }

    private func portionCaption(_ member: FamilyMember) -> String {
        if member.automaticPortions == true, PersonalPortions.estimatedEnergy(member) != nil {
            return L10n.text("Порции по профилю и меню дня")
        }
        if let energy = PersonalPortions.profileDailyEnergy(member) {
            return L10n.format("Порции по профилю: ~%d ккал в день", Int(energy.rounded()))
        }
        if PersonalPortions.usesCalculatedShare(member) {
            return L10n.format("Порция по профилю: %d%% базовой", PersonalPortions.percent(PersonalPortions.profileShare(member)))
        }
        return L10n.format("Ручная порция: %d%% базовой", PersonalPortions.percent(member.portion))
    }
}

struct LanguageSettingsSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(L10n.languageKey) private var language = "system"
    @AppStorage(PersonalSettings.notifications) private var notifications = false
    @AppStorage(PersonalSettings.iCloud) private var cloud = false
    @State private var notificationBusy = false
    @ObservedObject private var advertising = AdvertisingService.shared
    @ObservedObject private var purchases = AppPurchases.shared
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Цены продуктов", selection: Binding(
                        get: { store.referencePriceCountrySource },
                        set: { store.setReferencePriceCountry($0) }
                    )) {
                        ForEach(["system", "IL", "UA", "US", "personal"], id: \.self) { source in
                            Text(LadStore.priceCountrySourceTitle(source)).tag(source)
                        }
                    }
                    if store.referencePriceCountrySource == "system",
                       let country = ReferencePriceCountry(rawValue: store.referencePriceCountry) {
                        Text(country.title).font(.caption).foregroundStyle(Palette.muted)
                    }
                    if !store.referencePriceCountry.isEmpty {
                        Button("Обновить цены") { Task { await store.refreshReferencePrices() } }
                            .disabled(store.isUpdatingReferencePrices)
                        if store.isUpdatingReferencePrices { ProgressView() }
                        if let status = store.referencePriceStatus { Text(status).font(.caption).foregroundStyle(Palette.muted) }
                        if let period = countryPricePeriod {
                            Text(L10n.format("Данные за %@", period)).font(.caption).foregroundStyle(Palette.muted)
                        }
                        ForEach(countryPriceRecords, id: \.reference.seriesID) { record in
                            countryPriceRow(record)
                        }
                        if !shelfPriceRows.isEmpty {
                            Text("Цена на полке").font(.caption).foregroundStyle(Palette.muted)
                            ForEach(shelfPriceRows, id: \.reference!.seriesID) { price in
                                shelfPriceRow(price)
                            }
                        }
                    }
                } footer: {
                    Text("Средние по стране и упаковки из файлов цен сетей. Ваши цены имеют приоритет; марка и сорт могут отличаться.")
                }
                Section {
                    Picker("Язык приложения", selection: $language) {
                        Text("Как на телефоне").tag("system")
                        Text("English").tag("en")
                        Text("Русский").tag("ru")
                        Text("Українська").tag("uk")
                    }.pickerStyle(.inline)
                }
                Section {
                    Toggle("Напоминания о дневнике", isOn: Binding(get: { notifications }, set: { enabled in
                        notificationBusy = true
                        Task { await store.setNotifications(enabled); notificationBusy = false }
                    })).disabled(notificationBusy)
                    Text(L10n.text(store.notificationStatus)).font(.caption).foregroundStyle(Palette.muted)
                    if notifications || store.notificationStatus == "Разрешите уведомления в настройках iPhone" {
                        Button("Открыть настройки iPhone") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                } header: { Text("Уведомления") } footer: {
                    Text("Напомним заполнить дневник. Блюда и калории скрыты на экране блокировки.")
                }
                Section {
                    if ReleasePolicy.isStoreRelease {
                        Label("Данные на этом iPhone", systemImage: "iphone")
                            .foregroundStyle(Palette.ink)
                    } else {
                    Toggle("Синхронизация iCloud", isOn: Binding(get: { cloud }, set: { enabled in
                        cloud = enabled
                        Task { await store.setPersonalCloud(enabled) }
                    })).disabled(!PersonalSettings.cloudAvailable)
                    Text(L10n.text(store.cloudSyncStatus)).font(.caption).foregroundStyle(Palette.muted)
                    if let date = store.cloudLastSync {
                        Text(L10n.format("Последняя синхронизация: %@", date.formatted(date: .abbreviated, time: .shortened))).font(.caption)
                    }
                    if cloud && PersonalSettings.cloudAvailable {
                        Button("Синхронизировать сейчас") { Task { await store.syncPersonalCloud() } }.disabled(store.isCloudSyncing)
                    }
                    }
                } footer: {
                    Text(L10n.text(ReleasePolicy.isStoreRelease
                         ? "Экспортируйте записи через «Поделиться»."
                         : "Меню, продукты и дневник — в вашем iCloud. Вес — на iPhone. Выключение сохраняет данные."))
                }
                Section {
                    NavigationLink { FoodDiaryReport() } label: { Label("Дневник, отчёты и CSV", systemImage: "square.and.arrow.up") }
                    NavigationLink { WeightHistoryView() } label: { Label("Вес и динамика", systemImage: "chart.xyaxis.line") }
                }
                Section("О приложении") {
                    ForEach(LegalPage.allCases) { page in
                        NavigationLink { LegalDocumentView(page: page) } label: { Text(page.title) }
                    }
                }
                Section {
                    // The whole course ships in the app and ads are off, so the
                    // purchase stays hidden until the store actually sells it.
                    if purchases.commerceReady || purchases.hasFullCourse {
                        Button(L10n.text("Восстановить покупки")) { Task { await purchases.restore() } }
                            .disabled(purchases.isBusy)
                        CompleteCourseOffer()
                    }
                    if advertising.privacyOptionsRequired {
                        Button("Настройки рекламной конфиденциальности") { Task { await advertising.privacyOptions() } }
                    }
                }
            }
            .navigationTitle("Мои настройки")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }.task {
            await store.refreshMealNotifications()
            if !PersonalSettings.cloudAvailable { store.cloudSyncStatus = "iCloud недоступен в этой сборке" }
        }
        .onChange(of: language) { _, _ in store.personalPreferenceChanged() }
    }

    private var countryPriceRecords: [ReferencePriceRecord] {
        store.referencePriceCatalog.records(country: store.referencePriceCountry)
            .sorted { L10n.text($0.productName).localizedStandardCompare(L10n.text($1.productName)) == .orderedAscending }
    }

    private var countryPricePeriod: String? {
        Set(countryPriceRecords.map(\.reference.period)).sorted().last
    }

    private var shelfPriceRows: [IngredientPrice] {
        store.shelfPrices
            .sorted { L10n.text($0.productName).localizedStandardCompare(L10n.text($1.productName)) == .orderedAscending }
    }

    @ViewBuilder private func countryPriceRow(_ record: ReferencePriceRecord) -> some View {
        let shown = FoodCost.price(for: record.productName, prices: store.ingredientPrices) ?? record.price
        let line = (shown.reference == nil ? "" : "≈ ")
            + FoodCost.money(shown.packagePrice, currency: shown.currency)
            + " · \(shown.packageQuantity.formatted()) \(L10n.text(shown.packageUnit))"
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(record.productName)).foregroundStyle(Palette.ink)
            Text(line).font(.caption).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        if IngredientCatalog.product(record.productName) != nil {
            NavigationLink { IngredientDetailView(name: record.productName) } label: { label }
        } else {
            label
        }
    }

    @ViewBuilder private func shelfPriceRow(_ price: IngredientPrice) -> some View {
        let shown = FoodCost.price(for: price.productName, prices: store.ingredientPrices) ?? price
        let line = (shown.reference == nil ? "" : "≈ ")
            + FoodCost.money(shown.packagePrice, currency: shown.currency)
            + " · \(shown.packageQuantity.formatted()) \(L10n.text(shown.packageUnit))"
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(price.productName)).foregroundStyle(Palette.ink)
            Text(line).font(.caption).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            if let pack = shown.reference?.sourceLabel, !pack.isEmpty {
                Text(pack).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        if IngredientCatalog.product(price.productName) != nil {
            NavigationLink { IngredientDetailView(name: price.productName) } label: { label }
        } else {
            label
        }
    }
}

struct LegalDocumentView: View {
    let page: LegalPage
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(page.text(language: L10n.languageCode).components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                    if paragraph.hasPrefix("#") {
                        Text(paragraph.trimmingCharacters(in: CharacterSet(charactersIn: "# \n")))
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                    } else {
                        Text(.init(paragraph)).font(.system(size: 14)).textSelection(.enabled)
                    }
                }
                if page == .terms { Link("Apple Standard EULA", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) }
            }.foregroundStyle(Palette.ink).padding(21)
        }.background(Palette.canvas).navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct WeightHistoryView: View {
    @EnvironmentObject var store: LadStore
    @State private var personID = ""
    @State private var days = 90
    @State private var editing: WeightEntry?
    @State private var deletion: WeightEntry?
    @State private var export: DiaryExport?
    @State private var exportFailed = false
    private var member: FamilyMember { store.state.members.first { $0.id == personID } ?? store.currentMember }
    private var all: [WeightEntry] { WeightJournal.entries(store.state, memberID: member.id) }
    private var points: [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        return days == 0 ? all : all.filter { $0.measuredAt >= cutoff }
    }
    private var yDomain: ClosedRange<Double> {
        let minimum = points.map(\.kilograms).min() ?? 0
        let maximum = points.map(\.kilograms).max() ?? 1
        let padding = max(1, (maximum - minimum) * 0.15)
        return max(0, minimum - padding)...(maximum + padding)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Человек", selection: $personID) {
                    ForEach(store.state.members) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu)
                Picker("Период", selection: $days) {
                    Text("7 дней").tag(7); Text("30 дней").tag(30); Text("90 дней").tag(90); Text("Всё время").tag(0)
                }.pickerStyle(.segmented)
                if let last = all.last {
                    Text(L10n.format("%.1f кг", last.kilograms)).font(.system(size: 36, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    Text(last.measuredAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: L10n.languageCode)))).font(.caption).foregroundStyle(Palette.muted)
                }
                if points.isEmpty {
                    Text(L10n.text(all.isEmpty ? "Пока нет измерений. Запишите вес — история появится на графике." : "За этот период нет измерений."))
                        .font(.system(size: 15)).foregroundStyle(Palette.muted)
                    if all.isEmpty, let weight = member.weightKg {
                        Text(L10n.format("В профиле: %.1f кг. Дата этого измерения неизвестна; в историю оно не добавлено.", weight))
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                } else {
                    Chart(points) { point in
                        LineMark(x: .value(L10n.text("Дата"), point.measuredAt), y: .value(L10n.text("Вес, кг"), point.kilograms))
                            .foregroundStyle(Palette.sage).interpolationMethod(.linear)
                        PointMark(x: .value(L10n.text("Дата"), point.measuredAt), y: .value(L10n.text("Вес, кг"), point.kilograms))
                            .foregroundStyle(Palette.sage).symbolSize(40)
                    }.chartYScale(domain: yDomain).chartYAxis { AxisMarks(position: .leading) }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) {
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: L10n.languageCode)), anchor: .topTrailing)
                            }
                        }
                        .frame(height: 235).accessibilityLabel(L10n.text("Измерения веса"))
                    if let first = points.first, let last = points.last, points.count > 1 {
                        Text(L10n.format("Изменение за период: %+.1f кг", last.kilograms - first.kilograms))
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                    }
                }
                Text("Последний вес используется для расчёта порций. История хранится на этом iPhone.")
                    .font(.caption).foregroundStyle(Palette.muted)
                Button {
                    editing = WeightEntry(memberID: member.id, measuredAt: .now, kilograms: member.weightKg ?? all.last?.kilograms ?? 0)
                } label: { Label("Записать вес", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(15) }
                    .buttonStyle(.plain).foregroundStyle(.white).background(Palette.sage, in: RoundedRectangle(cornerRadius: 15))
                if !all.isEmpty {
                    Button {
                        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lad-export-\(UUID().uuidString)", isDirectory: true)
                        do {
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
                            let url = directory.appendingPathComponent("lad-weight.csv")
                            try Data(WeightJournal.csv(all, name: member.name).utf8).write(to: url, options: [.atomic, .completeFileProtection])
                            export = DiaryExport(url: url, prompt: nil)
                        } catch { exportFailed = true }
                    } label: { Label("Экспорт веса в CSV", systemImage: "square.and.arrow.up") }
                        .foregroundStyle(Palette.sage)
                }
                ForEach(points.reversed()) { point in
                    HStack {
                        Button { editing = point } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L10n.format("%.1f кг", point.kilograms)).font(.system(size: 17, weight: .semibold))
                                Text(point.measuredAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: L10n.languageCode)))).font(.caption)
                                if !point.note.isEmpty { Text(point.note).font(.caption).foregroundStyle(Palette.muted) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { deletion = point } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                            .foregroundStyle(Palette.terracotta).accessibilityLabel(L10n.text("Удалить измерение"))
                    }.padding(15).foregroundStyle(Palette.ink).background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
            }.padding(21)
        }.background(Palette.canvas).navigationTitle(L10n.text("Вес и динамика")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = WeightEntry(memberID: member.id, measuredAt: .now, kilograms: member.weightKg ?? all.last?.kilograms ?? 0)
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L10n.text("Записать вес"))
                }
            }
            .onAppear { if personID.isEmpty { personID = store.currentMember.id } }
            .sheet(item: $editing) { WeightEntryEditor(entry: $0) }
            .sheet(item: $export) { DiaryShareSheet(export: $0) }
            .alert("Не удалось экспортировать данные", isPresented: $exportFailed) { Button("Готово", role: .cancel) {} }
            .confirmationDialog("Удалить измерение?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let deletion { store.removeWeightEntry(deletion) }; deletion = nil }
                Button("Отмена", role: .cancel) { deletion = nil }
            } message: { Text("Запись исчезнет из истории. Текущий вес в профиле не изменится.") }
    }
}

struct WeightEntryEditor: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: WeightEntry
    @State private var weight = ""
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.text("Вес, кг"), text: $weight).keyboardType(.decimalPad)
                    DatePicker("Дата измерения", selection: $entry.measuredAt, in: ...Date.now)
                    TextField(L10n.text("Заметка"), text: $entry.note, axis: .vertical).lineLimit(2...5)
                    if !error.isEmpty { Text(L10n.text(error)).foregroundStyle(Palette.terracotta) }
                }
            }.navigationTitle(L10n.text("Записать вес"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") {
                            guard let value = QuantityInput.parse(weight) else { error = "Проверьте вес: от 10 до 500 кг."; return }
                            entry.kilograms = value
                            if store.saveWeightEntry(entry) { dismiss() } else { error = "Проверьте вес, дату и заметку (до 1000 символов)." }
                        }
                    }
                }.onAppear { weight = entry.kilograms > 0 ? entry.kilograms.formatted(.number.grouping(.never)) : "" }
        }
    }
}

struct MealTimesSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State private var draftSchedule: MealSchedule?
    @State private var warning = ""
    private var schedule: MealSchedule { draftSchedule ?? store.mealSchedule }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Завтрак до", selection: timeBinding(for: 0), displayedComponents: .hourAndMinute)
                    DatePicker("Обед до", selection: timeBinding(for: 1), displayedComponents: .hourAndMinute)
                    DatePicker("Ужин до", selection: timeBinding(for: 2), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Ваши часы для меню")
                } footer: {
                    Text("Местное время. Отметить съеденное можно и позднее.")
                    Text("Перекус — за час до обеда, если включён.")
                }
                if !warning.isEmpty { Text(warning).foregroundStyle(Palette.terracotta) }
            }
            .navigationTitle("Время приёмов пищи")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        guard schedule.isValid else {
                            warning = "Время должно идти по порядку: завтрак, обед, ужин."
                            return
                        }
                        store.updateMealSchedule(schedule)
                        dismiss()
                    }.bold()
                }
            }
        }
    }
    private func timeBinding(for kind: Int) -> Binding<Date> {
        Binding(get: { date(schedule.endMinute(for: kind)) }, set: { value in
            var updated = schedule
            switch kind {
            case 0: updated.breakfastEnds = MealTiming.minuteOfDay(value)
            case 1: updated.lunchEnds = MealTiming.minuteOfDay(value)
            default: updated.dinnerEnds = MealTiming.minuteOfDay(value)
            }
            draftSchedule = updated
            warning = ""
        })
    }
    private func date(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60,
                              second: 0, of: store.now) ??
            Calendar.current.startOfDay(for: store.now).addingTimeInterval(TimeInterval(minute * 60))
    }
}

struct MemberEditor: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State var member: FamilyMember
    @State private var ageText = ""
    @State private var energyText = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var allergenQuery = ""
    @State private var showAllergens = false
    @State private var showVitamins = false
    @State private var showCalculation = false
    @State private var showEnergyGoal = false
    private let goals = ["Баланс", "Поддержание", "Снижение", "Набор", "Без цели по весу"]
    private let vitaminOptions: [(String, String)] = [
        ("vitamin_a", "Витамин A"), ("vitamin_c", "Витамин C"),
        ("vitamin_d", "Витамин D"), ("vitamin_e", "Витамин E"),
        ("vitamin_k", "Витамин K"), ("vitamin_b1", "Витамин B1"),
        ("vitamin_b2", "Витамин B2"), ("vitamin_b3", "Витамин B3"),
        ("vitamin_b6", "Витамин B6"), ("vitamin_b12", "Витамин B12")
    ]
    private let allergens = ["Молоко", "Яйцо", "Рыба", "Злаки с глютеном", "Пшеница", "Рожь", "Ячмень", "Овёс",
                             "Ракообразные", "Арахис", "Соя", "Орехи", "Сельдерей", "Горчица",
                             "Кунжут", "Диоксид серы и сульфиты", "Люпин", "Моллюски"]
    private var visibleAllergens: [String] {
        guard !allergenQuery.isEmpty else { return allergens }
        return allergens.filter { $0.localizedStandardContains(allergenQuery) ||
            L10n.text($0).localizedStandardContains(allergenQuery) }
    }
    private func quantity(_ text: String, range: ClosedRange<Double>) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), range.contains(value) else { return nil }
        return value
    }
    private var measurementIssue: String? {
        if !ageText.isEmpty && (Int(ageText).map { (0...120).contains($0) } != true) {
            return L10n.text("Проверьте возраст: от 0 до 120 полных лет.")
        }
        if !heightText.isEmpty && quantity(heightText, range: 50...250) == nil {
            return L10n.text("Проверьте рост: от 50 до 250 см.")
        }
        if !weightText.isEmpty && quantity(weightText, range: 10...500) == nil {
            return L10n.text("Проверьте вес: от 10 до 500 кг.")
        }
        if (Int(ageText) ?? 0) >= 18, !energyText.isEmpty,
           Int(energyText).map({ (1000...5000).contains($0) }) != true {
            return L10n.text("Проверьте ориентир: от 1000 до 5000 ккал/день.")
        }
        return nil
    }
    private var previewMember: FamilyMember {
        var value = member
        value.ageYears = Int(ageText)
        value.heightCm = quantity(heightText, range: 50...250)
        value.weightKg = quantity(weightText, range: 10...500)
        value.dailyEnergyTarget = Int(energyText)
        return value
    }
    private func labeledInput(_ label: String, text: Binding<String>, decimal: Bool = false) -> some View {
        HStack {
            Text(L10n.text(label)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            TextField(L10n.text("Не указано"), text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing).frame(width: 125)
                .accessibilityLabel(L10n.text(label))
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Личные настройки") {
                    TextField(L10n.text("Имя"), text: $member.name)
                    labeledInput("Возраст, полных лет", text: $ageText)
                    labeledInput("Рост, см", text: $heightText, decimal: true)
                    labeledInput("Вес, кг", text: $weightText, decimal: true)
                }
                Section {
                    DisclosureGroup(isExpanded: $showAllergens) {
                        TextField(L10n.text("Поиск аллергена"), text: $allergenQuery)
                            .textInputAutocapitalization(.never)
                        ForEach(visibleAllergens, id: \.self) { allergen in
                            Toggle(L10n.text(allergen), isOn: Binding(
                                get: { member.allergies.contains(allergen) },
                                set: { enabled in
                                    if enabled && !member.allergies.contains(allergen) { member.allergies.append(allergen) }
                                    else if !enabled { member.allergies.removeAll { $0 == allergen } }
                                }
                            )).tint(Palette.sage)
                        }
                        Text("Ограничения учитываются по составу блюда. Для конкретной марки продукта учитывайте аллергены на упаковке.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    } label: { Label("Исключить аллергены", systemImage: "leaf") }
                    Text(member.allergies.isEmpty ? L10n.text("Не выбраны") : member.allergies.map(L10n.text).joined(separator: ", "))
                        .font(.system(size: 12)).foregroundStyle(member.allergies.isEmpty ? Palette.muted : Palette.terracotta)
                }
                portionSettings
                if (Int(ageText) ?? 0) >= 18 {
                    Section {
                        DisclosureGroup("Ориентир питания", isExpanded: $showEnergyGoal) {
                            Picker("Ориентир", selection: $member.goal) {
                                ForEach(goals, id: \.self) { Text(L10n.text($0)) }
                            }
                            labeledInput("Ручной ориентир, ккал/день", text: $energyText)
                            Text("Ручной ориентир заменяет расчёт. Снижение — 85% тарелки, набор — 115%. Это размер порции в семье, не назначение диеты.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                    }
                    Section {
                        DisclosureGroup("Учитывать витамины при подборе", isExpanded: $showVitamins) {
                        ForEach(vitaminOptions.indices, id: \.self) { index in
                            let (key, label) = vitaminOptions[index]
                            Toggle(L10n.text(label), isOn: Binding(
                                get: { member.preferredVitaminKeys?.contains(key) == true },
                                set: { enabled in
                                    var selected = member.preferredVitaminKeys ?? []
                                    if enabled { selected.insert(key) } else { selected.remove(key) }
                                    member.preferredVitaminKeys = selected
                                }
                            )).tint(Palette.sage)
                            NutrientRoleLine(key: key)
                        }
                        Text("Приоритет при выборе блюд.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        let selected = vitaminOptions.filter { member.preferredVitaminKeys?.contains($0.0) == true }
                        Text(selected.isEmpty ? L10n.text("Не выбраны") : selected.map { L10n.text($0.1) }.joined(separator: ", "))
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                }
                if let measurementIssue {
                    Text(measurementIssue).font(.system(size: 12)).foregroundStyle(Palette.terracotta)
                }
            }.scrollContentBackground(.hidden).background(Palette.canvas)
                .navigationTitle(member.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Сохранить") {
                            member.ageYears = Int(ageText).flatMap { (0...120).contains($0) ? $0 : nil }
                            member.dailyEnergyTarget = (member.ageYears ?? 0) >= 18 ? Int(energyText).flatMap { (1000...5000).contains($0) ? $0 : nil } : nil
                            if (member.ageYears ?? 0) < 18 { member.preferredVitaminKeys = nil }
                            member.heightCm = quantity(heightText, range: 50...250)
                            member.weightKg = quantity(weightText, range: 10...500)
                            if (member.ageYears ?? 0) < 19, member.automaticPortions == true { member.automaticPortions = nil }
                            if let age = member.ageYears, age < 18 { member.goal = "Без цели по весу" }
                            store.updateMember(member)
                            dismiss()
                        }.bold().disabled(measurementIssue != nil)
                    }
                }
        }.onAppear {
            ageText = member.ageYears.map(String.init) ?? ""
            energyText = member.dailyEnergyTarget.map(String.init) ?? ""
            heightText = member.heightCm.map { String($0) } ?? ""
            weightText = member.weightKg.map { String($0) } ?? ""
        }.onChange(of: ageText) { _, value in
            if let age = Int(value), age < 18 { member.goal = "Без цели по весу" }
        }
    }
    private var portionSettings: some View {
        let preview = previewMember
        let manual = PersonalPortions.isExplicitManual(preview)
        let age = Int(ageText) ?? 0
        return Section {
            Toggle("Задать вручную", isOn: Binding(
                get: { member.automaticPortions == false },
                set: { member.automaticPortions = $0 ? false : nil }
            )).tint(Palette.sage)
            if manual {
                HStack {
                    Text("Размер порции")
                    Spacer()
                    Text(L10n.format("%d%% базовой", PersonalPortions.percent(member.portion))).foregroundStyle(Palette.sage)
                }
                Slider(value: $member.portion, in: 0.5...1.6, step: 0.05)
            } else {
                if let energy = PersonalPortions.profileDailyEnergy(preview) {
                    Text(L10n.format("Порции по профилю: ~%d ккал в день", Int(energy.rounded())))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                    Text("Размер тарелки подстраивается под калорийность меню каждого дня.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                } else if PersonalPortions.usesCalculatedShare(preview) {
                    Text(L10n.format("Порция по профилю: %d%% базовой", PersonalPortions.percent(PersonalPortions.profileShare(preview))))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                } else {
                    Text("Укажите возраст — порция посчитается по нему.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Text("Порция по возрасту и цели. Рост, вес, пол и активность уточняют её, когда заполнены.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                if age > 0 && age < 2 {
                    Text("До 2 лет размер остаётся заданным.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                if age >= 3 {
                    Picker("Пол для расчёта", selection: $member.energySex) {
                        Text("Не указано").tag(nil as EnergySex?)
                        ForEach(EnergySex.allCases, id: \.self) { Text(L10n.text($0.label)).tag(Optional($0)) }
                    }
                    Picker("Активность", selection: $member.energyActivity) {
                        Text("Не указано").tag(nil as EnergyActivity?)
                        ForEach(EnergyActivity.allCases, id: \.self) { Text(L10n.text($0.label)).tag(Optional($0)) }
                    }
                }
                if age >= 19 {
                    Picker("Тип расчёта", selection: $member.energyContext) {
                        Text("Не указано").tag(nil as EnergyContext?)
                        ForEach(EnergyContext.allCases, id: \.self) { Text(L10n.text($0.label)).tag(Optional($0)) }
                    }
                    Text("Для взрослых 19+. При беременности, кормлении и особом рационе расчёт недоступен.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Toggle("Подогнать день под расчёт", isOn: Binding(
                        get: { member.automaticPortions == true },
                        set: { member.automaticPortions = $0 ? true : nil; if $0 { showCalculation = true } }
                    )).tint(Palette.sage)
                    if member.automaticPortions == true {
                        DisclosureGroup("Данные для расчёта", isExpanded: $showCalculation) {
                            Link(L10n.text("Источник расчёта энергии"), destination: PersonalPortions.sourceURL)
                                .font(.system(size: 12)).foregroundStyle(Palette.sage)
                        }
                        if let target = PersonalPortions.estimatedEnergy(preview) {
                            Text(L10n.format("Поддержание: ~%d ккал/день", Int(target.rounded())))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                            Text("Порции учитывают перекус. Размер перекуса и напитков остаётся заданным.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        } else {
                            Text("Заполните профиль или используйте ручные порции.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
        } header: { Text("Порции") }
    }
}
