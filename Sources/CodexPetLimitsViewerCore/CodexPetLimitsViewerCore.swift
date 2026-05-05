import AppKit
import Foundation
import SQLite3

public struct LimitBucket: Equatable {
    public let name: String
    public let percentRemaining: Double?
    public let resetText: String?

    public init(name: String, percentRemaining: Double?, resetText: String?) {
        self.name = name
        self.percentRemaining = percentRemaining
        self.resetText = resetText
    }

    public var displayLine: String {
        guard let percentRemaining else {
            return "\(name.padding(toLength: 6, withPad: " ", startingAt: 0))unavailable"
        }

        let percent = Int((percentRemaining * 100).rounded())
        var line = "\(name.padding(toLength: 6, withPad: " ", startingAt: 0))\(percent)% left"
        if let resetText, !resetText.isEmpty {
            line += "    resets \(resetText)"
        }
        return line
    }
}

public struct LimitState {
    public var fiveHour: LimitBucket
    public var weekly: LimitBucket
    public var source: String
    public var refreshedAt: Date

    public init(fiveHour: LimitBucket, weekly: LimitBucket, source: String, refreshedAt: Date) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.source = source
        self.refreshedAt = refreshedAt
    }

    public static let unavailable = LimitState(
        fiveHour: LimitBucket(name: "5h", percentRemaining: nil, resetText: nil),
        weekly: LimitBucket(name: "Week", percentRemaining: nil, resetText: nil),
        source: "Unavailable",
        refreshedAt: Date()
    )
}

public struct HoverGate {
    public let hoverDelay: TimeInterval
    public let movementSettleDelay: TimeInterval

    private var enteredAt: TimeInterval?
    private var lastMovementAt: TimeInterval?
    private var lastFrame: CGRect?

    public init(hoverDelay: TimeInterval = 0.55, movementSettleDelay: TimeInterval = 0.20) {
        self.hoverDelay = hoverDelay
        self.movementSettleDelay = movementSettleDelay
    }

    public mutating func update(now: TimeInterval, pointer: CGPoint, petFrame: CGRect?, mouseDown: Bool) -> Bool {
        guard let petFrame else {
            reset()
            return false
        }

        if let lastFrame, !lastFrame.equalTo(petFrame) {
            lastMovementAt = now
            enteredAt = nil
        }
        lastFrame = petFrame

        guard !mouseDown, petFrame.contains(pointer) else {
            enteredAt = nil
            return false
        }

        if let lastMovementAt, now - lastMovementAt < movementSettleDelay {
            enteredAt = nil
            return false
        }

        if enteredAt == nil {
            enteredAt = now
            return false
        }

        return now - (enteredAt ?? now) >= hoverDelay
    }

    private mutating func reset() {
        enteredAt = nil
        lastMovementAt = nil
        lastFrame = nil
    }
}

public enum LimitPopoverPlacer {
    public static let inset: CGFloat = 8
    public static let spacing: CGFloat = 8

    public static func origin(for size: CGSize, near petFrame: CGRect, in screenFrame: CGRect) -> CGPoint {
        var x = petFrame.midX - size.width / 2
        var y = petFrame.maxY + spacing

        if y + size.height > screenFrame.maxY - inset {
            y = petFrame.minY - size.height - spacing
        }

        x = min(max(x, screenFrame.minX + inset), screenFrame.maxX - size.width - inset)
        y = min(max(y, screenFrame.minY + inset), screenFrame.maxY - size.height - inset)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}

public enum PetFrameMapper {
    public static func appKitFrame(from rawFrame: CGRect, screens: [CGRect]) -> CGRect {
        guard !screens.isEmpty else { return rawFrame }
        if screens.contains(where: { $0.intersects(rawFrame) || $0.contains(rawFrame) }) {
            return rawFrame
        }

        let xMatchedScreens = screens.filter {
            rawFrame.midX >= $0.minX && rawFrame.midX <= $0.maxX
        }

        for screen in xMatchedScreens {
            guard rawFrame.minY < 0 else { continue }
            let localTopY = rawFrame.minY + screen.height
            let mappedY = screen.maxY - localTopY - rawFrame.height
            let mapped = CGRect(x: rawFrame.minX, y: mappedY, width: rawFrame.width, height: rawFrame.height)
            if screen.intersects(mapped) || screen.contains(mapped) {
                return mapped
            }
        }

        return rawFrame
    }
}

public final class PetStateReader {
    private let globalStatePath: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.globalStatePath = homeDirectory
            .appendingPathComponent(".codex")
            .appendingPathComponent(".codex-global-state.json")
    }

