import SwiftUI
import Supabase
import CoreLocation
import MapKit
import AudioToolbox
import UIKit

struct ActiveCardioWorkoutView: View {
    let workoutId: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    @AppStorage("cardioGPSProfile") private var cardioGPSProfileRaw: String = CardioGPSProfile.balanced.rawValue

    @StateObject private var gpsTracker = CardioWorkoutLocationTracker()
    @State private var showCountdown = true
    @State private var isRunning = false
    @State private var elapsedSec: Int = 0
    @State private var isSaving = false
    @State private var error: String?
    @State private var cardio: CardioRow?
    @State private var remainingSec: Int = 0
    @State private var initialTargetSec: Int = 0
    @State private var distanceText: String = ""
    @State private var hasTargetTime: Bool = false
    @State private var mode: TimerMode = .stopwatch
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showExpandedRouteMap = false
    @State private var splitEndElapsedSec: [Int] = []
    @State private var lastSplitDistanceKm: Double = 0
    @State private var lastSplitElapsedSec: Int = 0
    @State private var territoryFillRings: [[CLLocationCoordinate2D]] = []
    @State private var territoryPreviewCells: [TerritoryPreviewCell] = []
    @State private var lastTerritoryPreviewAt = Date.distantPast
    @State private var lastTerritoryPreviewPointCount = 0
    @State private var territoryPreviewTask: Task<Void, Never>?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let gpsKmSplitsLinePrefix = "[GPS] Km splits (min/km):"
    private static let gpsAvgPaceLinePrefix = "[GPS] Avg pace /km:"

    private static var gpsNoteLinePrefixes: [String] {
        [gpsKmSplitsLinePrefix, gpsAvgPaceLinePrefix]
    }

    private struct WorkoutFinishPayload: Encodable {
        let notes: String?
        let ended_at: Date
        let state: String?
    }

    private struct WorkoutSanitizePatch: Encodable {
        let ended_at: Date?
    }

    private struct WorkoutStartedAtPatch: Encodable {
        let started_at: Date
    }

    private struct WorkoutStateRow: Decodable {
        let state: String?
    }

    private var usesGPSTracking: Bool {
        guard let c = cardio else { return false }
        return cardioActivityType(for: c).prefersGPSTracking
    }

    private struct CardioRow: Decodable {
        let id: Int
        let activity_code: String?
        let modality: String?
        let distance_km: Decimal?
        let duration_sec: Int?
    }

    private enum TimerMode {
        case stopwatch
        case countdown
    }

    private var usesSwimUnitsLive: Bool {
        guard let c = cardio else { return false }
        return cardioActivityType(for: c).usesSwimDistanceAndPace
    }

    private var effectiveDistanceKm: Double {
        guard cardio != nil else { return 0 }
        if usesGPSTracking {
            return gpsTracker.distanceKm
        }
        if usesSwimUnitsLive {
            return CardioSwimDisplay.distanceKm(fromMetersText: distanceText) ?? 0
        }
        return parseDistanceKm(distanceText) ?? 0
    }

    private var gpsDistanceFormatted: String {
        if usesSwimUnitsLive {
            return CardioSwimDisplay.formatSwimDistance(km: gpsTracker.distanceKm)
        }
        return String(format: "%.2f km", gpsTracker.distanceKm)
    }

