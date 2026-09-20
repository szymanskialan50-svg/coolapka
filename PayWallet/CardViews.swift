import SwiftUI

struct CardView: View {
    let brand: CardBrand
    let number: String
    let holder: String
    let expiry: String
    var masked = true

    private var numberText: String {
        if number.isEmpty { return "•••• •••• •••• ••••" }
        if masked && number.count >= 4 { return "•••• •••• •••• " + number.suffix(4) }
        return Card.group(number)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            brand.colors[0] // Use solid color instead of gradient for flat look
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "wave.3.right").font(.title3)
                    Spacer()
                    Text(brand.rawValue.uppercased()).font(.system(.headline, design: .rounded).weight(.heavy)).italic()
                }
                Spacer()
                Text(numberText)
                    .font(.system(size: 21, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.6).lineLimit(1)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WŁAŚCICIEL").font(.system(size: 9, weight: .medium)).opacity(0.7)
                        Text(holder.isEmpty ? "IMIĘ NAZWISKO" : holder.uppercased())
                            .font(.footnote.weight(.semibold)).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("WAŻNA DO").font(.system(size: 9, weight: .medium)).opacity(0.7)
                        Text(expiry.isEmpty ? "MM/RR" : expiry).font(.footnote.weight(.semibold))
                    }
                }.padding(.top, 14)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundColor(.white)
        .aspectRatio(1.586, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 4)
        .animation(.easeInOut(duration: 0.3), value: brand)
    }
}

struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var wallet: WalletStore
    @EnvironmentObject var auth: AuthStore
    @StateObject private var nfc = NFCCardReader()
    @State private var number = ""
    @State private var holder = ""
    @State private var expiry = ""
    @State private var showScan = false
    @State private var error: String?

    private var brand: CardBrand { .detect(number) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    CardView(brand: brand, number: number.filter(\.isNumber), holder: holder, expiry: expiry, masked: false)
                        .padding(.horizontal)
                    HStack(spacing: 12) {
                        Button { showScan = true } label: {
                            Label("Skanuj", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { nfc.start() } label: {
                            Label("NFC", systemImage: "wave.3.right.circle").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                    .controlSize(.large).padding(.horizontal)

                    if !nfc.status.isEmpty {
                        Text(nfc.status).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    }

                    VStack(spacing: 12) {
                        field("Numer karty", $number, .numberPad)
                            .overlay(alignment: .trailing) {
                                if brand != .unknown {
                                    Text(brand.rawValue).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(brand.colors[0], in: Capsule()).foregroundColor(.white)
                                        .padding(.trailing, 10).transition(.scale.combined(with: .opacity))
                                }
                            }
                        field("Imię i nazwisko na karcie", $holder, .default, .characters)
                        field("Ważna do (MM/RR)", $expiry, .numberPad)
                    }
                    .padding(.horizontal)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: brand)

                    if let error { Text(error).font(.footnote).foregroundColor(.red).padding(.horizontal) }
                    Text("CVV nie jest zapisywany. Dane kart są szyfrowane w Keychain iPhone'a.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Nowa karta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Zapisz") { save() }.bold() }
            }
            .onChange(of: number) { v in
                let d = String(v.filter(\.isNumber).prefix(CardBrand.detect(v) == .amex ? 15 : 19))
                let g = Card.group(d)
                if g != v { number = g }
            }
            .onChange(of: expiry) { v in
                var d = String(v.filter(\.isNumber).prefix(4))
                if d.count > 2 { d.insert("/", at: d.index(d.startIndex, offsetBy: 2)) }
                if d != v { expiry = d }
            }
            .onAppear {
                nfc.onResult = { pan, exp in
                    number = Card.group(pan)
                    if let exp { expiry = exp }
                    if holder.isEmpty { holder = auth.user?.name ?? "" }
                }
            }
            .fullScreenCover(isPresented: $showScan) {
                ScanCardView { pan, exp in
                    number = Card.group(pan)
                    if let exp { expiry = exp }
                }
            }
        }
    }

    private func field(_ title: String, _ text: Binding<String>, _ kb: UIKeyboardType = .default,
                       _ cap: TextInputAutocapitalization = .never) -> some View {
        TextField(title, text: text)
            .keyboardType(kb).textInputAutocapitalization(cap).autocorrectionDisabled()
            .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save() {
        let digits = number.filter(\.isNumber)
        let name = holder.trimmingCharacters(in: .whitespaces)
        if !luhnValid(digits) { error = "Numer karty jest nieprawidłowy."; return }
        if !expiryValid(expiry) { error = "Data ważności jest nieprawidłowa lub karta wygasła."; return }
        if name.isEmpty { error = "Podaj imię i nazwisko z karty."; return }
        if wallet.cards.contains(where: { $0.number == digits }) { error = "Ta karta jest już w portfelu."; return }
        wallet.add(Card(holder: name, number: digits, expiry: expiry))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
