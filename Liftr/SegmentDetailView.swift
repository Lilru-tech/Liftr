import SwiftUI
import Supabase
import MapKit
import CoreLocation
import UIKit

private enum SegmentLineGeoJSON {
    private struct LineStringBody: Decodable {
        let type: String
        let coordinates: [[Double]]
    }

    static func coordinates(from json: String?) -> [CLLocationCoordinate2D] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        guard let obj = try? JSONDecoder().decode(LineStringBody.self, from: data),
              obj.type.lowercased() == "linestring",
              obj.coordinates.count >= 2
        else { return [] }
        return obj.coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            let lon = pair[0]
            let lat = pair[1]
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
}

private struct ExpandablePolylineRouteMap: View {
    let coordinates: [CLLocationCoordinate2D]
    var fullscreenNavigationTitle: String = "Segment"

    @State private var position: MapCameraPosition = .automatic
    @State private var showExpanded = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue.opacity(0.88), lineWidth: 4)
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onAppear { fitCamera() }
            .onChange(of: coordinates.count) { _, _ in fitCamera() }
            Button {
                fitCamera()
                showExpanded = true
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
        .fullScreenCover(isPresented: $showExpanded) {
            NavigationStack {
                ZStack {
                    Map(position: $position) {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.blue.opacity(0.88), lineWidth: 4)
                    }
                    .mapStyle(.standard(elevation: .flat))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(fullscreenNavigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showExpanded = false }
                    }
                }
                .onAppear { fitCamera() }
                .onChange(of: coordinates.count) { _, _ in fitCamera() }
            }
        }
    }

    private func fitCamera() {
        guard coordinates.count >= 2 else { return }
        var minLat = coordinates[0].latitude
        var maxLat = minLat
        var minLon = coordinates[0].longitude
        var maxLon = minLon
        for c in coordinates {
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
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

struct CreateSegmentFromWorkoutSheet: View {
    let workoutId: Int
    var onCreated: (UUID) -> Void
    var onOpenExistingSegment: ((UUID) -> Void)? = nil
    var onCancel: () -> Void

    @State private var routeCoordinates: [CLLocationCoordinate2D]
    @State private var name: String = "Segment"
    @State private var startFraction: Double = 0
    @State private var endFraction: Double = 1
    @State private var busy = false
    @State private var isOptimizingRoute = false
    @State private var error: String?
    @State private var routeOptimizeBanner: String?
    @State private var mapCamera: MapCameraPosition = .automatic
    @State private var mapPickPhase: MapPickPhase = .start
    @State private var duplicateSegmentAlertId: UUID?
    @State private var showExpandedPickMap = false

    init(
        workoutId: Int,
        initialRouteCoordinates: [CLLocationCoordinate2D],
        onCreated: @escaping (UUID) -> Void,
        onOpenExistingSegment: ((UUID) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.workoutId = workoutId
        self.onCreated = onCreated
        self.onOpenExistingSegment = onOpenExistingSegment
        self.onCancel = onCancel
        _routeCoordinates = State(initialValue: initialRouteCoordinates)
    }

    private enum MapPickPhase: Hashable {
        case start
        case end
    }

    private struct CreateSegmentRpc: Encodable {
        let p_workout_id: Int
        let p_name: String
        let p_start_fraction: Double
        let p_end_fraction: Double
        let p_buffer_m: Double
    }

    private var canUseRouteMap: Bool { routeCoordinates.count >= 2 }
    private var segmentFieldFill: Color { Color.primary.opacity(0.06) }
    private var segmentFieldStroke: Color { Color.primary.opacity(0.10) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(segmentFieldFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(segmentFieldStroke, lineWidth: 0.8)
                        )
                } footer: {
                    Text("When you publish a cardio workout, matching segments are filled in automatically if your route passes through them—you do not need to create the same segment again.")
                        .font(.footnote)
                }
                .listRowBackground(Color.clear)
                if canUseRouteMap {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            mapPickHeader
                            routeMapTapSection
                            Picker("Next tap sets", selection: $mapPickPhase) {
                                Text("Start").tag(MapPickPhase.start)
                                Text("End").tag(MapPickPhase.end)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(segmentFieldFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(segmentFieldStroke, lineWidth: 0.8)
                        )
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let routeOptimizeBanner {
                                Text(routeOptimizeBanner)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Tap the route, or drag the green (start) and red (end) pins to snap along the path. Fine tune sliders use the same length fractions as the server.")
                                .font(.footnote)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    DisclosureGroup("Fine tune (\(Int(startFraction * 100))% → \(Int(endFraction * 100))%)") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Start along route: \(Int(startFraction * 100))%")
                                Slider(value: $startFraction, in: 0...0.99, step: 0.005)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("End along route: \(Int(endFraction * 100))%")
                                Slider(value: $endFraction, in: 0.01...1, step: 0.005)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(segmentFieldFill)
                            .padding(.vertical, 4)
                    )
                } footer: {
                    Text("Uses the published route GeoJSON. Time on the leaderboard is estimated from session duration until per-point timestamps exist.")
                        .font(.footnote)
                }
                .listRowBackground(Color.clear)
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Create segment")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if canUseRouteMap {
                    mapCamera = cameraForRoute(routeCoordinates)
                }
            }
            .task {
                await optimizeDenseRouteIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(
                            busy || isOptimizingRoute
                                || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || startFraction >= endFraction
                        )
                }
            }
            .alert("Similar segment already exists", isPresented: Binding(
                get: { duplicateSegmentAlertId != nil },
                set: { if !$0 { duplicateSegmentAlertId = nil } }
            )) {
                Button("Open existing segment") {
                    if let id = duplicateSegmentAlertId {
                        onOpenExistingSegment?(id)
                    }
                    duplicateSegmentAlertId = nil
                }
                Button("OK", role: .cancel) {
                    duplicateSegmentAlertId = nil
                }
            } message: {
                Text("This stretch is already covered by a published segment. Other athletes get matched automatically when they publish a compatible route.")
            }
            .overlay {
                if busy || isOptimizingRoute {
                    ZStack {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                        ProgressView(isOptimizingRoute ? "Optimizing route…" : "Creating segment…")
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .allowsHitTesting(true)
                }
            }
        }
        .gradientBG()
    }

    private struct CardioRouteGeoJsonOnlyPatch: Encodable {
        let route_geojson: String
    }

    private func optimizeDenseRouteIfNeeded() async {
        let count = routeCoordinates.count
        guard count > RouteLineStringDecimation.maxStoredCoordinates else { return }
        await MainActor.run {
            isOptimizingRoute = true
            error = nil
        }
        let simplified = RouteLineStringDecimation.decimate(routeCoordinates)
        guard let json = RouteLineStringDecimation.encodeGeoJSONLineString(simplified) else {
            await MainActor.run { isOptimizingRoute = false }
            return
        }
        do {
            try await SupabaseManager.shared.client
                .from("cardio_sessions")
                .update(CardioRouteGeoJsonOnlyPatch(route_geojson: json))
                .eq("workout_id", value: workoutId)
                .execute()
            await MainActor.run {
                routeCoordinates = simplified
                startFraction = 0
                endFraction = 1
                mapCamera = cameraForRoute(simplified)
                routeOptimizeBanner = "Your stored route had \(count) GPS points; it was simplified so segment creation can finish in time."
                isOptimizingRoute = false
            }
        } catch {
            await MainActor.run {
                isOptimizingRoute = false
                self.error = (self.error.map { $0 + "\n" } ?? "")
                    + "Could not simplify the stored route (\(error.localizedDescription)). Segment creation may still time out—try a shorter run or ask your admin to tune the database."
            }
        }
    }

    @ViewBuilder
    private var mapPickHeader: some View {
        Text(mapPickPhase == .start ? "Tap the route or drag the green pin for start" : "Tap the route or drag the red pin for end")
            .font(.subheadline)
    }

    private var routeMapTapSection: some View {
        ZStack(alignment: .topTrailing) {
            segmentPickMap(compact: true)
            Button {
                showExpandedPickMap = true
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
        .fullScreenCover(isPresented: $showExpandedPickMap) {
            NavigationStack {
                ZStack {
                    segmentPickMap(compact: false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showExpandedPickMap = false }
                    }
                }
            }
        }
    }

    private func markerDragGesture(proxy: MapProxy, phase: MapPickPhase) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { g in
                guard let coord = proxy.convert(g.location, from: .global) else { return }
                applyCoordinateForPhase(coord, phase: phase)
            }
    }

    private func segmentPickMap(compact: Bool) -> some View {
        MapReader { proxy in
            Group {
                if compact {
                    Map(position: $mapCamera) {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(.blue.opacity(0.88), lineWidth: 4)
                        if let c = markerCoord(forFraction: startFraction) {
                            Annotation("Start", coordinate: c) {
                                segmentMarkerHandle(color: .green)
                                    .highPriorityGesture(markerDragGesture(proxy: proxy, phase: .start))
                            }
                        }
                        if let c = markerCoord(forFraction: endFraction) {
                            Annotation("End", coordinate: c) {
                                segmentMarkerHandle(color: .red)
                                    .highPriorityGesture(markerDragGesture(proxy: proxy, phase: .end))
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        handleSegmentMapTap(proxy: proxy, point: point)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Map(position: $mapCamera) {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(.blue.opacity(0.88), lineWidth: 4)
                        if let c = markerCoord(forFraction: startFraction) {
                            Annotation("Start", coordinate: c) {
                                segmentMarkerHandle(color: .green)
                                    .highPriorityGesture(markerDragGesture(proxy: proxy, phase: .start))
                            }
                        }
                        if let c = markerCoord(forFraction: endFraction) {
                            Annotation("End", coordinate: c) {
                                segmentMarkerHandle(color: .red)
                                    .highPriorityGesture(markerDragGesture(proxy: proxy, phase: .end))
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        handleSegmentMapTap(proxy: proxy, point: point)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func handleSegmentMapTap(proxy: MapProxy, point: CGPoint) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        applyCoordinateForPhase(coord, phase: mapPickPhase)
    }

    private func applyCoordinateForPhase(_ coord: CLLocationCoordinate2D, phase: MapPickPhase) {
        let idx = Self.nearestVertexIndex(coords: routeCoordinates, tap: coord)
        let f = lengthFraction(atVertexIndex: idx, coords: routeCoordinates)
        switch phase {
        case .start:
            startFraction = min(1, max(0, f))
        case .end:
            endFraction = min(1, max(0, f))
        }
    }

    @ViewBuilder
    private func segmentMarkerHandle(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .padding(12)
            .contentShape(Circle())
    }

    private func markerCoord(forFraction frac: Double) -> CLLocationCoordinate2D? {
        coordinateAlongRoute(coords: routeCoordinates, fraction: frac)
    }

    private func cameraForRoute(_ coords: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard let first = coords.first else { return .automatic }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.004, (maxLat - minLat) * 1.35),
            longitudeDelta: max(0.004, (maxLon - minLon) * 1.35)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    private static func nearestVertexIndex(coords: [CLLocationCoordinate2D], tap: CLLocationCoordinate2D) -> Int {
        guard !coords.isEmpty else { return 0 }
        let tapLoc = CLLocation(latitude: tap.latitude, longitude: tap.longitude)
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        for i in coords.indices {
            let c = coords[i]
            let d = tapLoc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < bestD {
                bestD = d
                best = i
            }
        }
        return best
    }

    private func lengthFraction(atVertexIndex i: Int, coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return 0 }
        let j = min(max(i, 0), coords.count - 1)
        var total = 0.0
        var cum = 0.0
        for k in 1..<coords.count {
            let a = CLLocation(latitude: coords[k - 1].latitude, longitude: coords[k - 1].longitude)
            let b = CLLocation(latitude: coords[k].latitude, longitude: coords[k].longitude)
            let seg = a.distance(from: b)
            if k <= j {
                cum += seg
            }
            total += seg
        }
        guard total > 0 else { return Double(j) / Double(coords.count - 1) }
        return min(1, max(0, cum / total))
    }

    private func coordinateAlongRoute(coords: [CLLocationCoordinate2D], fraction raw: Double) -> CLLocationCoordinate2D? {
        guard coords.count >= 2 else { return nil }
        let f = min(1, max(0, raw))
        var total = 0.0
        var segLens: [Double] = []
        segLens.reserveCapacity(coords.count - 1)
        for k in 1..<coords.count {
            let a = CLLocation(latitude: coords[k - 1].latitude, longitude: coords[k - 1].longitude)
            let b = CLLocation(latitude: coords[k].latitude, longitude: coords[k].longitude)
            let seg = a.distance(from: b)
            segLens.append(seg)
            total += seg
        }
        guard total > 0 else { return coords.first }
        let target = f * total
        var acc = 0.0
        for k in 0..<segLens.count {
            let L = segLens[k]
            if acc + L >= target {
                let t = L > 0 ? (target - acc) / L : 0
                let p0 = coords[k]
                let p1 = coords[k + 1]
                let lat = p0.latitude + (p1.latitude - p0.latitude) * t
                let lon = p0.longitude + (p1.longitude - p0.longitude) * t
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            acc += L
        }
        return coords.last
    }

    private func create() async {
        await MainActor.run {
            busy = true
            error = nil
        }
        do {
            let params = CreateSegmentRpc(
                p_workout_id: workoutId,
                p_name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                p_start_fraction: startFraction,
                p_end_fraction: endFraction,
                p_buffer_m: 25
            )
            let res = try await SupabaseManager.shared.client
                .rpc("create_segment_from_workout_v1", params: params)
                .execute()
            let idStr: String
            if let s = try? JSONDecoder().decode(String.self, from: res.data) {
                idStr = s
            } else if let arr = try? JSONDecoder().decode([String].self, from: res.data), let first = arr.first {
                idStr = first
            } else {
                throw NSError(domain: "Segment", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unexpected create response"])
            }
            let trimmed = idStr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let uuid = UUID(uuidString: trimmed) else {
                throw NSError(domain: "Segment", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid segment id"])
            }
            await MainActor.run {
                busy = false
                onCreated(uuid)
            }
        } catch {
            if let existing = Self.duplicateSegmentId(from: error) {
                await MainActor.run {
                    busy = false
                    duplicateSegmentAlertId = existing
                }
                return
            }
            if Self.errorBlob(from: error).localizedCaseInsensitiveContains("duplicate_segment") {
                await MainActor.run {
                    busy = false
                    self.error = Self.friendlyDuplicateSegmentMessage
                }
                return
            }
            await MainActor.run {
                busy = false
                self.error = error.localizedDescription
            }
        }
    }

    private static let friendlyDuplicateSegmentMessage =
        "This part of the route already matches a published segment. Others get matched automatically when they publish a compatible run—you do not need to create it again."

    private static func errorBlob(from error: Error) -> String {
        var parts: [String] = []
        if let pe = error as? PostgrestError {
            [pe.message, pe.hint, pe.detail].forEach { s in
                if let s, !s.isEmpty { parts.append(s) }
            }
        }
        parts.append(error.localizedDescription)
        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
            parts.append(underlying.localizedDescription)
        }
        return parts.joined(separator: " ")
    }

    private static func duplicateSegmentId(from error: Error) -> UUID? {
        let blob = errorBlob(from: error)
        guard blob.localizedCaseInsensitiveContains("duplicate_segment") else { return nil }
        if let pe = error as? PostgrestError,
           let h = pe.hint?.trimmingCharacters(in: .whitespacesAndNewlines),
           let u = UUID(uuidString: h) {
            return u
        }
        let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: blob, range: NSRange(blob.startIndex..., in: blob)),
              let r = Range(m.range, in: blob) else { return nil }
        return UUID(uuidString: String(blob[r]))
    }
}

private struct ShareSegmentChatToken: Identifiable {
    let id = UUID()
    let snapshot: SegmentShareSnapshot
}

struct SegmentDetailView: View {
    let segmentId: UUID
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    private struct SegmentDetailRow: Decodable {
        let id: UUID
        let name: String
        let buffer_m: Double
        let status: String
        let geojson: String?
        let created_by: UUID?
        let foreign_efforts_count: Int64
        let segment_length_m: Double?
        let center_lat: Double?
        let center_lon: Double?
        let leaderboard_effort_count: Int64?
        let leaderboard_athlete_count: Int64?
        let confidence_avg: Double?
        let confidence_min: Double?
        let confidence_max: Double?
        let viewer_best_elapsed_sec: Int?
        let viewer_best_workout_id: Int?
    }

    private struct LeaderRow: Decodable, Identifiable {
        var id: Int { workout_id }

        let rank: Int
        let user_id: UUID
        let username: String?
        let avatar_url: String?
        let elapsed_sec: Int
        let workout_id: Int
        let matched_at: Date?
        let effort_at: Date?
        let confidence: Double?
        let route_coverage: Double?
        let is_source_workout: Bool?

        static func leaderboardDisplayRows(from rows: [LeaderRow]) -> [LeaderRow] {
            let sorted = rows.sorted { $0.elapsed_sec < $1.elapsed_sec }
            return sorted.enumerated().map { i, r in
                LeaderRow(
                    rank: i + 1,
                    user_id: r.user_id,
                    username: r.username,
                    avatar_url: r.avatar_url,
                    elapsed_sec: r.elapsed_sec,
                    workout_id: r.workout_id,
                    matched_at: r.matched_at,
                    effort_at: r.effort_at,
                    confidence: r.confidence,
                    route_coverage: r.route_coverage,
                    is_source_workout: r.is_source_workout
                )
            }
        }

        var displayOverlapFraction: Double? {
            if let rc = route_coverage, rc > 0, rc <= 1 { return rc }
            if let c = confidence, c > 0, c <= 1 { return c }
            return nil
        }
    }

    private static let effortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func formatSegmentElapsed(_ sec: Int) -> String {
        if sec < 60 { return "\(sec)s" }
        if sec < 3600 {
            return String(format: "%d:%02d", sec / 60, sec % 60)
        }
        let h = sec / 3600
        let rem = sec % 3600
        return String(format: "%d:%02d:%02d", h, rem / 60, rem % 60)
    }

    @State private var detail: SegmentDetailRow?
    @State private var leaders: [LeaderRow] = []
    @State private var loading = true
    @State private var error: String?
    @State private var sessionUserId: UUID?
    @State private var showRenameSheet = false
    @State private var renameDraft: String = ""
    @State private var ownerBusy = false
    @State private var ownerError: String?
    @State private var showDeleteConfirm = false
    @State private var shareSegmentToken: ShareSegmentChatToken?

    private var coords: [CLLocationCoordinate2D] {
        SegmentLineGeoJSON.coordinates(from: detail?.geojson)
    }

    private var displayViewerPersonalBest: (elapsedSec: Int, workoutId: Int)? {
        guard let uid = sessionUserId else { return nil }
        let mine = leaders.filter { $0.user_id == uid }
        return mine.min(by: { $0.elapsed_sec < $1.elapsed_sec })
            .map { ($0.elapsed_sec, $0.workout_id) }
    }

    private func mapsCenterCoordinate() -> CLLocationCoordinate2D? {
        if let lat = detail?.center_lat, let lon = detail?.center_lon,
           lat.isFinite, lon.isFinite, (-90 ... 90).contains(lat), (-180 ... 180).contains(lon) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard !coords.isEmpty else { return nil }
        let sumLat = coords.reduce(0.0) { $0 + $1.latitude }
        let sumLon = coords.reduce(0.0) { $0 + $1.longitude }
        let n = Double(coords.count)
        return CLLocationCoordinate2D(latitude: sumLat / n, longitude: sumLon / n)
    }

    private func openSegmentInAppleMaps() {
        guard let c = mapsCenterCoordinate() else { return }
        let q = (detail?.name ?? "Segment")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Segment"
        let urlStr = "http://maps.apple.com/?ll=\(c.latitude),\(c.longitude)&q=\(q)&z=16"
        guard let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    private var ownerFieldFill: Color { Color.primary.opacity(0.06) }
    private var ownerFieldStroke: Color { Color.primary.opacity(0.10) }

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                Text(error).foregroundStyle(.secondary).padding()
            } else if detail == nil {
                Text("Segment not found").foregroundStyle(.secondary).padding()
            } else {
                content
            }
        }
        .navigationTitle(detail?.name ?? "Segment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if detail != nil {
                        Button {
                            Task { await beginShareSegment() }
                        } label: {
                            Image(systemName: "paperplane")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share segment in chat")
                    }
                    if let d = detail, let me = sessionUserId, d.created_by == me {
                        Menu {
                            Button("Rename") {
                                renameDraft = d.name
                                showRenameSheet = true
                            }
                            if d.foreign_efforts_count == 0 {
                                Button("Delete segment", role: .destructive) {
                                    showDeleteConfirm = true
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .tint(.primary)
                        .accessibilityLabel("Segment options")
                        .disabled(ownerBusy)
                    }
                    if onClose != nil {
                        Button("Done") { onClose?() }
                    }
                }
            }
        }
        .task {
            if let s = try? await SupabaseManager.shared.client.auth.session {
                sessionUserId = s.user.id
            }
            await load()
        }
        .sheet(item: $shareSegmentToken) { token in
            ShareSegmentToChatSheet(snapshot: token.snapshot) {}
                .environmentObject(app)
                .gradientBG()
        }
        .sheet(isPresented: $showRenameSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $renameDraft)
                            .textFieldStyle(.plain)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(ownerFieldFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(ownerFieldStroke, lineWidth: 0.8)
                            )
                    }
                    .listRowBackground(Color.clear)
                    if let ownerError {
                        Section { Text(ownerError).foregroundStyle(.red) }
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Rename segment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showRenameSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await saveRename() } }
                            .disabled(ownerBusy || renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .gradientBG()
            .presentationDetents([.medium])
            .presentationBackground(.clear)
        }
        .confirmationDialog(
            "Delete this segment?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteSegment() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. You can delete only while no other athlete has a matched effort on this segment.")
        }
        .gradientBG()
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let ownerError {
                    Text(ownerError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if coords.count >= 2 {
                    ExpandablePolylineRouteMap(coordinates: coords)
                }
                if let d = detail {
                    segmentStatsSection(d)
                    Button(action: openSegmentInAppleMaps) {
                        Label("Open in Maps", systemImage: "map")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(mapsCenterCoordinate() == nil)
                    if let pb = displayViewerPersonalBest, pb.elapsedSec > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your best on this segment")
                                    .font(.caption.weight(.semibold))
                                Text(Self.formatSegmentElapsed(pb.elapsedSec))
                                    .font(.subheadline.monospacedDigit())
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text(
                        "Times are estimates along the route until per-point timestamps are available for matching."
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                Text("Leaderboard").font(.headline)
                if leaders.isEmpty {
                    Text("No efforts yet").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(leaders) { row in
                        let isYourBestEffort = displayViewerPersonalBest?.workoutId == row.workout_id
                        NavigationLink {
                            WorkoutDetailView(workoutId: row.workout_id, ownerId: row.user_id)
                                .environmentObject(app)
                                .gradientBG()
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Text("#\(row.rank)")
                                    .font(.subheadline.monospacedDigit())
                                    .frame(width: 36, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.username ?? "\(String(row.user_id.uuidString.prefix(8)))…")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(Self.formatSegmentElapsed(row.elapsed_sec))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if let at = row.effort_at {
                                        Text(Self.effortDayFormatter.string(from: at))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    if let frac = row.displayOverlapFraction {
                                        Text("Segment overlap ~\(Int((frac * 100).rounded()))%")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    if row.is_source_workout == true {
                                        Text("Defined from this workout’s route")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isYourBestEffort ? Color.accentColor : Color.clear,
                                    lineWidth: isYourBestEffort ? 2 : 0
                                )
                        )
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func segmentStatsSection(_ d: SegmentDetailRow) -> some View {
        let lenKm: String = {
            guard let m = d.segment_length_m, m > 0 else { return "—" }
            return String(format: "%.2f km", m / 1000)
        }()
        let efforts = d.leaderboard_effort_count ?? 0
        let athletes = d.leaderboard_athlete_count ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text("About this segment").font(.subheadline.weight(.semibold))
            Text("Length \(lenKm) · buffer \(Int(d.buffer_m)) m")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(athletes) athletes · \(efforts) leaderboard efforts (published cardio)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let avg = d.confidence_avg, avg > 0, avg <= 1 {
                let pct = Int((avg * 100).rounded())
                if let lo = d.confidence_min, let hi = d.confidence_max,
                   lo > 0, hi > 0, lo <= 1, hi <= 1, hi > lo {
                    Text("Typical segment overlap ~\(pct)% (range \(Int((lo * 100).rounded()))–\(Int((hi * 100).rounded()))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Typical segment overlap ~\(pct)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private struct UpdateNameRpc: Encodable {
        let p_segment_id: UUID
        let p_name: String
    }

    private struct DeleteSegmentRpc: Encodable {
        let p_segment_id: UUID
    }

    private func saveRename() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await MainActor.run { ownerBusy = true; ownerError = nil }
        do {
            let params = UpdateNameRpc(p_segment_id: segmentId, p_name: trimmed)
            _ = try await SupabaseManager.shared.client
                .rpc("update_my_segment_name_v1", params: params)
                .execute()
            await MainActor.run {
                ownerBusy = false
                showRenameSheet = false
            }
            await load()
        } catch {
            await MainActor.run {
                ownerBusy = false
                ownerError = error.localizedDescription
            }
        }
    }

    private func deleteSegment() async {
        await MainActor.run { ownerBusy = true; ownerError = nil }
        do {
            let params = DeleteSegmentRpc(p_segment_id: segmentId)
            _ = try await SupabaseManager.shared.client
                .rpc("delete_my_segment_v1", params: params)
                .execute()
            await MainActor.run {
                ownerBusy = false
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                ownerBusy = false
                ownerError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func beginShareSegment() async {
        guard let d = detail else { return }
        var prof: ChatProfile?
        if let cid = d.created_by {
            prof = try? await ChatService.fetchProfile(userId: cid)
        }
        let snap = SegmentShareSnapshot(
            v: 1,
            type: "segment_share",
            segment_id: d.id.uuidString,
            name: d.name,
            segment_length_m: d.segment_length_m,
            leaderboard_effort_count: d.leaderboard_effort_count,
            owner_user_id: d.created_by,
            owner_username: prof?.username,
            owner_avatar_url: prof?.avatar_url
        )
        shareSegmentToken = ShareSegmentChatToken(snapshot: snap)
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            var p1: [String: AnyJSON] = [:]
            p1["p_segment_id"] = (try? AnyJSON(segmentId.uuidString)) ?? .null
            let dRes = try await SupabaseManager.shared.client
                .rpc("get_segment_detail_v1", params: p1)
                .execute()
            let dRows = try JSONDecoder.supabase().decode([SegmentDetailRow].self, from: dRes.data)

            var p2: [String: AnyJSON] = [:]
            p2["p_segment_id"] = (try? AnyJSON(segmentId.uuidString)) ?? .null
            p2["p_limit"] = AnyJSON(50)
            let lRes = try await SupabaseManager.shared.client
                .rpc("get_segment_leaderboard_v1", params: p2)
                .execute()
            let lRows = try JSONDecoder.supabase().decode([LeaderRow].self, from: lRes.data)
            let displayLeaders = LeaderRow.leaderboardDisplayRows(from: lRows)

            await MainActor.run {
                detail = dRows.first
                leaders = displayLeaders
                loading = false
            }
        } catch {
            await MainActor.run {
                loading = false
                self.error = error.localizedDescription
            }
        }
    }
}
