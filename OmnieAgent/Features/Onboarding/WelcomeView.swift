import SwiftUI

/// First run: what Omnie is, and one way forward.
struct WelcomeView: View {
    @Environment(\.tokens) private var tokens
    @State private var adding = false
    @State private var scanning = false
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Wordmark(size: 40)
            Text("A client for your Hermes agents.")
                .font(.title3)
                .foregroundStyle(tokens.secondary)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(ConnectionKind.allCases) { kind in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: kind.systemImage)
                            .font(.body)
                            .frame(width: 24)
                            .foregroundStyle(tokens.text)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(tokens.text)
                            Text(kind.summary).font(.footnote).foregroundStyle(tokens.secondary)
                        }
                    }
                }
            }
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    adding = true
                } label: {
                    Text("Connect an agent")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .primaryAction()

                Button {
                    scanning = true
                } label: {
                    Label("Scan a connection code", systemImage: "qrcode.viewfinder")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tokens.text)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .background(tokens.background.ignoresSafeArea())
        .sheet(isPresented: $adding) {
            ConnectionEditor(draft: Connection(name: "", kind: .dashboard, baseURL: ""), secret: "", isNew: true)
        }
        .sheet(isPresented: $scanning) {
            CodeScannerSheet { url in
                scanning = false
                model.handle(url: url)
            }
        }
    }
}
