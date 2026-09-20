import SwiftUI

@main
struct PayWalletApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var wallet = WalletStore()
    @AppStorage("theme") private var theme = AppTheme.dark.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(wallet)
                .preferredColorScheme(AppTheme(rawValue: theme)?.scheme)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wallet: WalletStore

    var body: some View {
        Group {
            if auth.user != nil { MainTabs().transition(.opacity) }
            else if auth.pendingUser != nil { VerificationView().transition(.opacity) }
            else { AuthView().transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.user?.key)
        .task(id: auth.user?.key) { wallet.load(userID: auth.user?.key) }
    }
}

struct MainTabs: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab).tabItem { Label("Portfel", systemImage: "creditcard.fill") }.tag(0)
            PayView().tabItem { Label("Zapłać", systemImage: "wave.3.right.circle.fill") }.tag(1)
            HistoryView().tabItem { Label("Historia", systemImage: "clock.arrow.circlepath") }.tag(2)
            SettingsView().tabItem { Label("Ustawienia", systemImage: "gearshape.fill") }.tag(3)
        }
    }
}