    public func readPetFrame() -> CGRect? {
        guard
            let data = try? Data(contentsOf: globalStatePath),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            isOverlayOpen(root),
            let bounds = root["electron-avatar-overlay-bounds"] as? [String: Any],
            let mascot = bounds["mascot"] as? [String: Any],
            let x = number(bounds["x"]),
            let y = number(bounds["y"]),
            let left = number(mascot["left"]),
            let top = number(mascot["top"]),
            let width = number(mascot["width"]),
            let height = number(mascot["height"])
        else {
            return nil
        }

        let rawFrame = CGRect(x: x + left, y: y + top, width: width, height: height)
        return PetFrameMapper.appKitFrame(from: rawFrame, screens: NSScreen.screens.map(\.frame))
    }

    private func isOverlayOpen(_ root: [String: Any]) -> Bool {
        if let value = root["electron-avatar-overlay-open"] as? Bool {
            return value
        }
        if let value = root["electron-avatar-overlay-open"] as? NSNumber {
            return value.boolValue
        }
        return true
    }

    private func number(_ value: Any?) -> CGFloat? {
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        return nil
    }
}

public final class LimitStateReader {
    private let homeDirectory: URL
    private let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func readCurrent(completion: @escaping (LimitState) -> Void) {
        readLive { [weak self] live in
            if let live {
                completion(live)
                return
            }
            completion(self?.readCached() ?? .unavailable)
        }
    }

    public func readCached() -> LimitState {
        let dbPath = homeDirectory
            .appendingPathComponent(".codex")
            .appendingPathComponent("logs_2.sqlite")
            .path

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return .unavailable
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT feedback_log_body FROM logs
        WHERE feedback_log_body LIKE '%"type":"codex.rate_limits"%'
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return .unavailable
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            let text = String(cString: cString)
            if let state = parseLooseText(text, source: "Cached") {
                return state
            }
        }

