import SwiftUI
import VisionKit

/// Scans an `omnie://connect?...` QR code. Falls back to pasting the link
/// where the camera scanner isn't available.
struct CodeScannerSheet: View {
    let onFound: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tokens) private var tokens
    @State private var pasted = ""
    @State private var invalid = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    QRScanner { text in
                        if let url = URL(string: text), ConnectionLink(url: url) != nil {
                            Haptics.success()
                            onFound(url)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 20))
                    .frame(maxHeight: 420)
                } else {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera", description: Text("Paste the connection link instead."))
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Or paste a link")
                    HStack {
                        TextField("omnie://connect?…", text: $pasted)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote.monospaced())
                        Button("Use") {
                            if let url = URL(string: pasted.trimmingCharacters(in: .whitespacesAndNewlines)), ConnectionLink(url: url) != nil {
                                onFound(url)
                            } else {
                                invalid = true
                            }
                        }
                        .disabled(pasted.isEmpty)
                    }
                    .padding(12)
                    .card(tokens, radius: 12)
                    if invalid {
                        Text("That isn't an Omnie connection link.")
                            .font(.footnote)
                            .foregroundStyle(Palette.Semantic.danger)
                    }
                }
                Text("Format: omnie://connect?kind=dashboard&url=http://host:9119&name=Studio&user=me")
                    .font(.caption2.monospaced())
                    .foregroundStyle(tokens.secondary)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding()
            .background(tokens.background.ignoresSafeArea())
            .navigationTitle("Scan Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onText: (String) -> Void
        init(onText: @escaping (String) -> Void) { self.onText = onText }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue {
                    onText(text)
                }
            }
        }
    }
}
