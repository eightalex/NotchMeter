import Foundation

/// Построкове читання JSONL-журналів. Журнали агентів займають сотні
/// мегабайт, а потрібна лише невелика частка рядків, тож спершу шукаємо
/// в сирих байтах ключові слова і лише тоді розбираємо JSON.
enum JSONLines {
    static func forEach(in url: URL, containingAny needles: [String], _ body: ([String: Any]) -> Void) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return }
        let patterns = needles.map { Array($0.utf8) }

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let count = raw.count
            var start = 0
            while start < count {
                let end = memchr(base + start, 0x0A, count - start)
                    .map { base.distance(to: UnsafeRawPointer($0)) } ?? count
                let length = end - start
                if length > 0 {
                    let line = base + start
                    let matches = patterns.contains { pattern in
                        pattern.withUnsafeBytes { memmem(line, length, $0.baseAddress, pattern.count) != nil }
                    }
                    if matches {
                        // Без пулу об'єкти Foundation з сотень тисяч рядків
                        // жили б до кінця імпорту — сотні мегабайт пам'яті.
                        autoreleasepool {
                            if let object = try? JSONSerialization.jsonObject(with: Data(bytes: line, count: length)),
                               let dictionary = object as? [String: Any] {
                                body(dictionary)
                            }
                        }
                    }
                }
                start = end + 1
            }
        }
    }
}

