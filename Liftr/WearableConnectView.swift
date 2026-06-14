import SwiftUI

struct WearableConnectionRow: Decodable {
    let provider: String
    let status: String
    let connected_at: Date?
    let last_sync_at: Date?
}

struct WearableOAuthStartResponse: Decodable {
    let provider: String?
    let authorization_url: String?
    let error: String?
    let message: String?
}

struct WearableConnectView: View {
    @EnvironmentObject var app: AppState

    @State private var syncEnabled = ExternalRouteSyncService.shared.isSyncEnabled
    @State private var connecting = false
    @State private var connection: WearableConnectionRow?
    @State private var banner: String?
    @State private var lastSummary: ExternalRouteSyncSummary?

    var body: some View {
        List {
            Section {
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GPS routes for Apple Health")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            "Connect Garmin to fetch GPS tracks missing from Apple Health workouts synced via Garmin Connect. "
                                + "Liftr adds the route to Health and backfills your Liftr workout map. Workout calories are not modified."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Toggle("Add missing GPS routes", isOn: $syncEnabled)
                            .onChange(of: syncEnabled) { _, enabled in
                                Task { await setRouteSyncEnabled(enabled) }
                            }

                        if let lastSync = ExternalRouteSyncService.shared.lastSyncAt {
                            Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if ExternalRouteSyncService.shared.routesAppliedCount > 0 {
                            Text("Routes applied: \(ExternalRouteSyncService.shared.routesAppliedCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Garmin Connect") {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(connectionStatusText)
                                .font(.body.weight(.semibold))
                            Spacer()
                            if connecting {
                                ProgressView()
                            }
                        }

                        Button {
                            Task { await connectGarmin() }
                        } label: {
                            Text(connectButtonTitle)
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .disabled(connecting || app.userId == nil)

                        Button {
                            guard let userId = app.userId else { return }
                            Task { await runSync(userId: userId) }
                        } label: {
                            Text("Sync pending routes now")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .disabled(app.userId == nil)
                    }
                }
            }

            if let banner {
                Section {
                    settingsCard {
                        Text(banner)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let summary = lastSummary {
                Section("Result") {
                    settingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Applied", value: "\(summary.applied)")
                            Divider().opacity(0.15)
                            LabeledContent("Skipped", value: "\(summary.skipped)")
                            if summary.failed > 0 {
                                Divider().opacity(0.15)
                                LabeledContent("Failed", value: "\(summary.failed)")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .background(Color.clear)
        .navigationTitle("Wearable routes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshConnection() }
    }

    private var connectionStatusText: String {
        guard let connection else { return "Not connected" }
        return connection.status == "active" ? "Garmin connected" : "Garmin \(connection.status)"
    }

    private var connectButtonTitle: String {
        if connection?.status == "active" { return "Reconnect Garmin" }
        return "Connect Garmin"
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.18))
                )
            content()
                .padding(12)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private func refreshConnection() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("wearable_connections")
                .select("provider, status, connected_at, last_sync_at")
                .eq("provider", value: "garmin")
                .limit(1)
                .execute()
            let rows = try JSONDecoder.supabaseCustom().decode([WearableConnectionRow].self, from: res.data)
            await MainActor.run { connection = rows.first }
        } catch {
            await MainActor.run { connection = nil }
        }
    }

    private func setRouteSyncEnabled(_ enabled: Bool) async {
        banner = nil
        ExternalRouteSyncService.shared.isSyncEnabled = enabled
        guard enabled else { return }
        guard let userId = app.userId else {
            await MainActor.run {
                syncEnabled = false
                ExternalRouteSyncService.shared.isSyncEnabled = false
                banner = "Sign in to enable GPS route sync."
            }
            return
        }
        await runSync(userId: userId)
        if lastSummary?.failed ?? 0 > 0, lastSummary?.applied == 0 {
            await MainActor.run {
                syncEnabled = false
                ExternalRouteSyncService.shared.isSyncEnabled = false
            }
        }
    }

    private func connectGarmin() async {
        connecting = true
        banner = nil
        defer { connecting = false }

        struct Payload: Encodable {
            let provider: String
        }

        do {
            let response: WearableOAuthStartResponse = try await SupabaseManager.shared.client.functions
                .invoke(
                    "wearable-oauth-start",
                    options: .init(body: Payload(provider: "garmin"))
                )
            guard let urlString = response.authorization_url,
                  let url = URL(string: urlString)
            else {
                await MainActor.run {
                    banner = response.error ?? response.message ?? Self.garminNotReadyMessage
                }
                return
            }
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        } catch {
            await MainActor.run {
                banner = Self.userFacingGarminConnectError(error)
            }
        }
    }

    private static let garminNotReadyMessage =
        "Garmin connection is not available yet. Deploy the wearable-oauth-start edge function and add Garmin API keys in Supabase."

    private static func userFacingGarminConnectError(_ error: Error) -> String {
        let text = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        if text.contains("404") || text.contains("not found") {
            return garminNotReadyMessage
        }
        if text.contains("503") || text.contains("garmin_not_configured") {
            return "Garmin API keys are not configured on the server yet."
        }
        return error.localizedDescription
    }

    private func runSync(userId: UUID) async {
        let summary = await ExternalRouteSyncService.shared.processPendingJobs(userId: userId)
        await MainActor.run {
            lastSummary = summary
            if let first = summary.errorMessages.first, summary.failed > 0, summary.applied == 0 {
                banner = first
            }
        }
        await refreshConnection()
    }
}