        return .unavailable
    }

    private func readLive(completion: @escaping (LimitState?) -> Void) {
        guard let token = readAccessToken() else {
            completion(nil)
            return
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 3
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { data, response, _ in
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                let data,
                let state = self.parseUsageJSON(data, source: "Live")
            else {
                completion(nil)
                return
            }
            completion(state)
        }.resume()
    }

    private func readAccessToken() -> String? {
        let path = homeDirectory
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")
        guard
            let data = try? Data(contentsOf: path),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let token = tokens["access_token"] as? String,
            !token.isEmpty
        else {
            return nil
        }
        return token
    }

    public func parseUsageJSON(_ data: Data, source: String) -> LimitState? {
        if let payload = try? JSONDecoder().decode(UsagePayload.self, from: data),
           let state = state(from: payload, source: source) {
            return state
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return parseJSONObject(json, source: source)
    }

    private struct UsagePayload: Decodable {
        var rate_limit: RatePayload?
    }

    private struct EventPayload: Decodable {
        var rate_limits: RatePayload?
    }

    private struct RatePayload: Decodable {
        var primary: BucketPayload?
        var secondary: BucketPayload?
        var primary_window: BucketPayload?
        var secondary_window: BucketPayload?
    }

    private struct BucketPayload: Decodable {
        var used_percent: Double?
        var reset_at: Double?
    }

    private func state(from payload: UsagePayload, source: String) -> LimitState? {
        state(from: payload.rate_limit, source: source)
    }

    private func state(from payload: EventPayload, source: String) -> LimitState? {
        state(from: payload.rate_limits, source: source)
    }

    private func state(from rateLimit: RatePayload?, source: String) -> LimitState? {
        guard let rateLimit else { return nil }
        let primary = rateLimit.primary ?? rateLimit.primary_window
        let secondary = rateLimit.secondary ?? rateLimit.secondary_window

        guard primary != nil || secondary != nil else { return nil }
        return LimitState(
            fiveHour: bucket(from: primary, name: "5h"),
            weekly: bucket(from: secondary, name: "Week"),
            source: source,
            refreshedAt: Date()
        )
    }

    private func bucket(from payload: BucketPayload?, name: String) -> LimitBucket {
        guard let payload, let usedPercent = payload.used_percent else {
            return LimitBucket(name: name, percentRemaining: nil, resetText: nil)
        }
        let remaining = max(0, min(1, (100 - usedPercent) / 100))
        let reset = payload.reset_at.map {
            Self.shortResetFormatter.string(from: Date(timeIntervalSince1970: $0))
        }
        return LimitBucket(name: name, percentRemaining: remaining, resetText: reset)
    }

    private func parseJSONObject(_ object: Any, source: String) -> LimitState? {
        let candidates = flattenDictionaries(object)
        var fiveHour: LimitBucket?
        var weekly: LimitBucket?

        for dictionary in candidates {
            let haystack = dictionary.map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
                .lowercased()
            let bucket = bucket(from: dictionary)

            if fiveHour == nil, haystack.contains("5h") || haystack.contains("5_hour") || haystack.contains("five_hour") {
                fiveHour = LimitBucket(name: "5h", percentRemaining: bucket.percent, resetText: bucket.reset)
            }
            if weekly == nil, haystack.contains("weekly") || haystack.contains("week") {
                weekly = LimitBucket(name: "Week", percentRemaining: bucket.percent, resetText: bucket.reset)
            }
        }

        guard fiveHour != nil || weekly != nil else { return nil }
        return LimitState(
            fiveHour: fiveHour ?? LimitBucket(name: "5h", percentRemaining: nil, resetText: nil),
            weekly: weekly ?? LimitBucket(name: "Week", percentRemaining: nil, resetText: nil),
            source: source,
            refreshedAt: Date()
        )
    }

    private func flattenDictionaries(_ object: Any) -> [[String: Any]] {
        if let dictionary = object as? [String: Any] {
            var result = [dictionary]
            for value in dictionary.values {
                result.append(contentsOf: flattenDictionaries(value))
            }
            return result
        }
        if let array = object as? [Any] {
            return array.flatMap { flattenDictionaries($0) }
        }
        return []
    }

    private func bucket(from dictionary: [String: Any]) -> (percent: Double?, reset: String?) {
        let lower = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
        let percent = firstNumber(in: lower, keys: [
            "remaining_percent", "remainingpercent", "percent_remaining", "percentremaining",
            "remaining_pct", "remainingpct", "remaining"
        ]).map(normalizedPercent)

        let computed = percent ?? computedRemainingPercent(from: lower)
        let reset = firstString(in: lower, keys: [
            "reset_at", "resetat", "resets_at", "resetsat", "reset_time", "resettime", "next_reset"
        ]).flatMap(formatReset)

        return (computed, reset)
    }

    private func computedRemainingPercent(from dictionary: [String: Any]) -> Double? {
        guard
            let used = firstNumber(in: dictionary, keys: ["used", "consumed", "usage"]),
            let limit = firstNumber(in: dictionary, keys: ["limit", "total", "quota"]),
            limit > 0
        else {
            return nil
        }
        return max(0, min(1, 1 - used / limit))
    }

    private func firstNumber(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let number = value as? NSNumber { return number.doubleValue }
            if let string = value as? String, let double = Double(string) { return double }
        }
        return nil
    }

    private func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return nil
    }

    private func normalizedPercent(_ value: Double) -> Double {
        let normalized = value > 1 ? value / 100 : value
        return max(0, min(1, normalized))
    }

    private func formatReset(_ raw: String) -> String? {
        if let seconds = TimeInterval(raw) {
            let date = Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
            return Self.shortResetFormatter.string(from: date)
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            return Self.shortResetFormatter.string(from: date)
        }
        return raw.isEmpty ? nil : raw
    }

    private func parseLooseText(_ text: String, source: String) -> LimitState? {
        if let json = extractRateLimitJSON(from: text),
           let data = json.data(using: .utf8),
           let payload = try? JSONDecoder().decode(EventPayload.self, from: data),
           let state = state(from: payload, source: source) {
            return state
        }

        let five = looseBucket(named: "5h", patterns: ["5h", "5_hour", "five_hour"], in: text)
        let week = looseBucket(named: "Week", patterns: ["weekly", "week"], in: text)
        guard five.percentRemaining != nil || week.percentRemaining != nil else { return nil }
        return LimitState(fiveHour: five, weekly: week, source: source, refreshedAt: Date())
    }

    private func extractRateLimitJSON(from body: String) -> String? {
        guard let start = body.range(of: "{\"type\":\"codex.rate_limits\"")?.lowerBound else {
            return nil
        }

        var depth = 0
        var inString = false
        var escaping = false
        var index = start

        while index < body.endIndex {
            let char = body[index]
            if inString {
                if escaping {
                    escaping = false
                } else if char == "\\" {
                    escaping = true
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
            } else if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(body[start...index])
                }
            }
            index = body.index(after: index)
        }

        return nil
    }

    private func looseBucket(named name: String, patterns: [String], in text: String) -> LimitBucket {
        let lower = text.lowercased()
        guard patterns.contains(where: { lower.contains($0) }) else {
            return LimitBucket(name: name, percentRemaining: nil, resetText: nil)
        }

        let percent = firstRegexNumber(in: text, patterns: [
            #""remaining_percent"\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
            #""remainingPercent"\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
            #""percent_remaining"\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
            #"remaining[^0-9]{0,18}([0-9]+(?:\.[0-9]+)?)\s*%"#
        ]).map(normalizedPercent)

        return LimitBucket(name: name, percentRemaining: percent, resetText: nil)
    }

    private func firstRegexNumber(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard
                let match = regex.firstMatch(in: text, range: range),
                match.numberOfRanges > 1,
                let valueRange = Range(match.range(at: 1), in: text),
                let value = Double(text[valueRange])
            else {
                continue
            }
            return value
        }
        return nil
    }

    private static let shortResetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