/// Мітки часу журналів — `2026-09-16T19:52:44.625Z`. `ISO8601DateFormatter`
/// на сотнях тисяч рядків помітно повільніший, тож розбираємо вручну.
enum LogTime {
    static func parse(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let bytes = Array(text.utf8)
        guard bytes.count >= 19 else { return nil }

        func number(_ from: Int, _ length: Int) -> Int? {
            var result = 0
            for index in from..<(from + length) {
                let digit = Int(bytes[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                result = result * 10 + digit
            }
            return result
        }

        guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2)
        else { return nil }

        var fraction = 0.0
        if bytes.count > 20, bytes[19] == UInt8(ascii: ".") {
            var scale = 0.1
            var index = 20
            while index < bytes.count, let digit = number(index, 1) {
                fraction += Double(digit) * scale
                scale /= 10
                index += 1
            }
        }

        // Кількість днів від 1970-01-01 за григоріанським календарем (алгоритм Г. Гіннанта).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146097 + dayOfEra - 719468

        let seconds = Double(days * 86400 + hour * 3600 + minute * 60 + second) + fraction
        return Date(timeIntervalSince1970: seconds)
    }
}

// MARK: - Claude Code

/// Журнали Claude Code: `~/.claude/projects/<проєкт>/<сесія>.jsonl`, а
/// субагенти — у `<сесія>/subagents/agent-*.jsonl`.
enum ClaudeLogParser {
    static func parse(_ url: URL, storePrompts: Bool) -> ParsedLog {
        let isSubagent = url.deletingLastPathComponent().lastPathComponent == "subagents"
        let parentSession = isSubagent
            ? url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            : nil

        var builder = TurnBuilder()
        var turns: [TurnRecord] = []
        var title: String?
        var summary: String?
        var session = parentSession ?? url.deletingPathExtension().lastPathComponent
        var project = ""

        func flush() {
            if let turn = builder.finish(
                tool: .claude, session: session, project: project, source: url, isSubagent: isSubagent,
                storePrompts: storePrompts
            ) {
                turns.append(turn)
            }
            builder = TurnBuilder()
        }

        let needles = [#""type":"assistant""#, #""type":"user""#, #""type":"custom-title""#, #""type":"summary""#]
        JSONLines.forEach(in: url, containingAny: needles) { entry in
            let type = entry["type"] as? String
            switch type {
            case "custom-title":
                if let value = entry["customTitle"] as? String, !value.isEmpty { title = value }
                return
            case "summary":
                if let value = entry["summary"] as? String, !value.isEmpty { summary = value }
                return
            case "user", "assistant":
                break
            default:
                return
            }

            guard let timestamp = LogTime.parse(entry["timestamp"]) else { return }
            if let cwd = entry["cwd"] as? String, !cwd.isEmpty { project = cwd }
            if parentSession == nil, let id = entry["sessionId"] as? String, !id.isEmpty { session = id }

            if type == "user" {
                if let prompt = humanPrompt(entry), !isSubagent {
                    flush()
                    builder.start(id: entry["uuid"] as? String, at: timestamp, prompt: prompt)
                } else if !builder.isStarted {
                    // Субагент: його завдання — перше «повідомлення користувача».
                    builder.start(id: entry["uuid"] as? String, at: timestamp,
                                  prompt: isSubagent ? humanPrompt(entry, any: true) : nil)
                } else if isToolResult(entry) {
                    // Службові рядки (вивід локальних команд тощо) можуть з'явитися
                    // через дні — хід вони не подовжують, лише результати інструментів.
                    builder.touch(timestamp)
                }
                return
            }

            // Відповідь асистента.
            if !builder.isStarted {
                builder.start(id: entry["uuid"] as? String, at: timestamp, prompt: nil)
            }
            builder.touch(timestamp)
            guard let message = entry["message"] as? [String: Any] else { return }
            let model = message["model"] as? String
            if let content = message["content"] as? [[String: Any]] {
                builder.toolCalls += content.reduce(0) { $0 + (($1["type"] as? String) == "tool_use" ? 1 : 0) }
            }
            guard model != "<synthetic>", let usage = message["usage"] as? [String: Any] else { return }
            var tokens = TokenUsage()
            tokens.input = usage["input_tokens"] as? Int ?? 0
            tokens.output = usage["output_tokens"] as? Int ?? 0
            tokens.cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            tokens.cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
            tokens.reasoning = (usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"] as? Int ?? 0
            // Одна відповідь розбита на кілька рядків (по блоку вмісту), і в
            // кожному повторено usage — рахуємо за ідентифікатором повідомлення.
            let key = message["id"] as? String ?? (entry["uuid"] as? String ?? UUID().uuidString)
            builder.record(call: key, model: model, tokens: tokens)
        }
        flush()

        let resolvedTitle = title ?? summary
        if let resolvedTitle {
            for index in turns.indices { turns[index].title = resolvedTitle }
        }
        return ParsedLog(turns: turns, limits: [])
    }

    private static func isToolResult(_ entry: [String: Any]) -> Bool {
        if entry["toolUseResult"] != nil { return true }
        guard let blocks = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return false }
        return blocks.contains { ($0["type"] as? String) == "tool_result" }
    }

    /// Текст запиту, якщо цей рядок — справді ваше повідомлення, а не
    /// результат інструмента, службова вставка чи вивід локальної команди.
    private static func humanPrompt(_ entry: [String: Any], any: Bool = false) -> String? {
        if entry["isMeta"] as? Bool == true || entry["isCompactSummary"] as? Bool == true { return nil }
        if entry["toolUseResult"] != nil { return nil }
        if !any, let origin = entry["origin"] as? [String: Any], let kind = origin["kind"] as? String, kind != "human" {
            return nil
        }
        guard let message = entry["message"] as? [String: Any] else { return nil }

        var text: String
        if let string = message["content"] as? String {
            text = string
        } else if let blocks = message["content"] as? [[String: Any]] {
            if blocks.contains(where: { ($0["type"] as? String) == "tool_result" }) { return nil }
            text = blocks.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
        } else {
            return nil
        }

        text = PromptText.clean(text)
        guard !text.isEmpty else { return nil }
        for prefix in ["<local-command-stdout>", "<local-command-stderr>", "<local-command-caveat>",
                       "[Request interrupted"] where text.hasPrefix(prefix) {
            return nil
        }
        // Слеш-команди записуються розміткою — лишаємо саму команду.
        if let range = text.range(of: "<command-name>"),
           let end = text.range(of: "</command-name>", range: range.upperBound..<text.endIndex) {
            return String(text[range.upperBound..<end.lowerBound])
        }
        return text
    }
}

// MARK: - Codex

/// Журнали Codex: `~/.codex/sessions/РРРР/ММ/ДД/rollout-*.jsonl`. Межі
/// ходу — події `task_started` і `task_complete`/`turn_aborted`, токени —
/// накопичувальні `total_token_usage` з подій `token_count`.
enum CodexLogParser {
    static func parse(_ url: URL, titles: [String: String], storePrompts: Bool) -> ParsedLog {
        var result = ParsedLog()
        var session = String(url.deletingPathExtension().lastPathComponent.suffix(36))
        var project = ""
        var model: String?

        var builder = TurnBuilder()
        var turnModel: String?
        var lastTotal = TokenUsage()
        var turnStartTotal = TokenUsage()
        var lastLimit: [String: (Double, Double?)] = [:]

        func flush() {
            guard builder.isStarted else { return }
            var delta = lastTotal - turnStartTotal
            // Лічильник почався заново (сесію перезапустили) — беремо все, що є.
            if delta.isNegative { delta = lastTotal }
            builder.setTokens(delta, model: turnModel ?? model)
            if let turn = builder.finish(
                tool: .codex, session: session, project: project, source: url, isSubagent: false,
                storePrompts: storePrompts
            ) {
                result.turns.append(turn)
            }
            builder = TurnBuilder()
        }

        let needles = ["\"token_count\"", "\"task_started\"", "\"task_complete\"", "\"turn_aborted\"",
                       "\"turn_context\"", "\"session_meta\"", "\"role\":\"user\"", "\"function_call\"",
                       "\"custom_tool_call\"", "\"web_search_call\""]
        JSONLines.forEach(in: url, containingAny: needles) { entry in
            guard let timestamp = LogTime.parse(entry["timestamp"]),
                  let payload = entry["payload"] as? [String: Any]
            else { return }

            switch entry["type"] as? String {
            case "session_meta":
                if let id = payload["id"] as? String, !id.isEmpty { session = id }
                if let cwd = payload["cwd"] as? String, !cwd.isEmpty { project = cwd }
            case "turn_context":
                if let cwd = payload["cwd"] as? String, !cwd.isEmpty { project = cwd }
                if let value = payload["model"] as? String, !value.isEmpty {
                    model = value
                    if builder.isStarted { turnModel = value }
                }
            case "event_msg":
                switch payload["type"] as? String {
                case "task_started":
                    flush()
                    builder.start(id: payload["turn_id"] as? String, at: timestamp, prompt: nil)
                    turnStartTotal = lastTotal
                    turnModel = nil
                case "task_complete", "turn_aborted":
                    builder.touch(timestamp)
                    flush()
                case "token_count":
                    builder.touch(timestamp)
                    if let info = payload["info"] as? [String: Any],
                       let total = info["total_token_usage"] as? [String: Any] {
                        let usage = tokens(from: total)
                        if usage != lastTotal, builder.isStarted { builder.apiCalls += 1 }
                        lastTotal = usage
                    }
                    if let limits = payload["rate_limits"] as? [String: Any] {
                        for key in ["primary", "secondary"] {
                            guard let window = limits[key] as? [String: Any],
                                  let minutes = window["window_minutes"] as? Int,
                                  let percent = (window["used_percent"] as? NSNumber)?.doubleValue
                            else { continue }
                            let label = LimitWindow.label(forWindowMinutes: minutes)
                            let resets = (window["resets_at"] as? NSNumber)?.doubleValue
                            if let previous = lastLimit[label], previous.0 == percent, previous.1 == resets { continue }
                            lastLimit[label] = (percent, resets)
                            result.limits.append(LimitSample(
                                tool: .codex, label: label, at: timestamp, percent: percent,
                                resetsAt: resets.map { Date(timeIntervalSince1970: $0) }
                            ))
                        }
                    }
                default:
                    break
                }
            case "response_item":
                guard builder.isStarted else { return }
                builder.touch(timestamp)
                switch payload["type"] as? String {
                case "message":
                    guard payload["role"] as? String == "user", builder.prompt == nil,
                          let content = payload["content"] as? [[String: Any]]
                    else { return }
                    let text = PromptText.clean(content.compactMap { $0["text"] as? String }.joined(separator: "\n"))
                    // Службові вставки (контекст середовища тощо) — у кутових дужках.
                    if !text.isEmpty, !text.hasPrefix("<") { builder.prompt = text }
                case "function_call", "custom_tool_call", "web_search_call":
                    builder.toolCalls += 1
                default:
                    break
                }
            default:
                break
            }
        }
        flush()

        if let title = titles[session], !title.isEmpty {
            for index in result.turns.indices { result.turns[index].title = title }
        }
        return result
    }

