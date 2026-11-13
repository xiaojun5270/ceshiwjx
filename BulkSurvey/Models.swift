import Foundation

// MARK: - 一条待提交名单

struct SurveyEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = ""
    var jobNo: String = ""
    var email: String = ""
}

// MARK: - 单条状态

enum EntryStatus: String, Codable {
    case pending = "待提交"
    case running = "提交中"
    case success = "成功"
    case failed  = "失败"
    case blocked = "需人工"
}

// MARK: - 运行记录

struct RunRecord: Identifiable, Codable {
    var id = UUID()
    var name: String
    var jobNo: String
    var email: String
    var status: EntryStatus
    var note: String
    var time: Date = Date()
}

// MARK: - 运行参数

struct RunConfig: Codable {
    var url: String = "https://v.wjx.cn/vm/tghWxdt.aspx"
    var minDelay: Double = 8          // 两条之间最短间隔（秒）
    var maxDelay: Double = 20         // 两条之间最长间隔（秒）
    var perEntryTimeout: Double = 70  // 单条最长等待（秒）
    var stopOnCaptcha: Bool = true    // 遇到验证就暂停等人处理
    var maxRetry: Int = 1             // 单条失败后重试次数

    static func load() -> RunConfig {
        if let data = UserDefaults.standard.data(forKey: "RunConfig"),
           let cfg = try? JSONDecoder().decode(RunConfig.self, from: data) {
            return cfg
        }
        return RunConfig()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "RunConfig")
        }
    }
}

// MARK: - 名单解析（姓名 / 工号 / 邮箱）

enum EntryParser {

    static func parse(_ text: String) -> [SurveyEntry] {
        var result: [SurveyEntry] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }

            let cols = split(line)

            // 跳过表头
            if isHeader(cols) { continue }

            var e = SurveyEntry()
            switch cols.count {
            case 0:
                continue
            case 1:
                e.name = cols[0]
            case 2:
                // 常见两种写法：姓名,工号  或  工号,姓名
                if looksLikeID(cols[0]) && !looksLikeID(cols[1]) {
                    e.jobNo = cols[0]
                    e.name  = cols[1]
                } else {
                    e.name  = cols[0]
                    e.jobNo = cols[1]
                }
            default:
                e.name  = cols[0]
                e.jobNo = cols[1]
                e.email = cols[2]
            }

            if e.name.isEmpty && e.jobNo.isEmpty && e.email.isEmpty { continue }
            result.append(e)
        }
        return result
    }

    private static func split(_ line: String) -> [String] {
        let separators: [Character] = ["\t", ",", "，", ";", "；", "|", "｜"]
        for sep in separators where line.contains(sep) {
            return line.split(separator: sep, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        // 没有明确分隔符：按空白切（仅在切成 2~3 段时采用）
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "　" })
            .map(String.init)
            .filter { !$0.isEmpty }
        if parts.count >= 2 && parts.count <= 3 { return parts }
        return [line]
    }

    private static func isHeader(_ cols: [String]) -> Bool {
        guard !cols.isEmpty else { return false }
        let joined = cols.joined()
        let hasName  = joined.contains("姓名") || joined.lowercased().contains("name")
        let hasJob   = joined.contains("工号") || joined.contains("编号") || joined.lowercased().contains("id")
        let hasEmail = joined.contains("邮箱") || joined.lowercased().contains("mail")
        return (hasName && hasJob) || (hasEmail && (hasName || hasJob))
    }

    static func looksLikeID(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        let hasDigit = s.contains(where: { $0.isNumber })
        let hasHan   = s.contains(where: { isHan($0) })
        return hasDigit && !hasHan
    }

    private static func isHan(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v)
    }
}
