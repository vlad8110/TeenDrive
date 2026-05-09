import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var parentName = ""
    @State private var isShowingScanner = false
    @State private var scanErrorMessage: String?

    private var displayName: String {
        let trimmed = accountStore.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? accountStore.role.title : trimmed
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? String(displayName.prefix(1)).uppercased() : String(letters).uppercased()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerCard
                syncCard
                profileCard

                if accountStore.role == .teen {
                    teenPairingCard
                } else {
                    parentPairingCard
                }

                if accountStore.isPaired || accountStore.role == .parent {
                    disconnectCard
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
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

    private var headerCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 86, height: 86)

                Text(initials)
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())
                Label(accountStore.role == .teen ? "Teen account" : "Parent account", systemImage: accountStore.role == .teen ? "car.fill" : "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cloud Sync", systemImage: syncIcon)
                    .font(.headline)
                    .foregroundStyle(syncColor)
                Spacer()
                Text(accountStore.cloudSyncState.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(syncColor)
                    .lineLimit(1)
            }

            if let synced = accountStore.lastSuccessfulCloudSyncAt {
                Text("Last synced \(synced.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sign in and sync will start automatically when Firebase is ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Account Details", systemImage: "person.text.rectangle")
                .font(.headline)

            TextField(accountStore.role == .teen ? "Teen name" : "Parent name", text: $accountStore.displayName)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var teenPairingCard: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Pair With Parent", systemImage: "qrcode")
                    .font(.headline)
                Spacer()
                pairingBadge
            }

            if accountStore.isPairingReady {
                PairingQRCodeView(payload: accountStore.pairingPayload)
            } else {
                ProgressView()
                    .frame(width: 220, height: 220)
            }

            Text(accountStore.isPairingReady ? "Have a parent scan this QR code from their app." : "Preparing your cloud pairing QR.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if accountStore.connectedParentName.isEmpty {
                Text(accountStore.firebaseStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Label("Connected to \(accountStore.connectedParentName)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Button {
                accountStore.regeneratePairingCode()
            } label: {
                Label("Generate New QR", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var parentPairingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Connected Teens", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                Text("\(accountStore.connectedTeens.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.blue)
            }

            TextField("Parent name", text: $parentName)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)

            Button {
                accountStore.displayName = parentName
                isShowingScanner = true
            } label: {
                Label("Scan Teen QR", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(parentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let scanErrorMessage {
                Text(scanErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if accountStore.connectedTeens.isEmpty {
                ContentUnavailableView("No Teens Connected", systemImage: "person.badge.plus", description: Text("Scan a teen QR code to add them here."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(accountStore.connectedTeens) { teen in
                        connectedTeenRow(teen)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var disconnectCard: some View {
        Button(role: .destructive) {
            accountStore.disconnect()
        } label: {
            Label("Disconnect Account Links", systemImage: "person.crop.circle.badge.xmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var pairingBadge: some View {
        Text(accountStore.connectedParentName.isEmpty ? "Open" : "Paired")
            .font(.caption.weight(.bold))
            .foregroundStyle(accountStore.connectedParentName.isEmpty ? .blue : .green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((accountStore.connectedParentName.isEmpty ? Color.blue : Color.green).opacity(0.12), in: Capsule())
    }

    private var syncColor: Color {
        switch accountStore.cloudSyncState {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .upToDate:
            return .green
        case .blocked, .failed:
            return .orange
        }
    }

    private var syncIcon: String {
        switch accountStore.cloudSyncState {
        case .idle:
            return "icloud"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .upToDate:
            return "checkmark.icloud.fill"
        case .blocked, .failed:
            return "exclamationmark.icloud"
        }
    }

    private func connectedTeenRow(_ teen: ConnectedTeen) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.blue, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(teen.name)
                    .font(.subheadline.weight(.semibold))
                Text(teen.teenProfileID.isEmpty ? "Local pairing only" : "Cloud trips enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: teen.teenProfileID.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(teen.teenProfileID.isEmpty ? .orange : .green)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
