import SwiftUI
import LocalAuthentication

private func brandBadge(_ b: CardBrand) -> some View {
    ZStack {
        Circle().fill(LinearGradient(colors: b.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        Image(systemName: "creditcard.fill").font(.footnote).foregroundColor(.white)
    }.frame(width: 38, height: 38)
}

// MARK: - Portfel
struct HomeView: View {
    @EnvironmentObject var wallet: WalletStore
    @AppStorage("currency") private var currency = "PLN"
    @Binding var tab: Int
    @State private var selected: UUID?
    @State private var showAdd = false
    @State private var toDelete: Card?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if wallet.cards.isEmpty { empty } else { stack; details }
                    summary
                }.padding(.vertical)
            }
            .navigationTitle("Portfel")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
            }
            .sheet(isPresented: $showAdd) { AddCardView() }
            .confirmationDialog("Usunąć kartę?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
                Button("Usuń", role: .destructive) {
                    if let c = toDelete { withAnimation(.spring()) { wallet.remove(c); selected = nil } }
                    toDelete = nil
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "creditcard").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Brak kart").font(.title3.bold())
            Text("Dodaj kartę ręcznie, zeskanuj aparatem lub odczytaj przez NFC.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { showAdd = true } label: { Label("Dodaj kartę", systemImage: "plus").padding(.horizontal, 12) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(.horizontal, 30).padding(.top, 40)
    }

    private var stack: some View {
        VStack(spacing: -118) {
            ForEach(wallet.cards) { c in
                CardView(brand: c.brand, number: c.number, holder: c.holder, expiry: c.expiry)
                    .scaleEffect(selected == c.id ? 1 : 0.95)
                    .zIndex(selected == c.id ? 1 : 0)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { selected = (selected == c.id) ? nil : c.id }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: wallet.cards)
    }

    @ViewBuilder private var details: some View {
        if let c = wallet.cards.first(where: { $0.id == selected }) {
            VStack(spacing: 10) {
                Button { wallet.preferredID = c.id; withAnimation { tab = 1 } } label: {
                    Label("Zapłać tą kartą", systemImage: "wave.3.right").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button(role: .destructive) { toDelete = c } label: {
                    Label("Usuń kartę", systemImage: "trash").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            .controlSize(.large).padding(.horizontal)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Text("Dotknij karty, aby zobaczyć opcje").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("W tym miesiącu").font(.subheadline).foregroundStyle(.secondary)
            Text(wallet.spentThisMonth.formatted(.currency(code: currency))).font(.system(size: 30, weight: .bold, design: .rounded))
            Text("\(wallet.monthTx(Date()).count) transakcji").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
    }
}

// MARK: - Płatność (demo)
struct PayView: View {
    @EnvironmentObject var wallet: WalletStore
    @AppStorage("currency") private var currency = "PLN"
    @State private var sel: UUID?
    @State private var amount = ""
    @State private var merchant = ""
    @State private var done = false
    @State private var msg: String?

    private var card: Card? { wallet.cards.first { $0.id == sel } ?? wallet.cards.first }
    private var value: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            ZStack {
                if wallet.cards.isEmpty {
                    Text("Najpierw dodaj kartę w zakładce Portfel.").foregroundStyle(.secondary).padding()
                } else { form }
                if done { SuccessOverlay().transition(.opacity.combined(with: .scale(scale: 0.9))) }
            }
            .navigationTitle("Zapłać")
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 16) {
                TabView(selection: $sel) {
                    ForEach(wallet.cards) { c in
                        CardView(brand: c.brand, number: c.number, holder: c.holder, expiry: c.expiry)
                            .padding(.horizontal).tag(Optional(c.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: wallet.cards.count > 1 ? .automatic : .never))
                .frame(height: 240)

                HStack(alignment: .firstTextBaseline) {
                    TextField("0,00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(currency).font(.title3).foregroundStyle(.secondary)
                }.padding(.horizontal, 24)

                TextField("Sprzedawca (opcjonalnie)", text: $merchant).padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal)

                Button { Task { await pay() } } label: {
                    Label("Zapłać", systemImage: "faceid").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal)
                .disabled((value ?? 0) <= 0)

                if let msg { Text(msg).font(.footnote).foregroundColor(.red) }
                Text("Tryb demo: płatność jest zapisywana w historii, ale nie obciąża prawdziwej karty.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { sel = wallet.preferredID ?? wallet.cards.first?.id }
        .onChange(of: wallet.preferredID) { sel = $0 }
    }

    private func pay() async {
        guard let c = card, let v = value, v > 0 else { return }
        msg = nil
        guard await authenticate() else { msg = "Nie potwierdzono płatności."; return }
        let m = merchant.trimmingCharacters(in: .whitespaces)
        wallet.pay(card: c, merchant: m.isEmpty ? "Płatność" : m, amount: v)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring()) { done = true }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        withAnimation { done = false; amount = ""; merchant = "" }
    }

    private func authenticate() async -> Bool {
        let ctx = LAContext()
        var e: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &e) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Potwierdź płatność")) ?? false
    }
}

struct SuccessOverlay: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Color.green.gradient).frame(width: 110, height: 110).scaleEffect(on ? 1 : 0.3)
                    Image(systemName: "checkmark").font(.system(size: 52, weight: .bold)).foregroundColor(.white)
                        .scaleEffect(on ? 1 : 0.2).opacity(on ? 1 : 0)
                }
                Text("Zapłacono").font(.title2.bold()).opacity(on ? 1 : 0)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { on = true } }
    }
}

