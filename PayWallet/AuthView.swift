import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.colorScheme) private var scheme
    @State private var register = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var birth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var error: String?
    @State private var busy = false

    private var age: Int { AuthStore.age(birth) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(scheme == .dark ? Color.white : Color.black)
                        .frame(width: 80, height: 80)
                    Image(systemName: "creditcard.fill").font(.system(size: 38)).foregroundColor(scheme == .dark ? .black : .white)
                }.padding(.top, 30)
                Text("PayWallet").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Twoje karty w jednym miejscu").foregroundStyle(.secondary)

                Picker("", selection: $register.animation(.easeInOut)) {
                    Text("Rejestracja").tag(true)
                    Text("Logowanie").tag(false)
                }.pickerStyle(.segmented)

                VStack(spacing: 12) {
                    if register { input("Imię", $name, .default) }
                    input("E-mail", $email, .emailAddress)
                    SecureField("Hasło (min. 8 znaków)", text: $password).padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        DatePicker("Data urodzenia", selection: $birth, in: ...Date(), displayedComponents: .date)
                        Text(age >= AuthStore.minAge ? "Wiek: \(age) lat ✓" : "Wymagane min. 13 lat (masz \(age))")
                            .font(.caption).foregroundColor(age >= AuthStore.minAge ? .green : .red)
                        if !register { Text("Potrzebna tylko przy pierwszym logowaniu przez Apple/Google.").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let error { Text(error).font(.footnote).foregroundColor(.red).multilineTextAlignment(.center).transition(.opacity) }

                Button(action: submit) {
                    Text(register ? "Utwórz konto" : "Zaloguj się").bold().frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)

                HStack { Rectangle().frame(height: 1); Text("lub").font(.footnote); Rectangle().frame(height: 1) }
                    .foregroundStyle(.secondary.opacity(0.6))

                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do { try await auth.handleApple(birth: birth) }
                        catch { show(error) }
                    }
                } label: {
                    HStack {
                        Image(systemName: "applelogo").font(.system(size: 20))
                        Text("Kontynuuj z Apple").bold()
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                }
                .foregroundColor(scheme == .dark ? .black : .white)
                .background(scheme == .dark ? .white : .black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { if busy { ProgressView() } }

                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do { try await auth.googleSignIn(birth: birth) }
                        catch { if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { show(error) } }
                    }
                } label: {
                    HStack { Text("G").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.red); Text("Kontynuuj z Google").bold() }
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .foregroundColor(.primary)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { if busy { ProgressView() } }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func input(_ t: String, _ b: Binding<String>, _ kb: UIKeyboardType) -> some View {
        TextField(t, text: b).keyboardType(kb).textInputAutocapitalization(kb == .default ? .words : .never)
            .autocorrectionDisabled().padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func show(_ e: Error) { withAnimation { error = e.localizedDescription } }

    private func submit() {
        do {
            if register { try auth.register(name: name, email: email, password: password, birth: birth) }
            else { try auth.login(email: email, password: password) }
        } catch { show(error) }
    }
}

struct VerificationView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var code = ""
    @State private var error: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Weryfikacja e-mail").font(.title.bold())
            Text("Wysłaliśmy 6-cyfrowy kod na Twój e-mail.\nWpisz go poniżej, aby dokończyć rejestrację.")
                .multilineTextAlignment(.center).foregroundColor(.secondary)
            
            TextField("Kod weryfikacyjny", text: $code)
                .keyboardType(.numberPad).padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            if let error { Text(error).font(.footnote).foregroundColor(.red) }
            
            Button("Zweryfikuj") {
                do { try auth.verify(code) }
                catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            
            Button("Anuluj") { auth.cancelVerification() }.foregroundColor(.secondary)
        }.padding()
    }
}
