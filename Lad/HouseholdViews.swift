import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var store: LadStore
    @State private var newName = ""
    @State private var showAdd = false
    @State private var selectedPerson: FamilyMember?
    @State private var supplementName = ""
    @State private var showSupplement = false
    @State private var showCloud = false
    @State private var showMealTimes = false
    @State private var showSettings = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(eyebrow: "КАЖДОМУ СВОЁ", title: "Наш круг")
                Button { showSettings = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape").font(.system(size: 21)).foregroundStyle(Palette.sage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Настройки").font(.system(size: 15, weight: .semibold))
                            Text("Язык приложения").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Palette.sage)
                    }.foregroundStyle(Palette.ink).padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 7) {
                    Text("За одним столом").font(.system(size: 20, weight: .semibold, design: .serif))
                    Text("Одна готовка, личные настройки. Порции здесь примерные и задаются вручную; детям цели по весу не назначаются.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
                SectionHeading(title: "Люди", trailing: L10n.format("%d ПРОФИЛЯ", store.state.members.count))
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
                                Text(L10n.format("Ручная порция: %d%% базовой", Int(member.portion * 100)))
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                if let height = member.heightCm, let weight = member.weightKg {
                                    Text(L10n.format("Рост %.0f см · вес %.1f кг", height, weight))
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                if let fat = member.fatPercent {
                                    Text(L10n.format("Жир: %.1f%% массы тела", fat))
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                if let muscle = member.musclePercent {
                                    Text(L10n.format("Мышцы: %.1f%% массы тела", muscle))
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
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
                        Text("Локальный аккаунт").font(.system(size: 16, weight: .semibold))
                    }
                    Text("Семейные профили хранятся на этом iPhone. Временное облако Hetzner только обновляет их по защищённому соединению; в GitHub личные данные не отправляются.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text(L10n.format("Локально сохранено прошлых недель: %d", store.archivedWeekCount))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if let warning = store.storageWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                    }
                    Text(L10n.text(store.familyCloudStatus)).font(.system(size: 11)).foregroundStyle(Palette.sage)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Настроить облако") { showCloud = true }
                        Spacer()
                        if PrivateRecipeAccess.isConfigured {
                            Button("Обновить") { Task { await store.refreshFamily() } }
                        }
                    }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 19))
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Время семьи")
                    Text("Ориентиры помогают показать актуальный приём пищи. После них еда не исчезает из плана и не отмечается автоматически.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text(L10n.format("Завтрак до %@ · обед до %@ · ужин до %@",
                                     mealTime(store.mealSchedule.breakfastEnds), mealTime(store.mealSchedule.lunchEnds),
                                     mealTime(store.mealSchedule.dinnerEnds)))
                        .font(.system(size: 12)).foregroundStyle(Palette.ink)
                    Button("Изменить время") { showMealTimes = true }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 19))
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: L10n.format("Сегодня у %@", store.currentMember.name))
                    let eaten = (0..<3).filter { store.isEaten(store.slot(store.currentDay, $0)) }.count
                    let planned = (0..<3).filter {
                        let slot = store.slot(store.currentDay, $0)
                        return slot.memberIDs.contains(store.currentMember.id) && !store.isSkipped(slot)
                    }.count
                    Text(L10n.format("Отмечено приёмов пищи: %d из %d", eaten, planned))
                        .font(.system(size: 14)).foregroundStyle(Palette.ink)
                    ProgressView(value: Double(eaten), total: Double(max(1, planned))).tint(Palette.sage)
                    Text("План не считается съеденным, пока вы сами его не отметите.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 19))
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Мои добавки")
                    Text("Только личный учёт факта приёма — не рекомендация или назначение.")
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
            .sheet(isPresented: $showCloud) { PrivateCatalogSheet() }
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
    private func mealTime(_ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60,
                                         second: 0, of: store.now) ?? store.now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct LanguageSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(L10n.languageKey) private var language = "system"
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Язык приложения", selection: $language) {
                        Text("Как на телефоне").tag("system")
                        Text("English").tag("en")
                        Text("Русский").tag("ru")
                    }.pickerStyle(.inline)
                } footer: {
                    Text("Названия рецептов из подключённого каталога могут остаться на языке источника.")
                }
            }
            .navigationTitle("Настройки")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}

private struct MealTimesSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State private var breakfast = Date()
    @State private var lunch = Date()
    @State private var dinner = Date()
    @State private var warning = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Завтрак до", selection: $breakfast, displayedComponents: .hourAndMinute)
                    DatePicker("Обед до", selection: $lunch, displayedComponents: .hourAndMinute)
                    DatePicker("Ужин до", selection: $dinner, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Это ваши привычные часы по местному времени телефона, а не медицинские ограничения. Прошедший приём можно отметить позднее.")
                }
                if !warning.isEmpty { Text(warning).foregroundStyle(Palette.terracotta) }
            }
            .navigationTitle("Время приёмов пищи")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        let schedule = MealSchedule(breakfastEnds: minutes(breakfast), lunchEnds: minutes(lunch),
                                                    dinnerEnds: minutes(dinner))
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
        .onAppear {
            breakfast = date(store.mealSchedule.breakfastEnds)
            lunch = date(store.mealSchedule.lunchEnds)
            dinner = date(store.mealSchedule.dinnerEnds)
        }
    }
    private func date(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60,
                              second: 0, of: store.now) ?? store.now
    }
    private func minutes(_ date: Date) -> Int { MealTiming.minuteOfDay(date) }
}

