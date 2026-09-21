import SwiftUI

struct FamilyView: View {
    @EnvironmentObject var store: LadStore
    @State private var newName = ""
    @State private var showAdd = false
    @State private var selectedPerson: FamilyMember?
    @State private var supplementName = ""
    @State private var showSupplement = false
    @State private var showCloud = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(eyebrow: "КАЖДОМУ СВОЁ", title: "Наш круг")
                VStack(alignment: .leading, spacing: 7) {
                    Text("За одним столом").font(.system(size: 20, weight: .semibold, design: .serif))
                    Text("Одна готовка, личные настройки. Порции здесь примерные и задаются вручную; детям цели по весу не назначаются.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.paleSage.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
                SectionHeading(title: "Люди", trailing: "\(store.state.members.count) ПРОФИЛЯ")
                ForEach(Array(store.state.members.enumerated()), id: \.element.id) { index, member in
                    Button { selectedPerson = member } label: {
                        HStack(spacing: 14) {
                            Text(member.initials).font(.system(size: 22, weight: .semibold, design: .serif))
                                .frame(width: 50, height: 50)
                                .background([Palette.paleSage, Palette.peach, Color(red: 0.87, green: 0.84, blue: 0.73)][index % 3], in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(member.name).font(.system(size: 18, weight: .semibold, design: .serif))
                                Text([member.ageLabel, member.goal].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                Text("Ручная порция: \(Int(member.portion * 100))% базовой")
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                if !member.allergies.isEmpty { Text("Исключить: \(member.allergies.joined(separator: ", "))").font(.system(size: 11)).foregroundStyle(Palette.terracotta) }
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
                    Text(store.familyCloudStatus).font(.system(size: 11)).foregroundStyle(Palette.sage)
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
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Сегодня у \(store.currentMember.name)")
                    let eaten = (0..<3).filter { store.isEaten(store.slot(store.currentDay, $0)) }.count
                    Text("Отмечено приёмов пищи: \(eaten) из 3").font(.system(size: 14)).foregroundStyle(Palette.ink)
                    ProgressView(value: Double(eaten), total: 3).tint(Palette.sage)
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
}

struct MemberEditor: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State var member: FamilyMember
    @State private var ageText = ""
    @State private var energyText = ""
    private let goals = ["Баланс", "Поддержание", "Снижение", "Набор", "Без цели по весу"]
    private let allergens = ["Молоко", "Яйцо", "Рыба", "Пшеница"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Личные настройки") {
                    TextField("Имя", text: $member.name)
                    TextField("Возраст, полных лет", text: $ageText).keyboardType(.numberPad)
                    Picker("Ориентир", selection: $member.goal) {
                        ForEach(goals, id: \.self) { Text($0) }
                    }
                }
                Section {
                    HStack {
                        Text("Размер порции")
                        Spacer()
                        Text("\(Int(member.portion * 100))% базовой").foregroundStyle(Palette.sage)
                    }
                    Slider(value: $member.portion, in: 0.5...1.6, step: 0.05)
                } footer: {
                    Text("В прототипе это ручной множитель. Не персональная медицинская рекомендация.")
                }
                if (Int(ageText) ?? 0) >= 18 {
                    Section {
                        TextField("Ручной ориентир, ккал/день", text: $energyText).keyboardType(.numberPad)
                    } footer: {
                        Text("Не рассчитывается приложением и не заменяет консультацию специалиста. Используется только для сравнения и сортировки блюд.")
                    }
                }
                Section("Исключить аллергены") {
                    ForEach(allergens, id: \.self) { allergen in
                        Toggle(allergen, isOn: Binding(
                            get: { member.allergies.contains(allergen) },
                            set: { enabled in
                                if enabled { member.allergies.append(allergen) }
                                else { member.allergies.removeAll { $0 == allergen } }
                            }
                        )).tint(Palette.sage)
                    }
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
                            store.updateMember(member)
                            dismiss()
                        }.bold()
                    }
                }
        }.onAppear {
            ageText = member.ageYears.map(String.init) ?? ""
            energyText = member.dailyEnergyTarget.map(String.init) ?? ""
        }
    }
}
