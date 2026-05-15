/*
 File: AccountSettingsView.swift
 Created: 2026-05-09
 Creator: Vladimyr Merci

 Purpose:
 Builds the profile, pairing, sync status, and disconnect screens used by teen and parent accounts.

 Developer Notes:
 This file is part of the TeenDrive app. The comments below explain the important entry points so a new programmer can trace the flow without reading the whole project first.
*/
import SwiftUI

// Lets users edit their profile identity and manage parent/teen pairing.
struct AccountSettingsView: View {
    @ObservedObject var accountStore: AccountStore
    var sessionStore: SessionStore?
    var usesTeenHeader = false
    @State private var parentName = ""
    @State private var isShowingScanner = false
    @State private var isShowingPrivacySafety = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeletingAccountData = false
    @State private var deletionMessage: String?
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
        Group {
            if usesTeenHeader {
                teenProfileBody
            } else {
                standardProfileBody
            }
        }
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
        .sheet(isPresented: $isShowingPrivacySafety) {
            NavigationStack {
                PrivacySafetyView()
            }
        }
        .confirmationDialog(
            "Delete account and data?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account & Data", role: .destructive) {
                Task {
                    await deleteAccountAndData()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes local trips, pairing links, and account records for this device. Teen accounts also request deletion of their synced trips.")
        }
    }

    private var standardProfileBody: some View {
        profileContent
            .background(GlassAppBackground())
            .environment(\.colorScheme, .dark)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var teenProfileBody: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 760

            VStack(alignment: .leading, spacing: compact ? 7 : 9) {
                TeenScreenHeader(title: "Profile", compact: compact) {
                    Text(displayName)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                } actions: {
                    EmptyView()
                }

                profileContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.top, compact ? 22 : 34)
            .padding(.bottom, compact ? 16 : 20)
        }
        .background(GlassAppBackground())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var profileContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                if !usesTeenHeader {
                    headerCard
                }
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

                legalAndDataCard
            }
            .padding(12)
            .padding(.bottom, 24)
        }
    }

    private var headerCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, Color.green.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)

                Text(initials)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            VStack(spacing: 2) {
                Text(displayName)
                    .font(.headline.bold())
                Label(accountStore.role == .teen ? "Teen account" : "Parent account", systemImage: accountStore.role == .teen ? "car.fill" : "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .teenGlassCard()
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Cloud Sync", systemImage: syncIcon)
                    .font(.subheadline.weight(.semibold))
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
        .padding(12)
        .teenGlassCard()
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Account Details", systemImage: "person.text.rectangle")
                .font(.subheadline.weight(.semibold))

            TextField(accountStore.role == .teen ? "Teen name" : "Parent name", text: $accountStore.displayName)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .teenGlassCard()
    }

    private var teenPairingCard: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Pair With Parent", systemImage: "qrcode")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                pairingBadge
            }

            if accountStore.isPairingReady {
                PairingQRCodeView(payload: accountStore.pairingPayload)
                    .frame(width: 142, height: 142)
            } else {
                ProgressView()
                    .frame(width: 142, height: 142)
            }

            Text(accountStore.isPairingReady ? "Have a parent scan this QR code from their app." : "Preparing your cloud pairing QR.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !accountStore.hasConnectedParent {
                Text(accountStore.firebaseStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(accountStore.connectedParentDisplayName, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)

                    ForEach(accountStore.connectedParents) { parent in
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.green, in: Circle())

                            Text(parent.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .teenGlassControl()
                    }
                }
            }

            Button {
                accountStore.regeneratePairingCode()
            } label: {
                Label("Generate New QR", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .teenGlassCard()
    }

    private var parentPairingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Connected Teens", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                Text("\(accountStore.connectedTeens.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
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
        .teenGlassCard()
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
        .teenGlassCard()
    }

    private var legalAndDataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy & Safety", systemImage: "lock.shield")
                .font(.subheadline.weight(.semibold))

            Button {
                isShowingPrivacySafety = true
            } label: {
                Label("Privacy Policy & Safety Disclaimer", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                if isDeletingAccountData {
                    HStack {
                        ProgressView()
                        Text("Deleting Account Data")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Delete Account & Data", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isDeletingAccountData)

            if let deletionMessage {
                Text(deletionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .teenGlassCard()
    }

    private var pairingBadge: some View {
        Text(accountStore.hasConnectedParent ? "Paired" : "Open")
            .font(.caption.weight(.bold))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.12), in: Capsule())
    }

    private var syncColor: Color {
        switch accountStore.cloudSyncState {
        case .idle:
            return .secondary
        case .syncing:
            return .green
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

    /*
     Purpose:
     Runs the full user-requested deletion flow from the settings screen.

     Local trip history is erased first so reports disappear immediately, then AccountStore attempts cloud
     cleanup and resets account state back to the first-run role picker.
    */
    private func deleteAccountAndData() async {
        guard !isDeletingAccountData else { return }
        isDeletingAccountData = true
        deletionMessage = "Deleting local and cloud data..."
        sessionStore?.deleteAllLocalData()
        await accountStore.deleteAccountAndCloudData()
        deletionMessage = "Account data deleted on this device."
        isDeletingAccountData = false
    }

    /*
     Purpose:
     Builds the row for one teen connected to a parent account.
    */
    private func connectedTeenRow(_ teen: ConnectedTeen) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.green, in: Circle())

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
        .teenGlassControl()
    }
}