struct MemberEditor: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State var member: FamilyMember
    @State private var ageText = ""
    @State private var energyText = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var fatMassText = ""
    @State private var muscleMassText = ""
    @State private var allergenQuery = ""
    private let goals = ["Баланс", "Поддержание", "Снижение", "Набор", "Без цели по весу"]
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
        if !heightText.isEmpty && quantity(heightText, range: 50...250) == nil {
            return L10n.text("Проверьте рост: от 50 до 250 см.")
        }
        if !weightText.isEmpty && quantity(weightText, range: 10...500) == nil {
            return L10n.text("Проверьте вес: от 10 до 500 кг.")
        }
        if (Int(ageText) ?? 0) >= 18 && (!fatMassText.isEmpty || !muscleMassText.isEmpty) {
            guard let weight = quantity(weightText, range: 10...500) else {
                return L10n.text("Для расчёта состава тела сначала укажите вес.")
            }
            let fat = fatMassText.isEmpty ? 0 : quantity(fatMassText, range: 0...weight)
            let muscle = muscleMassText.isEmpty ? 0 : quantity(muscleMassText, range: 0...weight)
            guard let fat, let muscle, fat + muscle <= weight else {
                return L10n.text("Масса жира и мышц не должна превышать вес тела.")
            }
        }
        return nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Личные настройки") {
                    TextField(L10n.text("Имя"), text: $member.name)
                    TextField(L10n.text("Возраст, полных лет"), text: $ageText).keyboardType(.numberPad)
                    Picker("Ориентир", selection: $member.goal) {
                        ForEach((Int(ageText) ?? member.ageYears ?? 18) < 18 ? ["Без цели по весу"] : goals, id: \.self) {
                            Text(L10n.text($0))
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Размер порции")
                        Spacer()
                        Text(L10n.format("%d%% базовой", Int(member.portion * 100))).foregroundStyle(Palette.sage)
                    }
                    Slider(value: $member.portion, in: 0.5...1.6, step: 0.05)
                } footer: {
                    Text("В прототипе это ручной множитель. Не персональная медицинская рекомендация.")
                }
                if (Int(ageText) ?? 0) >= 18 {
                    Section {
                        TextField(L10n.text("Ручной ориентир, ккал/день"), text: $energyText).keyboardType(.numberPad)
                    } footer: {
                        Text("Не рассчитывается приложением и не заменяет консультацию специалиста. Используется только для сравнения и сортировки блюд.")
                    }
                }
                Section {
                    TextField(L10n.text("Рост, см"), text: $heightText).keyboardType(.decimalPad)
                    TextField(L10n.text("Вес, кг"), text: $weightText).keyboardType(.decimalPad)
                } header: {
                    Text("Измерения")
                } footer: {
                    Text("Рост и вес вводятся вручную. По ним нельзя достоверно определить долю жира или мышц.")
                }
                if (Int(ageText) ?? 0) >= 18 {
                    Section {
                        TextField(L10n.text("Измеренная масса жира, кг"), text: $fatMassText).keyboardType(.decimalPad)
                        TextField(L10n.text("Измеренная масса мышц, кг"), text: $muscleMassText).keyboardType(.decimalPad)
                        if let weight = quantity(weightText, range: 10...500), weight > 0 {
                            if let fat = quantity(fatMassText, range: 0...weight) {
                                Text(L10n.format("Жир: %.1f%% массы тела", fat / weight * 100))
                            }
                            if let muscle = quantity(muscleMassText, range: 0...weight) {
                                Text(L10n.format("Мышцы: %.1f%% массы тела", muscle / weight * 100))
                            }
                        }
                    } header: {
                        Text("Состав тела")
                    } footer: {
                        Text("Проценты = измеренная масса / вес × 100. Введите данные из измерения; это не оценка приложения и не медицинское заключение.")
                    }
                }
                if let measurementIssue {
                    Text(measurementIssue).font(.system(size: 12)).foregroundStyle(Palette.terracotta)
                }
                Section("Исключить аллергены") {
                    TextField(L10n.text("Поиск аллергена"), text: $allergenQuery)
                        .textInputAutocapitalization(.never)
                    ForEach(visibleAllergens, id: \.self) { allergen in
                        Toggle(L10n.text(allergen), isOn: Binding(
                            get: { member.allergies.contains(allergen) },
                            set: { enabled in
                                if enabled { member.allergies.append(allergen) }
                                else { member.allergies.removeAll { $0 == allergen } }
                            }
                        )).tint(Palette.sage)
                    }
                    Text("Список помогает фильтровать блюда, но у большинства рецептов состав аллергенов не подтверждён. Всегда проверяйте ингредиенты и упаковки.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Section { Text("Для ребёнка, беременности, аллергии и медицинских ограничений автоматический расчёт меню здесь не валидирован.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted) }
            }.scrollContentBackground(.hidden).background(Palette.canvas)
                .navigationTitle(member.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Сохранить") {
                            member.ageYears = Int(ageText).flatMap { (0...120).contains($0) ? $0 : nil }
                            member.dailyEnergyTarget = (member.ageYears ?? 0) >= 18 ? Int(energyText).flatMap { (1000...5000).contains($0) ? $0 : nil } : nil
                            member.heightCm = quantity(heightText, range: 50...250)
                            member.weightKg = quantity(weightText, range: 10...500)
                            member.measuredFatMassKg = (member.ageYears ?? 0) >= 18 ?
                                quantity(fatMassText, range: 0...(member.weightKg ?? 0)) : nil
                            member.measuredMuscleMassKg = (member.ageYears ?? 0) >= 18 ?
                                quantity(muscleMassText, range: 0...(member.weightKg ?? 0)) : nil
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
            fatMassText = member.measuredFatMassKg.map { String($0) } ?? ""
            muscleMassText = member.measuredMuscleMassKg.map { String($0) } ?? ""
        }.onChange(of: ageText) { _, value in
            if let age = Int(value), age < 18 { member.goal = "Без цели по весу" }
        }
    }
}