    private var livePaceFormatted: String {
        let d = effectiveDistanceKm
        guard d >= 0.001, elapsedSec > 0 else { return "—" }
        let secPerKm = Int(round(Double(elapsedSec) / d))
        if usesSwimUnitsLive {
            return CardioSwimDisplay.formatSwimPace(secPerKm: secPerKm)
        }
        return "\(formatMinSec(secPerKm))/km"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .gradientBG()

                ScrollView {
                    VStack(spacing: 24) {
                    if let c = cardio {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(activityLabel(c))
                                .font(.title2.weight(.bold))
                            HStack(spacing: 10) {
                                if let d = c.distance_km {
                                    let km = NSDecimalNumber(decimal: d).doubleValue
                                    let targetDist = cardioActivityType(for: c).usesSwimDistanceAndPace
                                        ? "Target \(CardioSwimDisplay.formatSwimDistance(km: km))"
                                        : String(format: "Target %.2f km", km)
                                    Text(targetDist)
                                }
                                if let target = c.duration_sec, target > 0 {
                                    Text("• \(formatTime(target))")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Active cardio workout")
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if hasTargetTime {
                        Picker("", selection: $mode) {
                            Text("Target time").tag(TimerMode.countdown)
                            Text("Free timer").tag(TimerMode.stopwatch)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(spacing: 8) {
                        Text(formatTime(mode == .countdown && hasTargetTime ? remainingSec : elapsedSec))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(mode == .countdown && hasTargetTime ? "Time left" : "Elapsed time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15)))

                    if cardio != nil, effectiveDistanceKm >= 0.01, elapsedSec > 0 {
                        HStack {
                            Text("Avg pace (live)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(livePaceFormatted)
                                .font(.title3.weight(.bold).monospacedDigit())
                        }
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                    }

                    if cardio != nil {
                        if usesGPSTracking {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Actual distance")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(gpsDistanceFormatted)
                                        .font(.title3.weight(.bold).monospacedDigit())
                                }
                                Text("Updates from GPS while the timer runs.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if gpsTracker.authorizationStatus == .denied
                                    || gpsTracker.authorizationStatus == .restricted {
                                    Text("Location is off. Enable it in Settings to track distance.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Actual distance")
                                    .font(.subheadline.weight(.semibold))
                                TextField(usesSwimUnitsLive ? "Distance (m)" : "Distance (km)", text: $distanceText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
                        }
                    }

                    if usesGPSTracking {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Route")
                                .font(.subheadline.weight(.semibold))
                            if gpsTracker.routeCoordinates.count >= 2 {
                                ZStack(alignment: .topTrailing) {
                                    Map(position: $mapCameraPosition) {
                                        ForEach(Array(territoryFillRings.enumerated()), id: \.offset) { _, ring in
                                            if ring.count >= 3 {
                                                MapPolygon(coordinates: ring)
                                                    .foregroundStyle(Color.green.opacity(0.22))
                                            }
                                        }
                                        ForEach(territoryPreviewCells) { cell in
                                            let ring = cell.cell_geojson?.ring ?? []
                                            if ring.count >= 3 {
                                                MapPolygon(coordinates: ring)
                                                    .foregroundStyle(Color.green.opacity(0.16))
                                            }
                                        }
                                        MapPolyline(coordinates: gpsTracker.routeCoordinates)
                                            .stroke(.blue.opacity(0.88), lineWidth: 4)
                                    }
                                    .mapStyle(.standard(elevation: .flat))
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .onChange(of: gpsTracker.routeCoordinates.count) { _, _ in
                                        fitMapToRouteIfNeeded()
                                        scheduleTerritoryPreviewRefresh()
                                    }
                                    Button {
                                        fitMapToRouteIfNeeded()
                                        showExpandedRouteMap = true
                                    } label: {
                                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .padding(8)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(8)
                                    .accessibilityLabel("Expand map")
                                }
                            } else {
                                Text("The map will draw your path while you move with GPS on.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(.white.opacity(0.12))
                                    )
                            }

                            Text("GPS & battery")
                                .font(.subheadline.weight(.semibold))
                                .padding(.top, 4)
                            Picker("GPS mode", selection: $cardioGPSProfileRaw) {
                                Text("Balanced").tag(CardioGPSProfile.balanced.rawValue)
                                Text("Battery saver").tag(CardioGPSProfile.batterySaving.rawValue)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: cardioGPSProfileRaw) { _, raw in
                                if let p = CardioGPSProfile(rawValue: raw) {
                                    gpsTracker.applyProfile(p)
                                }
                            }
                            Text("Balanced: better track and distance. Battery saver: fewer updates and coarser points (also fewer map dots).")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if gpsTracker.lastHorizontalAccuracyM > 0 {
                                Text("Last fix accuracy ~\(Int(gpsTracker.lastHorizontalAccuracyM)) m")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 16) {
                        Button {
                            if isRunning {
                                isRunning = false
                            } else {
                                isRunning = true
                            }
                        } label: {
                            Text(isRunning
                                 ? "Pause"
                                 : (elapsedSec == 0 ? "Start" : "Resume"))
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.accentColor)
                                )
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            elapsedSec = 0
                            isRunning = false
                            if usesGPSTracking {
                                gpsTracker.fullReset()
                                splitEndElapsedSec = []
                                lastSplitDistanceKm = 0
                                lastSplitElapsedSec = 0
                                mapCameraPosition = .automatic
                            }
                            if let c = cardio {
                                applyInitialDistanceFromCardio(c)
                            }
                            if mode == .countdown && hasTargetTime {
                                remainingSec = initialTargetSec
                            }
                            syncGPSTrackingState()
                        } label: {
                            Text("Reset")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 100, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.secondary, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning || elapsedSec == 0)
                    }

                    Button {
                        Task {
                            await saveAndFinishWorkout()
                        }
                    } label: {
                        Text("Finish workout")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.green.gradient)
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || elapsedSec == 0)

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(cardio != nil && !usesGPSTracking ? .interactively : .never)

                if isSaving {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("Saving workout…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                if showCountdown {
                    StartWorkoutCountdownView {
                        withAnimation(.easeInOut) {
                            showCountdown = false
                            isRunning = true
                        }
                        Task { await patchWorkoutStartedAtNow() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)
                }
            }
            .navigationTitle("Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !app.isPremium {
                    BannerAdView(adUnitID: "ca-app-pub-7676731162362384/7781347704")
                        .frame(height: 50)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
        .onDisappear {
            WorkoutLiveActivityManager.endIfAvailable()
            Task { await sanitizeEndDateIfNeededOnClose() }
        }
        .onReceive(timer) { _ in
            guard isRunning else { return }

            if mode == .countdown && hasTargetTime {
                if remainingSec > 0 {
                    remainingSec -= 1
                    elapsedSec += 1
                } else {
                    isRunning = false
                }
            } else {
                elapsedSec += 1
            }
            syncKmSplitMarkersWithDistance()
        }
        .task {
            await loadCardio()
        }
        .onAppear {
            if let p = CardioGPSProfile(rawValue: cardioGPSProfileRaw) {
                gpsTracker.applyProfile(p)
            }
        }
        .onChange(of: isRunning) { _, running in
            syncGPSTrackingState()
            if running {
                WorkoutLiveActivityManager.startIfAvailable(
                    startTime: Date().addingTimeInterval(-Double(elapsedSec)),
                    kind: .cardio
                )
            } else {
                WorkoutLiveActivityManager.endIfAvailable()
            }
        }
        .onChange(of: showCountdown) { _, _ in
            syncGPSTrackingState()
        }
        .onChange(of: gpsTracker.authorizationStatus) { _, _ in
            syncGPSTrackingState()
        }
        .onChange(of: splitEndElapsedSec.count) { old, new in
            guard usesGPSTracking, new > old else { return }
            playKmSplitFeedback()
        }
        .onReceive(gpsTracker.$distanceKm) { _ in
            guard usesGPSTracking else { return }
            syncKmSplitMarkersWithDistance()
        }
        .fullScreenCover(isPresented: $showExpandedRouteMap) {
            NavigationStack {
                ZStack {
                    Map(position: $mapCameraPosition) {
                        ForEach(Array(territoryFillRings.enumerated()), id: \.offset) { _, ring in
                            if ring.count >= 3 {
                                MapPolygon(coordinates: ring)
                                    .foregroundStyle(Color.green.opacity(0.22))
                            }
                        }
                        ForEach(territoryPreviewCells) { cell in
                            let ring = cell.cell_geojson?.ring ?? []
                            if ring.count >= 3 {
                                MapPolygon(coordinates: ring)
                                    .foregroundStyle(Color.green.opacity(0.16))
                            }
                        }
                        MapPolyline(coordinates: gpsTracker.routeCoordinates)
                            .stroke(.blue.opacity(0.88), lineWidth: 4)
                    }
                    .mapStyle(.standard(elevation: .flat))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showExpandedRouteMap = false }
                    }
                }
                .onAppear { fitMapToRouteIfNeeded() }
                .onChange(of: gpsTracker.routeCoordinates.count) { _, _ in
                    fitMapToRouteIfNeeded()
                }
            }
        }
        .overlay {
            if app.isAuthenticated, !showCountdown, !isSaving {
                MessagesFloatingButton()
                    .environmentObject(app)
                    .allowsHitTesting(true)
                    .zIndex(99)
            }
        }
    }

    private func playKmSplitFeedback() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioServicesPlaySystemSound(1104)
    }

    private func fitMapToRouteIfNeeded() {
        let coords = gpsTracker.routeCoordinates
        guard coords.count >= 2 else { return }
        var minLat = coords[0].latitude
        var maxLat = minLat
        var minLon = coords[0].longitude
        var maxLon = minLon
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.004, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.004, (maxLon - minLon) * 1.4)
        )
        mapCameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func parseDistanceKm(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v >= 0 else { return nil }
        return v
    }

    private func cardioActivityType(for row: CardioRow) -> CardioActivityType {
        let raw = (row.activity_code ?? row.modality ?? "run").lowercased()
        return CardioActivityType(rawValue: raw) ?? .run
    }

    private func applyInitialDistanceFromCardio(_ row: CardioRow) {
        let t = cardioActivityType(for: row)
        guard !t.prefersGPSTracking else { return }
        if let d = row.distance_km {
            let km = NSDecimalNumber(decimal: d).doubleValue
            if t.usesSwimDistanceAndPace {
                distanceText = CardioSwimDisplay.metersText(fromKm: km)
            } else {
                distanceText = String(format: "%.2f", km)
            }
        } else {
            distanceText = ""
        }
    }

    private func syncGPSTrackingState() {
        guard usesGPSTracking else {
            gpsTracker.pauseUpdates()
            return
        }
        if isRunning && !showCountdown {
            gpsTracker.startContinuousUpdates()
        } else {
            gpsTracker.pauseUpdates()
        }
    }

    private func syncKmSplitMarkersWithDistance() {
        guard usesGPSTracking, isRunning, !showCountdown else { return }
        let d1 = gpsTracker.distanceKm
        let t1 = elapsedSec
        let d0 = lastSplitDistanceKm
        let t0 = lastSplitElapsedSec

        if d1 < d0 - 1e-6 {
            lastSplitDistanceKm = d1
            lastSplitElapsedSec = t1
            return
        }

        var nextKm = splitEndElapsedSec.count + 1
        while Double(nextKm) <= d1 + 1e-9 {
            if Double(nextKm) > d0 - 1e-9 {
                let denom = d1 - d0
                let tAt: Int
                if denom <= 1e-9 {
                    tAt = t1
                } else {
                    let frac = (Double(nextKm) - d0) / denom
                    let clamped = max(0.0, min(1.0, frac))
                    tAt = t0 + Int(round(Double(t1 - t0) * clamped))
                }
                splitEndElapsedSec.append(tAt)
            }
            nextKm += 1
        }

        lastSplitDistanceKm = d1
        lastSplitElapsedSec = t1
    }

    private func formatMinSec(_ totalSec: Int) -> String {
        let s = max(0, totalSec)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private static func lapDeltas(from cumulative: [Int]) -> [Int] {
        var prev = 0
        var out: [Int] = []
        for c in cumulative {
            out.append(max(0, c - prev))
            prev = c
        }
        return out
    }

    private static func lapsForManualDistance(
        fullKmCount n: Int,
        elapsedSec T: Int,
        gpsCumulative: [Int]
    ) -> [Int] {
        let g = gpsCumulative.count
        var laps: [Int] = []
        var prev = 0
        let take = min(n, g)
        if take > 0 {
            for i in 0..<take {
                let cum = gpsCumulative[i]
                laps.append(max(0, cum - prev))
                prev = cum
            }
        }
        if laps.count < n {
            let rem = n - laps.count
            let tail = max(0, T - prev)
            if rem > 0 {
                let base = tail / rem
                var rest = tail % rem
                for _ in 0..<rem {
                    let v = base + (rest > 0 ? 1 : 0)
                    if rest > 0 { rest -= 1 }
                    laps.append(max(1, v))
                }
            }
        }
        return laps
    }

    private static func kmPaceSplitSecondsPerKm(
        usesGPS: Bool,
        distanceFieldUserEdited: Bool,
        manualKm: Double,
        gpsKm: Double,
        elapsedSec T: Int,
        gpsCumulative: [Int]
    ) -> [Int] {
        guard usesGPS else { return [] }

        let tolerance = 0.04
        let treatAsGpsDistance = !distanceFieldUserEdited || abs(manualKm - gpsKm) <= tolerance

        if treatAsGpsDistance {
            guard !gpsCumulative.isEmpty else { return [] }
            let laps = lapDeltas(from: gpsCumulative)
            return laps.isEmpty ? [] : laps
        }

        let n = Int(floor(manualKm))
        if n < 1 { return [] }

        let laps = lapsForManualDistance(fullKmCount: n, elapsedSec: T, gpsCumulative: gpsCumulative)
        return laps.isEmpty ? [] : laps
    }

    private func mergeWorkoutNotes(existing: String?, gpsLine: String?) -> String? {
        let trimmed = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let withoutOld = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !Self.gpsNoteLinePrefixes.contains(where: { t.hasPrefix($0) })
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var chunks: [String] = []
        if !withoutOld.isEmpty { chunks.append(withoutOld) }
        if let g = gpsLine, !g.isEmpty { chunks.append(g) }
        let merged = chunks.joined(separator: "\n\n")
        return merged.isEmpty ? nil : merged
    }

    private func loadCardio() async {
        do {
            let res = try await SupabaseManager.shared.client
                .from("cardio_sessions")
                .select("id, activity_code, modality, distance_km, duration_sec")
                .eq("workout_id", value: workoutId)
                .single()
                .execute()

            let row = try JSONDecoder.supabase().decode(CardioRow.self, from: res.data)
            await MainActor.run {
                self.cardio = row

                if let dur = row.duration_sec, dur > 0 {
                    self.hasTargetTime = true
                    self.initialTargetSec = dur
                    self.remainingSec = dur
                    self.elapsedSec = 0
                    self.mode = .countdown
                } else {
                    self.hasTargetTime = false
                    self.initialTargetSec = 0
                    self.remainingSec = 0
                    self.elapsedSec = 0
                    self.mode = .stopwatch
                }

                self.applyInitialDistanceFromCardio(row)
                if self.cardioActivityType(for: row).prefersGPSTracking {
                    self.gpsTracker.requestWhenInUseIfNeeded()
                    if let p = CardioGPSProfile(rawValue: self.cardioGPSProfileRaw) {
                        self.gpsTracker.applyProfile(p)
                    }
                }
                self.syncGPSTrackingState()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }

    private func patchWorkoutStartedAtNow() async {
        let now = Date()
        do {
            _ = try await SupabaseManager.shared.client
                .from("workouts")
                .update(WorkoutStartedAtPatch(started_at: now))
                .eq("id", value: workoutId)
                .execute()
            NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
        } catch {
        }
    }

    private func sanitizeEndDateIfNeededOnClose() async {
        let saving = await MainActor.run { isSaving }
        if saving { return }

        do {
            struct WorkoutDates: Decodable {
                let started_at: Date?
                let ended_at: Date?
            }

            let res = try await SupabaseManager.shared.client
                .from("workouts")
                .select("started_at, ended_at")
                .eq("id", value: workoutId)
                .limit(1)
                .execute()

            let arr = try JSONDecoder.supabase().decode([WorkoutDates].self, from: res.data)
            guard let w = arr.first, let start = w.started_at else { return }

            if let end = w.ended_at, end < start {
                _ = try await SupabaseManager.shared.client
                    .from("workouts")
                    .update(WorkoutSanitizePatch(ended_at: nil))
                    .eq("id", value: workoutId)
                    .execute()

                NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)
            }
        } catch {
        }
    }

    private struct CardioFinishSnapshot {
        let elapsedSec: Int
        let distanceText: String
        let splitEndElapsedSec: [Int]
        let usesGPSTracking: Bool
        let usesSwimUnits: Bool
        let routeGeoJSON: String?
        let gpsKm: Double
    }

    private func saveAndFinishWorkout() async {
        let snap = await MainActor.run {
            isSaving = true
            isRunning = false
            gpsTracker.pauseUpdates()
            let swimUnits = cardio.map { cardioActivityType(for: $0).usesSwimDistanceAndPace } ?? false
            return CardioFinishSnapshot(
                elapsedSec: elapsedSec,
                distanceText: distanceText,
                splitEndElapsedSec: splitEndElapsedSec,
                usesGPSTracking: usesGPSTracking,
                usesSwimUnits: swimUnits,
                routeGeoJSON: gpsTracker.routeGeoJSONString(),
                gpsKm: gpsTracker.distanceKm
            )
        }

        do {
            struct UpdatePayload: Encodable {
                let duration_sec: Int
                let distance_km: Decimal?
                let route_geojson: String?
            }

            let distanceDecimal: Decimal?
            let manualKm: Double
            if snap.usesGPSTracking {
                let gpsDistanceText = String(format: "%.2f", snap.gpsKm)
                distanceDecimal = Decimal(string: gpsDistanceText)
                manualKm = snap.gpsKm
            } else {
                let trimmed = snap.distanceText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",", with: ".")
                if trimmed.isEmpty {
                    distanceDecimal = nil
                    manualKm = 0
                } else if snap.usesSwimUnits, let km = CardioSwimDisplay.distanceKm(fromMetersText: trimmed) {
                    manualKm = km
                    distanceDecimal = Decimal(string: String(format: "%.6f", km))
                } else {
                    distanceDecimal = Decimal(string: trimmed)
                    manualKm = Double(trimmed) ?? 0
                }
            }

            let withRoute = UpdatePayload(
                duration_sec: snap.elapsedSec,
                distance_km: distanceDecimal,
                route_geojson: snap.routeGeoJSON
            )
            let withoutRoute = UpdatePayload(
                duration_sec: snap.elapsedSec,
                distance_km: distanceDecimal,
                route_geojson: nil
            )
            do {
                _ = try await SupabaseManager.shared.client
                    .from("cardio_sessions")
                    .update(withRoute)
                    .eq("workout_id", value: workoutId)
                    .execute()
            } catch {
                _ = try await SupabaseManager.shared.client
                    .from("cardio_sessions")
                    .update(withoutRoute)
                    .eq("workout_id", value: workoutId)
                    .execute()
            }

            let kmSplits = Self.kmPaceSplitSecondsPerKm(
                usesGPS: snap.usesGPSTracking,
                distanceFieldUserEdited: false,
                manualKm: manualKm,
                gpsKm: snap.gpsKm,
                elapsedSec: snap.elapsedSec,
                gpsCumulative: snap.splitEndElapsedSec
            )

            let sessionId = await MainActor.run { cardio?.id }
            if let sid = sessionId {
                var existingStatsData: Data?
                do {
                    let statsRes = try await SupabaseManager.shared.client
                        .from("cardio_session_stats")
                        .select("stats")
                        .eq("session_id", value: sid)
                        .single()
                        .execute()
                    existingStatsData = statsRes.data
                } catch {
                    existingStatsData = nil
                }
                let mergedStats = try CardioKmPaceSplits.mergedStatsForUpsert(
                    existingRowData: existingStatsData,
                    kmSplitsPaceSec: kmSplits
                )
                struct CardioStatsUpsert: Encodable {
                    let session_id: Int
                    let stats: AnyJSON
                }
                _ = try await SupabaseManager.shared.client
                    .from("cardio_session_stats")
                    .upsert(CardioStatsUpsert(session_id: sid, stats: mergedStats))
                    .execute()
            }

            struct NotesSelect: Decodable { let notes: String? }
            let notesRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("notes")
                .eq("id", value: workoutId)
                .single()
                .execute()
            let notesRow = try JSONDecoder.supabase().decode(NotesSelect.self, from: notesRes.data)
            let mergedNotes = mergeWorkoutNotes(existing: notesRow.notes, gpsLine: nil)
            let endTime = Date()
            let stateRes = try await SupabaseManager.shared.client
                .from("workouts")
                .select("state")
                .eq("id", value: workoutId)
                .single()
                .execute()
            let stateRow = try JSONDecoder.supabase().decode(WorkoutStateRow.self, from: stateRes.data)
            let stateToPublish = stateRow.state?.lowercased() == "planned" ? "published" : nil

            _ = try await SupabaseManager.shared.client
                .from("workouts")
                .update(WorkoutFinishPayload(notes: mergedNotes, ended_at: endTime, state: stateToPublish))
                .eq("id", value: workoutId)
                .execute()

            NotificationCenter.default.post(name: .workoutDidChange, object: workoutId)

            if snap.usesGPSTracking, snap.routeGeoJSON != nil {
                if let summary = await TerritoryCaptureClient.applyCapture(workoutId: workoutId) {
                    TerritoryCaptureClient.storeCaptureReferenceCoordinate(from: summary)
                }
            }

            await MainActor.run {
                isSaving = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                self.error = error.localizedDescription
            }
        }
    }

    private func formatTime(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private func activityLabel(_ r: CardioRow) -> String {
        let code = (r.activity_code ?? r.modality ?? "cardio")
        return code.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func scheduleTerritoryPreviewRefresh() {
        guard usesGPSTracking, isRunning else { return }
        let pointCount = gpsTracker.routeCoordinates.count
        guard pointCount >= 2 else { return }
        let now = Date()
        if now.timeIntervalSince(lastTerritoryPreviewAt) < 15,
           pointCount - lastTerritoryPreviewPointCount < 8 {
            return
        }
        lastTerritoryPreviewAt = now
        lastTerritoryPreviewPointCount = pointCount
        territoryPreviewTask?.cancel()
        territoryPreviewTask = Task {
            guard let routeJSON = gpsTracker.routeGeoJSONString() else { return }
            let display = await TerritoryCaptureClient.fetchTerritoryPreview(
                routeGeoJSON: routeJSON,
                maxCells: 200
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                territoryFillRings = display?.fillRings ?? []
                territoryPreviewCells = display?.sampleCells ?? []
            }
        }
    }
}
