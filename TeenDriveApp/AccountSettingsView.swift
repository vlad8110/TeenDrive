import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var parentName = ""
    @State private var isShowingScanner = false
    @State private var scanErrorMessage: String?

    var body: some View {
        Form {
            Section("Cloud sync") {
                LabeledContent("Status") {
                    Text(accountStore.cloudSyncState.title)
                        .foregroundStyle(accountStore.cloudSyncState.isError ? .orange : .primary)
                        .multilineTextAlignment(.trailing)
                }
                if let synced = accountStore.lastSuccessfulCloudSyncAt {
                    LabeledContent("Last success") {
                        Text(synced.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }

            Section("Account") {
                LabeledContent("Mode", value: accountStore.role.title)
                TextField(accountStore.role == .teen ? "Teen name" : "Parent name", text: $accountStore.displayName)
                    .textContentType(.name)
            }

            if accountStore.role == .teen {
                teenPairingSection
            } else {
                parentPairingSection
            }

            if accountStore.isPaired || accountStore.role == .parent {
                Section {
                    Button(role: .destructive) {
                        accountStore.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            }
        }
        .navigationTitle("Account")
        .onAppear {
            parentName = accountStore.displayName
        }
        .task {
            await accountStore.syncAccount()
        }
        .sheet(isPresented: $isShowingScanner) {
            NavigationStack {
                QRCodeScannerView { payload in
                    Task {
                        let paired = await accountStore.connectParent(name: parentName, scannedPayload: payload)
                        scanErrorMessage = paired ? nil : "That QR code is not a Teen Drive pairing code."
                        isShowingScanner = false
                    }
                }
                .ignoresSafeArea()
                .navigationTitle("Scan Teen QR")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Cancel") {
                        isShowingScanner = false
                    }
                }
            }
        }
    }

    private var teenPairingSection: some View {
        Section("Teen Pairing QR") {
            VStack(alignment: .center, spacing: 12) {
                if accountStore.isPairingReady {
                    PairingQRCodeView(payload: accountStore.pairingPayload)
                } else {
                    ProgressView()
                        .frame(width: 220, height: 220)
                }

                Text(accountStore.isPairingReady ? "Have a parent scan this QR code to connect." : "Preparing cloud pairing QR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            if accountStore.connectedParentName.isEmpty {
                Text(accountStore.firebaseStatus)
                    .foregroundStyle(.secondary)
            } else {
                Label("Connected to \(accountStore.connectedParentName)", systemImage: "person.2.fill")
                    .foregroundStyle(.green)
            }

            Button("Generate New QR") {
                accountStore.regeneratePairingCode()
            }
        }
    }

    private var parentPairingSection: some View {
        Section("Connect Teen") {
            TextField("Parent name", text: $parentName)
                .textContentType(.name)

            Button {
                accountStore.displayName = parentName
                isShowingScanner = true
            } label: {
                Label("Scan Teen QR", systemImage: "qrcode.viewfinder")
            }
            .disabled(parentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let scanErrorMessage {
                Text(scanErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !accountStore.connectedTeenCode.isEmpty {
                Label("Paired with \(accountStore.connectedTeens.count) teen\(accountStore.connectedTeens.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if !accountStore.connectedTeens.isEmpty {
                ForEach(accountStore.connectedTeens) { teen in
                    Label(teen.name, systemImage: "person.fill")
                }
                .onDelete(perform: accountStore.deleteConnectedTeens)
            }
        }
    }
}
