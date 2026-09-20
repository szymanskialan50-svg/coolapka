import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var title: String { self == .dark ? "Czarny" : "Jasny" }
    var scheme: ColorScheme { self == .dark ? .dark : .light }
}

enum CardBrand: String, Codable {
    case visa = "Visa", mastercard = "Mastercard", amex = "American Express"
    case discover = "Discover", maestro = "Maestro", jcb = "JCB"
    case diners = "Diners Club", unionpay = "UnionPay", unknown = "Karta"

    /// Rozpoznaje typ karty po pierwszych cyfrach (BIN).
    static func detect(_ raw: String) -> CardBrand {
        let d = raw.filter(\.isNumber)
        guard !d.isEmpty else { return .unknown }
        func pre(_ n: Int) -> Int { d.count >= n ? (Int(d.prefix(n)) ?? -1) : -1 }
        if d.hasPrefix("4") { return .visa }
        if (51...55).contains(pre(2)) || (2221...2720).contains(pre(4)) { return .mastercard }
        if [34, 37].contains(pre(2)) { return .amex }
        if d.hasPrefix("6011") || pre(2) == 65 || (644...649).contains(pre(3)) { return .discover }
        if pre(2) == 62 { return .unionpay }
        if (3528...3589).contains(pre(4)) { return .jcb }
        if (300...305).contains(pre(3)) || [36, 38, 39].contains(pre(2)) { return .diners }
        if pre(2) == 50 || (56...69).contains(pre(2)) { return .maestro }
        return .unknown
    }

    var colors: [Color] {
        switch self {
        case .visa: return [Color(hex: 0x1A1F71), Color(hex: 0x4C6FFF)]
        case .mastercard: return [Color(hex: 0x2B2B33), Color(hex: 0xF0562B)]
        case .amex: return [Color(hex: 0x0B6E6E), Color(hex: 0x37C6B8)]
        case .discover: return [Color(hex: 0xD35400), Color(hex: 0xF5A623)]
        case .maestro: return [Color(hex: 0x4A148C), Color(hex: 0xE040FB)]
        case .jcb: return [Color(hex: 0x0D47A1), Color(hex: 0x00C853)]
        case .diners: return [Color(hex: 0x37474F), Color(hex: 0x90A4AE)]
        case .unionpay: return [Color(hex: 0xB71C1C), Color(hex: 0x1565C0)]
        case .unknown: return [Color(hex: 0x232526), Color(hex: 0x5C6470)]
        }
    }
}

struct Card: Identifiable, Codable, Equatable {
    var id = UUID()
    var holder: String
    var number: String
    var expiry: String
    var brand: CardBrand { CardBrand.detect(number) }
    var last4: String { String(number.suffix(4)) }

    static func group(_ n: String) -> String {
        let d = n.filter(\.isNumber)
        let sizes = (d.hasPrefix("34") || d.hasPrefix("37")) ? [4, 6, 5] : [4, 4, 4, 4, 4]
        var out: [String] = []
        var i = d.startIndex
        for s in sizes {
            guard i < d.endIndex else { break }
            let e = d.index(i, offsetBy: s, limitedBy: d.endIndex) ?? d.endIndex
            out.append(String(d[i..<e]))
            i = e
        }
        return out.joined(separator: " ")
    }
}

struct Transaction: Identifiable, Codable {
    var id = UUID()
    var cardID: UUID
    var brand: CardBrand
    var last4: String
    var merchant: String
    var amount: Double
    var date: Date
}

func luhnValid(_ n: String) -> Bool {
    let d = n.filter(\.isNumber).compactMap { $0.wholeNumberValue }
    guard d.count >= 13 else { return false }
    var sum = 0
    for (i, v) in d.reversed().enumerated() {
        var x = v
        if i % 2 == 1 { x *= 2; if x > 9 { x -= 9 } }
        sum += x
    }
    return sum % 10 == 0
}

func expiryValid(_ s: String) -> Bool {
    let p = s.split(separator: "/")
    guard p.count == 2, let m = Int(p[0]), let y = Int(p[1]), (1...12).contains(m) else { return false }
    let c = Calendar.current.dateComponents([.year, .month], from: Date())
    let cy = (c.year ?? 2026) % 100
    return y > cy || (y == cy && m >= (c.month ?? 1))
}
