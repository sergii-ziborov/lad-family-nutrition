import Foundation
import CloudKit
import UserNotifications

enum PersonalSettings {
    static let notifications = "lad.notificationsEnabled"
    static let iCloud = "lad.icloudEnabled"
    static var cloudAvailable: Bool { !ReleasePolicy.isStoreRelease && Bundle.main.object(forInfoDictionaryKey: "LadCloudEnabled") as? Bool == true }
}

enum ReleasePolicy {
    static var isStoreRelease: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }
}

enum LocalPersonalFile {
    static func url() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw CocoaError(.fileNoSuchFile) }
        var folder = base.appendingPathComponent("lad-personal-local", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try folder.setResourceValues(resources)
        return folder.appendingPathComponent("state.json")
    }
    static func read() throws -> Data? {
        let file = try url()
        return FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
    }
    static func save(_ state: DemoState) throws {
        try JSONEncoder().encode(state).write(to: url(), options: [.atomic, .completeFileProtection])
    }
}

enum LegalPage: String, CaseIterable, Identifiable {
    case terms, privacy, authors, sources, licenses
    var id: String { rawValue }
    var title: String {
        L10n.text(["terms": "Условия использования", "privacy": "Конфиденциальность", "authors": "Авторам курсов", "sources": "Источники и поддержка", "licenses": "Лицензии библиотек"][rawValue]!)
    }
    func text(language: String) -> String {
        if self == .licenses {
            guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt", subdirectory: "Legal/third-party") else { return "" }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        guard ["en", "ru", "uk"].contains(language),
              let url = Bundle.main.url(forResource: rawValue, withExtension: "md", subdirectory: "Legal/" + language),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}

struct MealReminder: Identifiable {
    let id: String
    let date: Date
    let kind: Int
    static func future(state: DemoState, now: Date, calendar: Calendar = .current) -> [Self] {
        state.slots.compactMap { slot in
            guard slot.memberIDs.contains(state.selectedMemberID),
                  !state.eatenIDs.contains("\(slot.id)-\(state.selectedMemberID)"),
                  !(state.skippedSlotIDs ?? []).contains(slot.id), slot.recipeID != Recipe.unplanned.id,
                  let day = calendar.date(byAdding: .day, value: slot.day, to: state.startDate) else { return nil }
            let minute = state.planningSchedule.endMinute(for: slot.kind)
            guard let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day), date > now else { return nil }
            return Self(id: "lad.meal.\(Int(state.startDate.timeIntervalSince1970)).\(slot.id).\(state.selectedMemberID)", date: date, kind: slot.kind)
        }.sorted { $0.date < $1.date }
    }
}

extension LadStore {
    func startPersonalServices() {
        guard !servicesStarted, !protectedStateReadFailed else { return }
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--screenshots") else { return }
        #endif
        servicesStarted = true
        cloudLastSync = UserDefaults.standard.object(forKey: "lad.cloudLastSync") as? Date
        migrateFoodHistory()
        maintainsDayMenu = true
        fillTodayMenu()
        personalDataChanged()
    }
    func personalDataChanged() {
        notificationTask?.cancel()
        notificationTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refreshMealNotifications()
        }
        if PersonalSettings.cloudAvailable && UserDefaults.standard.bool(forKey: PersonalSettings.iCloud) {
            if isCloudSyncing { cloudResyncRequested = true; return }
            cloudSyncTask?.cancel()
            cloudSyncTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await syncPersonalCloud()
            }
        }
    }
    func personalServicesForeground() {
        startPersonalServices()
        personalDataChanged()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshots") { return }
        #endif
        maintainsDayMenu = true
        fillTodayMenu()
    }
    func setNotifications(_ enabled: Bool) async {
        var denied = false
        if enabled {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                UserDefaults.standard.set(allowed, forKey: PersonalSettings.notifications)
                denied = !allowed
            } catch {
                UserDefaults.standard.set(false, forKey: PersonalSettings.notifications)
                notificationStatus = "Не удалось включить уведомления"
            }
        } else { UserDefaults.standard.set(false, forKey: PersonalSettings.notifications) }
        notificationTask?.cancel()
        await refreshMealNotifications()
        if denied { notificationStatus = "Разрешите уведомления в настройках iPhone" }
    }
    func refreshMealNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let enabled = UserDefaults.standard.bool(forKey: PersonalSettings.notifications)
        let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        guard !Task.isCancelled else { return }
        let existing = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix("lad.meal.") })
        guard enabled && allowed else {
            notificationStatus = enabled ? "Разрешите уведомления в настройках iPhone" : "Уведомления выключены"
            return
        }
        for reminder in MealReminder.future(state: state, now: now) {
            guard !Task.isCancelled, UserDefaults.standard.bool(forKey: PersonalSettings.notifications) else { return }
            let content = UNMutableNotificationContent()
            content.title = L10n.text("Дневник питания")
            content.body = L10n.format("%@: запишите, что вы съели и какая была порция.", DiaryCore.preparationLabel(reminder.kind))
            content.sound = .default
            // No meal names, calories or medical details on the lock screen.
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            do { try await center.add(UNNotificationRequest(identifier: reminder.id, content: content,
                                                          trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))) }
            catch { notificationStatus = "Не удалось обновить напоминания"; return }
            if Task.isCancelled || !UserDefaults.standard.bool(forKey: PersonalSettings.notifications) {
                center.removePendingNotificationRequests(withIdentifiers: [reminder.id]); return
            }
        }
        notificationStatus = "Напоминания включены"
    }
    func setPersonalCloud(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: PersonalSettings.iCloud)
        if enabled { await syncPersonalCloud() }
        else {
            cloudSyncTask?.cancel()
            cloudResyncRequested = false
            cloudSyncStatus = "iCloud выключен"
        }
    }
    func cloudSnapshot() -> PersonalCloudSnapshot {
        var payload = state
        payload.weightEntries = nil
        return PersonalCloudSnapshot(state: payload, modifiedAt: personalStateModifiedAt, deviceID: localAccountID,
                                     language: UserDefaults.standard.string(forKey: L10n.languageKey) ?? "system")
    }
    func syncPersonalCloud() async {
        guard UserDefaults.standard.bool(forKey: PersonalSettings.iCloud) else { return }
        guard !isCloudSyncing else { cloudResyncRequested = true; return }
        guard PersonalSettings.cloudAvailable else {
            cloudSyncStatus = "iCloud недоступен в этой сборке"; return
        }
        isCloudSyncing = true
        cloudResyncRequested = false
        defer {
            isCloudSyncing = false
            if cloudResyncRequested && UserDefaults.standard.bool(forKey: PersonalSettings.iCloud) { personalDataChanged() }
        }
        cloudSyncStatus = "Синхронизация…"
        let container = CKContainer(identifier: "iCloud.app.lad.family")
        let database = container.privateCloudDatabase
        do {
            guard try await container.accountStatus() == .available else {
                cloudSyncStatus = "Войдите в iCloud в настройках iPhone"; return
            }
            let recordID = CKRecord.ID(recordName: "lad-personal-v1")
            for attempt in 0..<3 {
                guard !Task.isCancelled, UserDefaults.standard.bool(forKey: PersonalSettings.iCloud) else { return }
                let record: CKRecord
                do { record = try await database.record(for: recordID) }
                catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "LadPersonal", recordID: recordID) }
                let local = cloudSnapshot()
                var merged = local
                if let asset = record["snapshot"] as? CKAsset, let url = asset.fileURL {
                    let remote = try JSONDecoder().decode(PersonalCloudSnapshot.self, from: Data(contentsOf: url))
                    guard remote.schemaVersion == 1, !remote.state.members.isEmpty, remote.state.hasValidMealSlots,
                          Set(remote.state.members.map(\.id)).count == remote.state.members.count,
                          (remote.state.diaryEntries ?? []).allSatisfy(\.isValid),
                          (remote.state.preparedDishes ?? []).allSatisfy({ $0.food.isValid && $0.totalServings.isFinite && $0.totalServings > 0 && $0.totalServings <= 100 && $0.useBy >= $0.preparedAt }) else {
                        cloudSyncStatus = "Версия данных iCloud не поддерживается"; return
                    }
                    merged = PersonalCloudSnapshot.merge(local, remote)
                }
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("lad-cloud-\(UUID().uuidString).json")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try JSONEncoder().encode(merged).write(to: temporary, options: [.atomic, .completeFileProtection])
                record["snapshot"] = CKAsset(fileURL: temporary)
                do {
                    let saved = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
                    guard let result = saved.saveResults[recordID] else { throw CocoaError(.fileWriteUnknown) }
                    _ = try result.get()
                } catch let error as CKError where (error.code == .serverRecordChanged || error.code == .partialFailure) && attempt < 2 {
                    continue
                }
                guard !Task.isCancelled, UserDefaults.standard.bool(forKey: PersonalSettings.iCloud) else { return }
                // A local edit may have occurred during the network request. Merge it,
                // then upload again; never replace a newer edit with an old capture.
                let current = cloudSnapshot()
                var final = PersonalCloudSnapshot.merge(current, merged)
                final.state.weightEntries = state.weightEntries
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                if try encoder.encode(final.state) != encoder.encode(state) {
                    try LocalWeekArchive.save(state, accountID: localAccountID)
                    isApplyingCloudSnapshot = true
                    state = final.state
                    isApplyingCloudSnapshot = false
                    selectedDay = min(6, max(0, selectedDay))
                }
                personalStateModifiedAt = final.modifiedAt
                UserDefaults.standard.set(final.modifiedAt, forKey: "lad.personalModifiedAt")
                if let language = final.language, ["system", "en", "ru", "uk"].contains(language) {
                    UserDefaults.standard.set(language, forKey: L10n.languageKey)
                }
                cloudLastSync = .now
                UserDefaults.standard.set(cloudLastSync, forKey: "lad.cloudLastSync")
                cloudSyncStatus = "Синхронизировано с iCloud"
                await refreshMealNotifications()
                if current.modifiedAt > local.modifiedAt { cloudResyncRequested = true }
                refreshClock()
                return
            }
            cloudSyncStatus = "Изменения на другом устройстве. Повторите синхронизацию."
        } catch {
            isApplyingCloudSnapshot = false
            cloudSyncStatus = "iCloud недоступен. Данные сохранены на телефоне."
        }
    }
    func personalPreferenceChanged() {
        personalStateModifiedAt = .now
        UserDefaults.standard.set(personalStateModifiedAt, forKey: "lad.personalModifiedAt")
        if servicesStarted { personalDataChanged() }
    }
    private func migrateFoodHistory() {
        guard !UserDefaults.standard.bool(forKey: "lad.diaryMigration.v1") else { return }
        var next = state
        var entries = next.diaryEntries ?? []
        let sources = LocalWeekArchive.states(accountID: localAccountID) + [state]
        for source in sources {
            for entry in source.diaryEntries ?? [] where !entries.contains(where: { $0.id == entry.id }) { entries.append(entry) }
            for slot in source.slots {
                for member in source.members where source.eatenIDs.contains("\(slot.id)-\(member.id)") {
                    let key = DiaryCore.planKey(startDate: source.startDate, slotID: slot.id, memberID: member.id)
                    guard !entries.contains(where: { $0.planKey == key }) else { continue }
                    let day = Calendar.current.date(byAdding: .day, value: slot.day, to: source.startDate) ?? source.startDate
                    let minute = source.planningSchedule.endMinute(for: slot.kind)
                    let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
                    let foods = slot.allRecipeIDs.map { id -> DiaryFood in
                        if let recipe = allRecipes.first(where: { $0.id == id }) {
                            return DiaryFood(recipe: recipe, servings: member.portion)
                        }
                        return DiaryFood(title: L10n.text("Блюдо из прежнего меню"))
                    }
                    if !foods.isEmpty {
                        entries.append(DiaryEntry(id: "legacy|" + key, memberID: member.id, memberName: member.name,
                                                  eatenAt: min(date, now), mealKind: slot.kind, planKey: key,
                                                  foods: foods, note: L10n.text("Перенесено из прежних отметок о съеденном"), timeEstimated: true))
                    }
                }
            }
        }
        next.diaryEntries = entries
        if !entries.isEmpty { state = next }
        UserDefaults.standard.set(true, forKey: "lad.diaryMigration.v1")
    }
}
