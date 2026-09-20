import SwiftUI
import Security
import CryptoKit
import AuthenticationServices
import GoogleSignIn

// MARK: - Keychain
enum Keychain {
    static func set(_ data: Data, key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var a = q
        a[kSecValueData as String] = data
        a[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(a as CFDictionary, nil)
    }
    static func get(_ key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess else { return nil }
        return r as? Data
    }
}

// MARK: - Wallet
final class WalletStore: ObservableObject {
    @Published private(set) var cards: [Card] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published var preferredID: UUID?
    private var uid = ""

    func load(userID: String?) {
        guard let userID else { cards = []; transactions = []; uid = ""; return }
        uid = userID
        cards = read("cards")
        transactions = read("tx")
    }
    private func read<T: Codable>(_ k: String) -> [T] {
        guard let d = Keychain.get("\(uid).\(k)"), let v = try? JSONDecoder().decode([T].self, from: d) else { return [] }
        return v
    }
    private func save() {
        guard !uid.isEmpty else { return }
        if let d = try? JSONEncoder().encode(cards) { Keychain.set(d, key: "\(uid).cards") }
        if let d = try? JSONEncoder().encode(transactions) { Keychain.set(d, key: "\(uid).tx") }
    }
    func add(_ c: Card) { cards.append(c); save() }
    func remove(_ c: Card) { cards.removeAll { $0.id == c.id }; save() }
    func pay(card: Card, merchant: String, amount: Double) {
        transactions.insert(Transaction(cardID: card.id, brand: card.brand, last4: card.last4,
                                        merchant: merchant, amount: amount, date: Date()), at: 0)
        save()
    }
    func deleteAll() { cards = []; transactions = []; save() }
    func monthTx(_ d: Date) -> [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: d, toGranularity: .month) }
    }
    var spentThisMonth: Double { monthTx(Date()).reduce(0) { $0 + $1.amount } }
}

// MARK: - Auth
enum GoogleConfig {
    /// Wklej tu iOS Client ID z Google Cloud Console (np. 123-abc.apps.googleusercontent.com)
    static let clientID = ""
}

struct AppUser: Codable, Equatable {
    var key: String
    var email: String
    var name: String
    var birth: Date
    var provider: String
    var age: Int { AuthStore.age(birth) }
}
private struct Account: Codable { var user: AppUser; var salt: String?; var hash: String? }

enum AuthError: LocalizedError {
    case msg(String)
    var errorDescription: String? { if case .msg(let m) = self { return m }; return nil }
}

final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

final class AuthStore: ObservableObject {
    static let minAge = 13
    @Published var user: AppUser?
    @Published var pendingUser: AppUser?
    private var expectedCode = ""
    private let presenter = WebAuthPresenter()

    private var accounts: [String: Account] {
        get { Keychain.get("accounts").flatMap { try? JSONDecoder().decode([String: Account].self, from: $0) } ?? [:] }
        set { if let d = try? JSONEncoder().encode(newValue) { Keychain.set(d, key: "accounts") } }
    }

    init() {
        if let k = UserDefaults.standard.string(forKey: "session"), let a = accounts[k] { user = a.user }
    }

    static func age(_ birth: Date) -> Int {
        Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
    }

    private func hash(_ pw: String, salt: String) -> String {
        var d = Data((salt + pw).utf8)
        for _ in 0..<20_000 { d = Data(SHA256.hash(data: d)) }
        return d.map { String(format: "%02x", $0) }.joined()
    }

    private func start(_ u: AppUser) {
        UserDefaults.standard.set(u.key, forKey: "session")
        user = u
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: "session")
        user = nil
    }

    func register(name: String, email: String, password: String, birth: Date) throws {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard e.contains("@"), e.contains(".") else { throw AuthError.msg("Podaj poprawny adres e-mail.") }
        guard password.count >= 8 else { throw AuthError.msg("Hasło musi mieć co najmniej 8 znaków.") }
        guard Self.age(birth) >= Self.minAge else { throw AuthError.msg("Aplikacja jest dostępna od 13. roku życia.") }
        let key = "email:" + e
        guard accounts[key] == nil else { throw AuthError.msg("Konto z tym adresem już istnieje.") }
        let salt = UUID().uuidString
        let u = AppUser(key: key, email: e, name: name.isEmpty ? e : name, birth: birth, provider: "email")
        accounts[key] = Account(user: u, salt: salt, hash: hash(password, salt: salt))
        
        expectedCode = String(format: "%06d", Int.random(in: 100000...999999))
        print("Wysłano kod e-mail do \(e): \(expectedCode)") // Mock wysyłania e-maila
        pendingUser = u
    }

    func verify(_ code: String) throws {
        guard code == expectedCode else { throw AuthError.msg("Nieprawidłowy kod weryfikacyjny.") }
        if let u = pendingUser {
            start(u)
            pendingUser = nil
            expectedCode = ""
        }
    }
    
    func cancelVerification() {
        if let u = pendingUser {
            accounts.removeValue(forKey: u.key)
            pendingUser = nil
            expectedCode = ""
        }
    }

    func login(email: String, password: String) throws {
        let key = "email:" + email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let a = accounts[key], let salt = a.salt, a.hash == hash(password, salt: salt) else {
            throw AuthError.msg("Nieprawidłowy e-mail lub hasło.")
        }
        start(a.user)
    }

    func social(provider: String, id: String, email: String, name: String, birth: Date) throws {
        let key = provider + ":" + id
        if let a = accounts[key] { start(a.user); return }
        guard Self.age(birth) >= Self.minAge else { throw AuthError.msg("Aplikacja jest dostępna od 13. roku życia.") }
        let u = AppUser(key: key, email: email, name: name, birth: birth, provider: provider)
        accounts[key] = Account(user: u)
        start(u)
    }

    @MainActor
    func handleApple(birth: Date) async throws {
        let result = try await SignInWithAppleHelper.shared.startSignInWithAppleFlow()
        try social(provider: "apple", id: String(result.token.prefix(30)), email: "Użytkownik Apple",
                   name: "Użytkownik Apple", birth: birth)
    }

    @MainActor
    func googleSignIn(birth: Date) async throws {
        let cid = GoogleConfig.clientID
        guard !cid.isEmpty else {
            throw AuthError.msg("Logowanie Google: wpisz Client ID w pliku Stores.swift (GoogleConfig).")
        }
        
        let config = GIDConfiguration(clientID: cid)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            throw AuthError.msg("Nie można znaleźć kontrolera bazowego.")
        }
        
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { signInResult, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let user = signInResult?.user else {
                    cont.resume(throwing: AuthError.msg("Brak użytkownika Google."))
                    return
                }
                do {
                    try self.social(provider: "google", id: user.userID ?? UUID().uuidString,
                                    email: user.profile?.email ?? "", name: user.profile?.name ?? "Użytkownik Google", birth: birth)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
