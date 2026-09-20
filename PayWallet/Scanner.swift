import SwiftUI
import VisionKit
import AVFoundation

struct ScannerRepresentable: UIViewControllerRepresentable {
    var onFound: (String, String?) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> CreditCardScannerViewController {
        let vc = CreditCardScannerViewController(delegate: context.coordinator)
        vc.titleLabelText = "Dodaj kartę"
        vc.subtitleLabelText = "Ustaw kartę w ramce"
        vc.cancelButtonTitleText = "Anuluj"
        return vc
    }
    func updateUIViewController(_ vc: CreditCardScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CreditCardScannerViewControllerDelegate {
        var parent: ScannerRepresentable
        init(_ parent: ScannerRepresentable) { self.parent = parent }

        func creditCardScannerViewControllerDidCancel(_ viewController: CreditCardScannerViewController) {
            parent.onCancel()
        }
        func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didErrorWith error: CreditCardScannerError) {
            parent.onCancel()
        }
        func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didFinishWith card: CreditCard) {
            let pan = card.number ?? ""
            var exp: String?
            if let d = card.expireDate, let m = d.month, let y = d.year {
                exp = String(format: "%02d/%02d", m, y % 100)
            }
            parent.onFound(pan, exp)
        }
    }
}

struct ScanCardView: View {
    var onFound: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScannerRepresentable(
            onFound: { p, e in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onFound(p, e)
                dismiss()
            },
            onCancel: { dismiss() }
        )
        .ignoresSafeArea()
    }
}
