import AppKit
import SwiftUI

/// Вкладка «Статистика»: що записувати і як показувати у вікні статистики.
struct StatsSettingsView: View {
    var store: StatsStore
    var preferences: StatsPreferences
    var openStats: () -> Void

    private var values: StatsPreferences.Values { preferences.values }

    var body: some View {
        Form {
            recordingSection
            windowSection
            tokensSection
            sectionsSection
            logSection
            panelSection
        }
        .formStyle(.grouped)
        // Форма прокручувана, тож власної висоти не має — задаємо явно.
        .frame(width: 540, height: 660)
    }

    // MARK: - Запис

    private var recordingSection: some View {
        Section {
            Toggle("Збирати статистику", isOn: Binding(
                get: { values.recording },
                set: {
                    preferences.values.recording = $0
                    store.applyRecordingPreference()
                }
            ))

            Group {
                toggle("Записувати історію лімітів", \.recordLimits)
                Toggle("Зберігати текст запитів", isOn: Binding(
                    get: { values.storePrompts },
                    set: {
                        preferences.values.storePrompts = $0
                        // Уже збережені записи треба перечитати з новим правилом.
                        store.rebuild()
                    }
                ))
                Picker("Зберігати записи", selection: Binding(
                    get: { values.retention },
                    set: {
                        preferences.values.retention = $0
                        store.importNow()
                    }
                )) {
                    ForEach(StatsRetention.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .disabled(!values.recording)

            LabeledContent("Зібрано") {
                Text(collectedSummary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Button("Відкрити статистику", action: openStats)
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Перечитати") { store.rebuild() }
                    .disabled(!values.recording || store.isImporting)
                    .help("Розібрати всі журнали агентів наново")
                Button("У Finder") { store.revealDatabase() }
                    .help("Показати файл бази статистики")
                Button("Очистити…") { confirmClear() }
            }
        } header: {
            Text("Запис")
        } footer: {
            Text("Статистика збирається з локальних журналів агентів (~/.claude/projects і ~/.codex/sessions), тож історія є й за час до встановлення NotchMeter. Усе зберігається лише на цьому Mac. Claude Code типово видаляє свої журнали через 30 днів — записи, які NotchMeter уже переніс до себе, лишаються.")
                .foregroundStyle(.secondary)
        }
    }

    private var collectedSummary: String {
        if store.isImporting && store.turns.isEmpty { return "читаю журнали… \(Int(store.progress * 100))%" }
        guard let first = store.firstRecord else { return "поки нічого" }
        let turns = store.turns.filter { !$0.isSubagent }.count
        let size = ByteCountFormatter.string(fromByteCount: Int64(store.databaseSize), countStyle: .file)
        return "\(StatsFormat.number(Double(turns), style: .full)) ходів з \(StatsFormat.fullDate.string(from: first)) · \(size)"
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Очистити всю статистику?"
        alert.informativeText = "Записи, яких уже немає в журналах агентів, буде втрачено назавжди. Решту NotchMeter прочитає знову під час наступного імпорту."
        alert.addButton(withTitle: "Очистити")
        alert.addButton(withTitle: "Скасувати")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearAll()
    }

    // MARK: - Вікно статистики

    private var windowSection: some View {
        Section {
            picker("Період", \.period, options: StatsPeriod.allCases) { $0.title }
            picker("Агенти", \.agentFilter, options: AgentFilter.allCases) { $0.title }
            picker("Метрика графіка", \.metric, options: StatsMetric.allCases) { $0.title }
            picker("Групування", \.grouping, options: StatsGrouping.allCases) { $0.title }
            picker("Вигляд графіка", \.chartStyle, options: StatsChartStyle.allCases) { $0.title }
            picker("Крок графіка", \.bucket, options: StatsBucketChoice.allCases) { $0.title }
            picker("Числа", \.numberStyle, options: StatsNumberStyle.allCases) { $0.title }
            Picker("Тиждень починається з", selection: Binding(
                get: { values.weekStartsMonday },
                set: { preferences.values.weekStartsMonday = $0 }
            )) {
                Text("Понеділка").tag(true)
                Text("Неділі").tag(false)
            }
            toggle("Враховувати субагентів", \.includeSubagents)
        } header: {
            Text("Вікно статистики")
        } footer: {
            Text("Період, агенти, метрику й вигляд графіка можна перемикати й просто у вікні — вибір запам'ятовується. «Автоматичний» крок: години для дня, дні до півтора місяця, далі тижні й місяці. Субагенти Claude додають токени й виклики, але не ходи й час: вони працюють паралельно з ходом, що їх запустив.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Токени

    private var tokensSection: some View {
        Section {
            toggle("Вхідні", \.tokensInput)
            toggle("Вихідні (разом із міркуваннями)", \.tokensOutput)
            toggle("Запис у кеш", \.tokensCacheWrite)
            toggle("Читання з кешу", \.tokensCacheRead)
        } header: {
            Text("Які токени рахувати")
        } footer: {
            Text("Агенти щоразу заново надсилають усю розмову, і більшість її читається з кешу: цих токенів у десятки разів більше за решту, а коштують вони в рази дешевше. Тому читання з кешу типово не враховується — інакше воно затуляє все інше.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Розділи

    private var sectionsSection: some View {
        Section {
            toggle("Підсумки", \.showSummary)
            toggle("Порівняння з попереднім періодом", \.showComparison)
                .disabled(!values.showSummary)
            toggle("Графік", \.showChart)
            toggle("Теплова карта (день тижня × година)", \.showHeatmap)
            toggle("Історія лімітів", \.showLimits)
            Group {
                toggle("Ліміт на 5 годин", \.limitsShowFiveHour)
                toggle("Ліміт на тиждень", \.limitsShowWeek)
                toggle("Інші ліміти (Opus, застосунки)", \.limitsShowOther)
            }
            .disabled(!values.showLimits)
            toggle("Проєкти", \.showProjects)
            toggle("Моделі", \.showModels)
            Stepper(value: Binding(
                get: { values.projectsCount },
                set: { preferences.values.projectsCount = $0 }
            ), in: 3...30) {
                LabeledContent("Рядків у проєктах і моделях") {
                    Text("\(values.projectsCount)").monospacedDigit()
                }
            }
            .disabled(!values.showProjects && !values.showModels)
            toggle("Журнал ходів", \.showLog)
        } header: {
            Text("Розділи вікна")
        }
    }

    // MARK: - Журнал

    private var logSection: some View {
        Section {
            toggle("Коли", \.logTime)
            toggle("Агент", \.logAgent)
            toggle("Проєкт", \.logProject)
            toggle("Назва сесії", \.logTitle)
            toggle("Текст запиту", \.logPrompt)
            toggle("Модель", \.logModel)
            toggle("Тривалість", \.logDuration)
            toggle("Токени", \.logTokens)
            toggle("Запити до моделі", \.logApiCalls)
            toggle("Виклики інструментів", \.logToolCalls)
            Stepper(value: Binding(
                get: { values.logRows },
                set: { preferences.values.logRows = $0 }
            ), in: 25...1000, step: 25) {
                LabeledContent("Рядків за раз") {
                    Text("\(values.logRows)").monospacedDigit()
                }
            }
        } header: {
            Text("Колонки журналу")
        } footer: {
            Text("Клік по рядку журналу розгортає подробиці: повний запит, усі види токенів, час початку й кінця.")
                .foregroundStyle(.secondary)
        }
        .disabled(!values.showLog)
    }

    // MARK: - Панель

    private var panelSection: some View {
        Section {
            toggle("Підсумок за сьогодні в панелі", \.panelShowsToday)
            Group {
                toggle("Ходи", \.panelTodayTurns)
                toggle("Час роботи", \.panelTodayTime)
                toggle("Токени", \.panelTodayTokens)
            }
            .disabled(!values.panelShowsToday)

            HStack {
                Spacer()
                Button("Скинути вигляд до типового") { preferences.resetDisplay() }
                    .disabled(preferences.isDefault)
            }
        } header: {
            Text("Панель біля вирізу")
        } footer: {
            Text("Рядок унизу розгорнутої панелі з підсумком дня за всіма агентами; токени — за видами, обраними вище.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Помічники

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<StatsPreferences.Values, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { preferences.values[keyPath: keyPath] },
            set: { preferences.values[keyPath: keyPath] = $0 }
        ))
    }

    private func picker<Option: Hashable>(
        _ title: String,
        _ keyPath: WritableKeyPath<StatsPreferences.Values, Option>,
        options: [Option],
        label: @escaping (Option) -> String
    ) -> some View {
        Picker(title, selection: Binding(
            get: { preferences.values[keyPath: keyPath] },
            set: { preferences.values[keyPath: keyPath] = $0 }
        )) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
    }
}