    private static func tokens(from usage: [String: Any]) -> TokenUsage {
        let input = usage["input_tokens"] as? Int ?? 0
        let cached = usage["cached_input_tokens"] as? Int ?? 0
        return TokenUsage(
            input: max(0, input - cached),
            output: usage["output_tokens"] as? Int ?? 0,
            cacheRead: cached,
            cacheWrite: usage["cache_write_input_tokens"] as? Int ?? 0,
            reasoning: usage["reasoning_output_tokens"] as? Int ?? 0
        )
    }
}

// MARK: - Текст запиту

enum PromptText {
    private static let injected = try! NSRegularExpression(
        pattern: "<(system-reminder|ide_[a-z_]+|environment_context)>[\\s\\S]*?</\\1>"
    )

    /// Прибирає службові вставки, які агенти дописують до вашого повідомлення.
    static func clean(_ raw: String) -> String {
        var text = raw
        // Розширення Codex для IDE додає контекст редактора, а сам запит — після цієї позначки.
        if let marker = text.range(of: "## My request for Codex:") {
            text = String(text[marker.upperBound...])
        }
        let range = NSRange(text.startIndex..., in: text)
        text = injected.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Збирання ходу

/// Накопичує один хід, поки йде розбір журналу.
struct TurnBuilder {
    private(set) var isStarted = false
    private var id: String?
    private var started = Date.distantPast
    private var ended = Date.distantPast
    /// Час, коли агент справді працював: паузи довші за `idleGap` (хід
    /// чекав вашої відповіді, сесію відклали на завтра) не рахуються.
    private var active: TimeInterval = 0
    var prompt: String?
    var apiCalls = 0
    var toolCalls = 0
    private var calls: [String: (model: String?, tokens: TokenUsage)] = [:]
    private var fixedTokens: TokenUsage?
    private var fixedModel: String?

    mutating func start(id: String?, at date: Date, prompt: String?) {
        isStarted = true
        self.id = id
        started = date
        ended = date
        active = 0
        self.prompt = prompt
    }

    static let idleGap: TimeInterval = 30 * 60

    mutating func touch(_ date: Date) {
        guard date > ended else { return }
        let gap = date.timeIntervalSince(ended)
        if gap <= Self.idleGap { active += gap }
        ended = date
    }

    mutating func record(call: String, model: String?, tokens: TokenUsage) {
        calls[call] = (model, tokens)
    }

    mutating func setTokens(_ tokens: TokenUsage, model: String?) {
        fixedTokens = tokens
        fixedModel = model
    }

    func finish(tool: Tool, session: String, project: String, source: URL, isSubagent: Bool,
                storePrompts: Bool) -> TurnRecord? {
        guard isStarted else { return nil }

        let tokens = fixedTokens ?? calls.values.reduce(TokenUsage()) { $0 + $1.tokens }
        let callCount = fixedTokens == nil ? calls.count : apiCalls
        // Хід без жодного звернення до моделі — локальна команда чи скасування.
        guard callCount > 0 || tokens.output > 0 else { return nil }

        // Модель ходу — та, що згенерувала найбільше.
        var byModel: [String: Int] = [:]
        for call in calls.values {
            guard let model = call.model else { continue }
            byModel[model, default: 0] += call.tokens.output + 1
        }
        let model = fixedModel ?? byModel.max { $0.value < $1.value }?.key

        // Відгалужена чи продовжена сесія Claude копіює історію в новий файл
        // з тими самими ідентифікаторами повідомлень — тож ключ ходу не
        // залежить від файлу, і копія замінює оригінал замість дубля.
        let key: String
        if let id, !isSubagent {
            key = id
        } else {
            key = "\(source.lastPathComponent):\(id ?? String(Int(started.timeIntervalSince1970 * 1000)))"
        }
        return TurnRecord(
            id: "\(tool.rawValue):\(key)",
            tool: tool,
            session: session,
            project: project,
            title: nil,
            model: model,
            started: started,
            ended: ended,
            active: active,
            prompt: storePrompts ? prompt.map { String($0.prefix(2000)) } : nil,
            apiCalls: callCount,
            toolCalls: toolCalls,
            tokens: tokens,
            isSubagent: isSubagent
        )
    }
}
