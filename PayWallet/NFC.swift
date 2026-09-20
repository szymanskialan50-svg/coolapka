import Foundation
import CoreNFC

struct TLV {
    let tag: Int
    let constructed: Bool
    let value: Data

    static func parse(_ d: Data) -> [TLV] {
        let b = [UInt8](d)
        var out: [TLV] = []
        var i = 0
        while i < b.count {
            let first = b[i]
            var tag = Int(first)
            i += 1
            if first & 0x1F == 0x1F {
                while i < b.count {
                    let t = Int(b[i]); tag = (tag << 8) | t; i += 1
                    if t & 0x80 == 0 { break }
                }
            }
            guard i < b.count else { break }
            var len = Int(b[i]); i += 1
            if len & 0x80 != 0 {
                let n = len & 0x7F
                len = 0
                for _ in 0..<n { guard i < b.count else { return out }; len = (len << 8) | Int(b[i]); i += 1 }
            }
            guard i + len <= b.count else { break }
            out.append(TLV(tag: tag, constructed: first & 0x20 != 0, value: Data(b[i..<(i + len)])))
            i += len
        }
        return out
    }

    static func find(_ tag: Int, in d: Data) -> Data? {
        for t in parse(d) {
            if t.tag == tag { return t.value }
            if t.constructed, let f = find(tag, in: t.value) { return f }
        }
        return nil
    }
}

enum CardErr: Error { case none, status(UInt8, UInt8) }

final class NFCCardReader: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    @Published var status = ""
    var onResult: ((String, String?) -> Void)?
    private var session: NFCTagReaderSession?

    func start() {
        guard NFCTagReaderSession.readingAvailable else {
            status = "NFC jest niedostępne na tym urządzeniu lub w tej wersji aplikacji."
            return
        }
        status = "Przyłóż kartę do górnej części iPhone'a…"
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self)
        session?.alertMessage = "Przyłóż kartę płatniczą do iPhone'a"
        session?.begin()
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            if self.status.hasPrefix("✓") { return }
            if (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled { self.status = "" }
            else { self.status = "NFC: " + error.localizedDescription }
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let first = tags.first, case .iso7816(let tag) = first else {
            session.invalidate(errorMessage: "To nie jest karta płatnicza.")
            return
        }
        session.connect(to: first) { [weak self] err in
            guard let self else { return }
            if let err { session.invalidate(errorMessage: err.localizedDescription); return }
            Task {
                do {
                    let (pan, exp) = try await self.readEMV(tag)
                    session.alertMessage = "Odczytano kartę"
                    session.invalidate()
                    await MainActor.run { self.status = "✓ Odczytano kartę"; self.onResult?(pan, exp) }
                } catch {
                    session.invalidate(errorMessage: "Nie udało się odczytać numeru. Część banków blokuje odczyt NFC.")
                }
            }
        }
    }

    private func tx(_ tag: NFCISO7816Tag, _ cla: UInt8, _ ins: UInt8, _ p1: UInt8, _ p2: UInt8, _ data: Data = Data()) async throws -> Data {
        let apdu = NFCISO7816APDU(instructionClass: cla, instructionCode: ins, p1Parameter: p1, p2Parameter: p2,
                                  data: data, expectedResponseLength: 256)
        let (resp, sw1, sw2) = try await tag.sendCommand(apdu: apdu)
        guard sw1 == 0x90, sw2 == 0x00 else { throw CardErr.status(sw1, sw2) }
        return resp
    }

    private func hex(_ d: Data) -> String { d.map { String(format: "%02X", $0) }.joined() }

    private func extract(_ d: Data) -> (String?, String?) {
        var pan: String?
        var exp: String?
        if let v = TLV.find(0x5A, in: d) { pan = hex(v).trimmingCharacters(in: CharacterSet(charactersIn: "F")) }
        if let v = TLV.find(0x57, in: d) {
            let parts = hex(v).split(separator: "D", maxSplits: 1)
            if parts.count == 2 {
                if pan == nil { pan = String(parts[0]) }
                let r = parts[1]
                if r.count >= 4 { exp = "\(r.dropFirst(2).prefix(2))/\(r.prefix(2))" }
            }
        }
        if exp == nil, let v = TLV.find(0x5F24, in: d) {
            let h = hex(v)
            if h.count >= 4 { exp = "\(h.dropFirst(2).prefix(2))/\(h.prefix(2))" }
        }
        return (pan, exp)
    }

    private func buildPDOL(_ p: Data) -> Data {
        let b = [UInt8](p)
        var i = 0
        var out = Data()
        while i < b.count {
            var tag = Int(b[i]); i += 1
            if tag & 0x1F == 0x1F {
                while i < b.count { let t = Int(b[i]); tag = (tag << 8) | t; i += 1; if t & 0x80 == 0 { break } }
            }
            guard i < b.count else { break }
            let len = Int(b[i]); i += 1
            var v = [UInt8](repeating: 0, count: len)
            if tag == 0x9F66, len == 4 { v = [0x27, 0x00, 0x00, 0x00] }
            if tag == 0x9F1A, len == 2 { v = [0x06, 0x16] }
            if tag == 0x5F2A, len == 2 { v = [0x09, 0x85] }
            out.append(contentsOf: v)
        }
        return out
    }

    private func readEMV(_ tag: NFCISO7816Tag) async throws -> (String, String?) {
        var pan: String?
        var exp: String?
        func absorb(_ d: Data) { let (p, e) = extract(d); pan = pan ?? p; exp = exp ?? e }

        let ppse = try await tx(tag, 0x00, 0xA4, 0x04, 0x00, Data("2PAY.SYS.DDF01".utf8))
        guard let aid = TLV.find(0x4F, in: ppse) else { throw CardErr.none }
        let fci = try await tx(tag, 0x00, 0xA4, 0x04, 0x00, aid)
        absorb(fci)

        let pdol = TLV.find(0x9F38, in: fci).map(buildPDOL) ?? Data()
        let gpoData = Data([0x83, UInt8(pdol.count)]) + pdol
        if let gpo = try? await tx(tag, 0x80, 0xA8, 0x00, 0x00, gpoData) {
            absorb(gpo)
            var afl = TLV.find(0x94, in: gpo)
            if afl == nil, let f = TLV.parse(gpo).first, f.tag == 0x80, f.value.count > 2 { afl = Data(f.value.dropFirst(2)) }
            if let afl {
                let b = [UInt8](afl)
                var i = 0
                while i + 3 < b.count {
                    let sfi = b[i] >> 3, lo = b[i + 1], hi = b[i + 2]
                    i += 4
                    guard lo > 0, lo <= hi else { continue }
                    for r in lo...hi {
                        if let rec = try? await tx(tag, 0x00, 0xB2, r, (sfi << 3) | 4) { absorb(rec) }
                        if pan != nil && exp != nil { break }
                    }
                }
            }
        }
        guard let p = pan, p.count >= 13 else { throw CardErr.none }
        return (p, exp)
    }
}
