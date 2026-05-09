import SwiftUI

struct RoleSelectionView: View {
    @ObservedObject var accountStore: AccountStore
    @State private var selectedRole: AccountRole = .teen
    @State private var name = ""

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)

                Text("Teen Drive")
                    .font(.largeTitle.bold())

                Text("Choose how this phone will use the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Picker("Mode", selection: $selectedRole) {
                ForEach(AccountRole.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
            .pickerStyle(.segmented)

            TextField(selectedRole == .teen ? "Teen name" : "Parent name", text: $name)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 10) {
                Label(selectedRole == .teen ? "Track drives on this phone" : "Scan teen QR codes", systemImage: selectedRole == .teen ? "location.fill" : "qrcode.viewfinder")
                Label(selectedRole == .teen ? "Works even before pairing" : "Connect more than one teen", systemImage: selectedRole == .teen ? "checkmark.circle.fill" : "person.2.fill")
                Label(selectedRole == .teen ? "Parent dashboard stays hidden" : "Review connected teen trips", systemImage: selectedRole == .teen ? "eye.slash.fill" : "list.bullet.rectangle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button {
                accountStore.displayName = name
                accountStore.selectRole(selectedRole)
            } label: {
                Label("Continue", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }
}