// MARK: - Historia i wyciąg
struct HistoryView: View {
    @EnvironmentObject var wallet: WalletStore
    @AppStorage("currency") private var currency = "PLN"
    @State private var mode = 0
    @State private var month = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode.animation()) { Text("Transakcje").tag(0); Text("Wyciąg").tag(1) }
                    .pickerStyle(.segmented).padding()
                if mode == 0 { list } else { statement }
            }
            .navigationTitle("Historia")
        }
    }

    private func row(_ t: Transaction) -> some View {
        HStack(spacing: 12) {
            brandBadge(t.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.merchant).font(.body.weight(.medium))
                Text("\(t.brand.rawValue) •••• \(t.last4) · \(t.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("-" + t.amount.formatted(.currency(code: currency))).font(.body.weight(.semibold))
        }
    }

    @ViewBuilder private var list: some View {
        if wallet.transactions.isEmpty {
            Spacer(); Text("Brak transakcji").foregroundStyle(.secondary); Spacer()
        } else {
            let groups = Dictionary(grouping: wallet.transactions) { Calendar.current.startOfDay(for: $0.date) }
            List {
                ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(groups[day] ?? []) { row($0) }
                    }
                }
            }
        }
    }

    private var statement: some View {
        let tx = wallet.monthTx(month)
        let total = tx.reduce(0) { $0 + $1.amount }
        let perCard = Dictionary(grouping: tx) { "\($0.brand.rawValue) •••• \($0.last4)" }
        return List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                }
            }
            Section("Podsumowanie") {
                LabeledContent("Wydatki razem", value: total.formatted(.currency(code: currency)))
                LabeledContent("Liczba transakcji", value: "\(tx.count)")
            }
            if !perCard.isEmpty {
                Section("Według kart") {
                    ForEach(perCard.keys.sorted(), id: \.self) { k in
                        LabeledContent(k, value: (perCard[k] ?? []).reduce(0) { $0 + $1.amount }.formatted(.currency(code: currency)))
                    }
                }
            }
            Section("Operacje") {
                ForEach(tx) { row($0) }
                if tx.isEmpty { Text("Brak operacji w tym miesiącu").foregroundStyle(.secondary) }
            }
            if !tx.isEmpty {
                Section { ShareLink(item: csv(tx)) { Label("Eksportuj wyciąg (CSV)", systemImage: "square.and.arrow.up") } }
            }
        }
    }

    private func shift(_ v: Int) {
        withAnimation { month = Calendar.current.date(byAdding: .month, value: v, to: month) ?? month }
    }

    private func csv(_ tx: [Transaction]) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let rows = tx.map { t -> String in
            let m = t.merchant.replacingOccurrences(of: ";", with: ",")
            return f.string(from: t.date) + ";" + m + ";" + t.brand.rawValue + " " + t.last4 + ";" + String(format: "%.2f", t.amount)
        }
        return (["Data;Sprzedawca;Karta;Kwota (" + currency + ")"] + rows).joined(separator: "\n")
    }
}

// MARK: - Ustawienia
struct SettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wallet: WalletStore
    @AppStorage("theme") private var theme = AppTheme.dark.rawValue
    @AppStorage("currency") private var currency = "PLN"
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Wygląd") {
                    Picker("Motyw", selection: $theme) { ForEach(AppTheme.allCases) { Text($0.title).tag($0.rawValue) } }
                        .pickerStyle(.segmented)
                    Picker("Waluta", selection: $currency) { ForEach(["PLN", "EUR", "USD", "GBP"], id: \.self) { Text($0) } }
                }
                if let u = auth.user {
                    Section("Konto") {
                        LabeledContent("Nazwa", value: u.name)
                        LabeledContent("E-mail", value: u.email)
                        LabeledContent("Wiek", value: "\(u.age) lat")
                        LabeledContent("Logowanie", value: u.provider.capitalized)
                        Button("Wyloguj się", role: .destructive) { withAnimation { auth.signOut() } }
                    }
                }
                Section("Dane") {
                    Button("Usuń wszystkie karty i historię", role: .destructive) { confirmWipe = true }
                }
                Section { Text("PayWallet 1.0 · tryb demo, bez realnych płatności").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Ustawienia")
            .confirmationDialog("Usunąć wszystkie dane?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Usuń", role: .destructive) { withAnimation { wallet.deleteAll() } }
            }
        }
    }
}
