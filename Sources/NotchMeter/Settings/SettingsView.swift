import SwiftUI

// Прив'язки в налаштуваннях зібрані вручну через `Binding(get:set:)`: без
// повного Xcode макрос `@State` недоступний, а спостережувані моделі й так
// тримають стан.

/// Вкладка «Вигляд»: що показувати біля вирізу й у панелі та перегляд змін.
struct AppearanceSettingsView: View {
    var model: SettingsModel
    var preferences: DisplayPreferences
    var content: ContentPreferences

    private var values: ContentPreferences.Values { content.values }

    var body: some View {
        Form {
            previewSection
            screenSection
            hoverSection
            panelLimitsSection
            panelSessionsSection
        }
        .formStyle(.grouped)
        // Форма прокручувана, тож власної висоти не має — задаємо явно.
        .frame(width: 540, height: 660)
    }

    // MARK: - Перегляд

    private var previewSection: some View {
        Section {
            Picker("Показати біля вирізу", selection: Binding(
                get: { model.preview },
                set: { model.preview = $0 }
            )) {
                ForEach(NotchPreviewMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Перегляд")
        } footer: {
            Text("Поки відкрите це вікно, виріз тримає обраний стан — зміни нижче видно одразу, без наведення й кліків. Після закриття вікна все повертається як було.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Монітор

    private var screenSection: some View {
        // Читаємо лічильник, щоб список моніторів оновлювався при під'єднанні.
        _ = model.screenRevision
        let screen = NotchGeometry.preferredScreen()
        let onNotchScreen = screen?.hasNotch ?? false
        let automatic = screen.map { NotchGeometry.menuBarHeight(on: $0) } ?? NSStatusBar.system.thickness
        let isAutomatic = preferences.externalBarHeight <= 0

        return Section {
            Picker("Показувати на моніторі", selection: Binding(
                get: { preferences.screenChoice },
                set: { preferences.screenChoice = $0 }
            )) {
                ForEach(screenOptions, id: \.choice) { option in
                    Text(option.title).tag(option.choice)
                }
            }

            Group {
                Toggle("Висота як у рядка меню", isOn: Binding(
                    get: { isAutomatic },
                    set: { preferences.externalBarHeight = $0 ? 0 : Double(automatic) }
                ))

                LabeledContent("Висота") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { isAutomatic ? Double(automatic) : preferences.externalBarHeight },
                            set: { preferences.externalBarHeight = $0.rounded() }
                        ), in: 20...48)
                        .frame(width: 180)
                        Text("\(Int(isAutomatic ? automatic : preferences.externalBarHeight))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                .disabled(isAutomatic)
            }
            .disabled(onNotchScreen)
        } header: {
            Text("Монітор")
        } footer: {
            Text(onNotchScreen
                 ? "«Автоматично» — екран MacBook зі справжнім вирізом, а коли кришка закрита — монітор із рядком меню. Висоту можна змінити лише на екрані без вирізу: на MacBook вона завжди збігається з вирізом."
                 : "«Автоматично» — екран MacBook зі справжнім вирізом, а коли кришка закрита — монітор із рядком меню. На екрані без вирізу висота автоматично дорівнює рядку меню — зараз \(Int(automatic)) pt.")
                .foregroundStyle(.secondary)
        }
    }

    /// Автоматичний вибір, головний екран і кожен під'єднаний монітор. Обраний
    /// раніше, але зараз від'єднаний монітор теж лишається в списку.
    private var screenOptions: [(choice: ScreenChoice, title: String)] {
        var options: [(choice: ScreenChoice, title: String)] = [
            (.automatic, "Автоматично"),
            (.main, "Головний (з рядком меню)"),
        ]
        var connected: Set<String> = []
        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID else { continue }
            connected.insert(uuid)
            let name = screen.localizedName
            options.append((.display(uuid: uuid, name: name), screen.hasNotch ? "\(name) (з вирізом)" : name))
        }
        if case let .display(uuid, name) = preferences.screenChoice {
            if let index = options.firstIndex(where: {
                if case .display(uuid, _) = $0.choice { return true } else { return false }
            }) {
                // Назва могла змінитися — тег має збігатися з обраним значенням.
                options[index].choice = preferences.screenChoice
            } else if !connected.contains(uuid) {
                options.append((preferences.screenChoice, "\(name) — не під'єднано"))
            }
        }
        return options
    }

    // MARK: - При наведенні

    private var hoverSection: some View {
        Section {
            Picker("Ліворуч від вирізу", selection: Binding(
                get: { preferences.leftTool },
                set: { preferences.leftTool = $0 }
            )) {
                ForEach(DisplayPreferences.tools, id: \.self) { tool in
                    Text(tool.displayName).tag(tool)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Праворуч від вирізу") {
                Text(preferences.rightTool.displayName)
                    .foregroundStyle(Color(nsColor: preferences.rightTool.accent))
            }

            Picker("Ліміт в індикаторі", selection: Binding(
                get: { preferences.compactWindow },
                set: { preferences.compactWindow = $0 }
            )) {
                ForEach(CompactWindowChoice.allCases, id: \.self) { choice in
                    Text(choice.menuTitle).tag(choice)
                }
            }

            picker("Назва агента", \.hoverLabel, options: AgentLabelStyle.allCases) { $0.title }
            toggle("Шкала ліміту", \.hoverShowsGauge)
            picker("Колір шкали", \.hoverGaugeColoring, options: GaugeColoring.allCases) { $0.title }
                .disabled(!values.hoverShowsGauge)
            toggle("Відсоток", \.hoverShowsPercent)
            picker("Шкала й відсоток показують", \.hoverPercentMode, options: PercentMode.allCases) { $0.title }
                .disabled(!values.hoverShowsGauge && !values.hoverShowsPercent)
            toggle("Мітка вікна ліміту (5г, 7д)", \.hoverShowsWindowTag)
            toggle("Час до скидання ліміту", \.hoverShowsResetTime)
            toggle("Крапка активності", \.hoverShowsActivity)
            toggle("Лічильник сесій біля крапки", \.hoverShowsBadge)
                .disabled(!values.hoverShowsActivity)
            LabeledContent("Відступ від краю крила") {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { values.hoverEdgePadding },
                        set: { content.values.hoverEdgePadding = $0.rounded() }
                    ), in: 4...24)
                    .frame(width: 180)
                    Text("\(Int(values.hoverEdgePadding))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        } header: {
            Text("При наведенні на виріз")
        } footer: {
            Text("Щоб бачити зміни одразу, оберіть угорі «Стан наведення». Ширина крил підлаштовується під вміст ширшого з них, а відступи від краю крила й від вирізу лишаються сталими; у вужчому крилі логотип стоїть біля краю, решта — біля вирізу.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Панель: ліміти

    private var panelLimitsSection: some View {
        Section {
            toggle(Tool.codex.displayName, \.panelShowsCodex)
            toggle(Tool.claude.displayName, \.panelShowsClaude)
            toggle("Логотип біля назви агента", \.panelShowsProviderLogo)
            toggle("Назва плану (plus, pro…)", \.panelShowsPlan)

            toggle("Ліміт на 5 годин", \.panelShowsFiveHour)
            toggle("Ліміт на тиждень", \.panelShowsWeek)
            toggle("Ліміт на тиждень для Opus", \.panelShowsOpusWeek)
            toggle("Ліміт на тиждень для застосунків", \.panelShowsAppsWeek)

            toggle("Шкала ліміту", \.panelShowsGauge)
            LabeledContent("Ширина шкали") {
                HStack(spacing: 10) {
                    Slider(value: Binding(
                        get: { values.panelGaugeWidth },
                        set: { content.values.panelGaugeWidth = $0.rounded() }
                    ), in: 40...200)
                    .frame(width: 180)
                    Text("\(Int(values.panelGaugeWidth))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
            .disabled(!values.panelShowsGauge)
            picker("Колір шкали", \.panelGaugeColoring, options: GaugeColoring.allCases) { $0.title }
                .disabled(!values.panelShowsGauge)
            picker("Шкала й відсоток показують", \.panelPercentMode, options: PercentMode.allCases) { $0.title }
            picker("Час скидання", \.panelResetFormat, options: ResetFormat.allCases) { $0.title }
            toggle("Позначка «застаріло»", \.panelShowsStale)
            toggle("Помилки й попередження", \.panelShowsErrors)
        } header: {
            Text("Панель: ліміти")
        } footer: {
            Text("Щоб бачити зміни одразу, оберіть угорі «Панель». Вікна лімітів, яких немає у вашому плані, не з'являться навіть увімкненими.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Панель: сесії

    private var panelSessionsSection: some View {
        Section {
            toggle("Список сесій", \.panelShowsSessions)

            Group {
                toggle("Сесії в простої", \.panelIncludesIdleSessions)

                Stepper(value: Binding(
                    get: { values.panelMaxSessions },
                    set: { content.values.panelMaxSessions = $0 }
                ), in: 1...12) {
                    LabeledContent("Скільки сесій показувати") {
                        Text("\(values.panelMaxSessions)")
                            .monospacedDigit()
                    }
                }

                toggle("Логотип замість CX, CC", \.panelSessionUsesLogo)
                toggle("Назва сесії", \.panelSessionShowsTitle)
                toggle("Тека проєкту", \.panelSessionShowsDirectory)
                toggle("Стан (працює, чекає вводу)", \.panelSessionShowsState)
                toggle("Тривалість ходу", \.panelSessionShowsElapsed)
                toggle("Кількість кроків (Codex)", \.panelSessionShowsSteps)
            }
            .disabled(!values.panelShowsSessions)

            toggle("Час останнього оновлення", \.panelShowsUpdatedAt)

            HStack {
                Spacer()
                Button("Скинути вміст до типового") { content.reset() }
                    .disabled(content.isDefault)
            }
        } header: {
            Text("Панель: сесії")
        }
    }

    // MARK: - Помічники

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<ContentPreferences.Values, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { content.values[keyPath: keyPath] },
            set: { content.values[keyPath: keyPath] = $0 }
        ))
    }

    private func picker<Option: Hashable>(
        _ title: String,
        _ keyPath: WritableKeyPath<ContentPreferences.Values, Option>,
        options: [Option],
        label: @escaping (Option) -> String
    ) -> some View {
        Picker(title, selection: Binding(
            get: { content.values[keyPath: keyPath] },
            set: { content.values[keyPath: keyPath] = $0 }
        )) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
    }
}

/// Вкладка «Загальні»: частота оновлення, ручне оновлення й автозапуск.
struct GeneralSettingsView: View {
    var model: SettingsModel

    var body: some View {
        Form {
            updatesSection
            systemSection
        }
        .formStyle(.grouped)
        // З запасом під підказку про підтвердження автозапуску — щоб навіть
        // з нею не з'являлась прокрутка.
        .frame(width: 540, height: 430)
    }

    // MARK: - Оновлення та система

    private var updatesSection: some View {
        Section {
            Picker("Частота оновлення лімітів", selection: Binding(
                get: { model.refreshMultiplier },
                set: { model.refreshMultiplier = $0 }
            )) {
                ForEach(SettingsModel.refreshOptions, id: \.multiplier) { option in
                    Text(option.title).tag(option.multiplier)
                }
            }

            LabeledContent("Опитування") {
                Text(model.refreshSummary)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Дані") {
                HStack(spacing: 10) {
                    if let updated = model.lastUpdated {
                        Text("оновлено \(ExpandedView.clock.string(from: updated))")
                            .foregroundStyle(.secondary)
                    }
                    Button("Оновити зараз") { model.refreshNow() }
                }
            }
        } header: {
            Text("Оновлення")
        } footer: {
            Text("Впливає лише на відсотки лімітів. Codex читається з локальних логів — це майже нічого не коштує. Claude запитується в API Anthropic: рідше оновлення — менше запитів і менший ризик тимчасового блокування за частоту. Ваш ліміт на запити до моделей ці перевірки не витрачають.\n\nКрапки активності й список сесій від частоти не залежать — вони оновлюються за кілька секунд. Коли ви наводите на виріз чи відкриваєте панель, ліміти теж оновлюються, але не частіше ніж раз на \(SettingsModel.duration(UsageStore.onDemandMinimumGap)).")
                .foregroundStyle(.secondary)
        }
    }

    private var systemSection: some View {
        Section("Система") {
            Toggle("Запускати при вході в систему", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            if model.loginNeedsApproval {
                Text("Підтвердіть автозапуск у Системних параметрах → Загальні → Об'єкти входу.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let error = model.loginError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Style.warningColor)
            }
        }
    }
}
