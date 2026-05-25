import MapKit
import SwiftUI

struct TerritoryMapRepresentable: UIViewRepresentable {
    var region: MKCoordinateRegion
    var cells: [TerritoryMapCellRow]
    var suggestionCells: [TerritoryExpansionRecommendationRow]
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelectCell: (TerritoryMapCellRow?) -> Void
    var onUserLocationUpdate: (CLLocationCoordinate2D?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onRegionChange: onRegionChange,
            onSelectCell: onSelectCell,
            onUserLocationUpdate: onUserLocationUpdate
        )
    }

    func makeUIView(context: Context) -> TerritoryMapContainerView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.pointOfInterestFilter = .excludingAll
            configuration.showsTraffic = false
            return configuration
        }()
        mapView.setRegion(region, animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)
        context.coordinator.mapView = mapView
        return TerritoryMapContainerView(mapView: mapView)
    }

    func updateUIView(_ container: TerritoryMapContainerView, context: Context) {
        let mapView = container.mapView
        context.coordinator.onRegionChange = onRegionChange
        context.coordinator.onSelectCell = onSelectCell
        context.coordinator.onUserLocationUpdate = onUserLocationUpdate
        context.coordinator.cells = cells

        if !context.coordinator.isUserChangingRegion,
           !TerritoryMapGeometry.regionsApproximatelyEqual(mapView.region, region) {
            context.coordinator.isProgrammaticRegionChange = true
            mapView.setRegion(region, animated: false)
            context.coordinator.isProgrammaticRegionChange = false
        }

        context.coordinator.updateTerritoryOverlays(on: mapView, cells: cells)
        context.coordinator.updateExpansionOverlays(on: mapView, suggestions: suggestionCells)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var cells: [TerritoryMapCellRow] = []
        var onRegionChange: (MKCoordinateRegion) -> Void
        var onSelectCell: (TerritoryMapCellRow?) -> Void
        var onUserLocationUpdate: (CLLocationCoordinate2D?) -> Void
        var isProgrammaticRegionChange = false
        var isUserChangingRegion = false
        private var territoryOverlays: [MKOverlay] = []
        private var expansionOverlays: [MKOverlay] = []
        private var renderedCellIds = Set<String>()
        private var renderedSuggestionIds = Set<String>()
        private var pulseTimer: Timer?

        init(
            onRegionChange: @escaping (MKCoordinateRegion) -> Void,
            onSelectCell: @escaping (TerritoryMapCellRow?) -> Void,
            onUserLocationUpdate: @escaping (CLLocationCoordinate2D?) -> Void
        ) {
            self.onRegionChange = onRegionChange
            self.onSelectCell = onSelectCell
            self.onUserLocationUpdate = onUserLocationUpdate
        }

        deinit {
            pulseTimer?.invalidate()
        }

        func updateTerritoryOverlays(on mapView: MKMapView, cells: [TerritoryMapCellRow]) {
            let nextIds = Set(cells.map(\.cell_id))
            guard nextIds != renderedCellIds else { return }
            mapView.removeOverlays(territoryOverlays)
            territoryOverlays = Self.makeTerritoryOverlays(from: cells)
            renderedCellIds = nextIds
            mapView.addOverlays(territoryOverlays, level: .aboveRoads)
        }

        func updateExpansionOverlays(
            on mapView: MKMapView,
            suggestions: [TerritoryExpansionRecommendationRow]
        ) {
            let nextIds = Set(suggestions.map(\.cell_id))
            guard nextIds != renderedSuggestionIds else { return }
            mapView.removeOverlays(expansionOverlays)
            expansionOverlays = Self.makeExpansionOverlays(from: suggestions)
            renderedSuggestionIds = nextIds
            if expansionOverlays.isEmpty {
                pulseTimer?.invalidate()
                pulseTimer = nil
            } else {
                mapView.addOverlays(expansionOverlays, level: .aboveLabels)
                startPulseTimer(on: mapView)
            }
        }

        private func startPulseTimer(on mapView: MKMapView) {
            pulseTimer?.invalidate()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self, weak mapView] _ in
                guard let self, let mapView else { return }
                for overlay in self.expansionOverlays {
                    guard let renderer = mapView.renderer(for: overlay) as? TerritoryExpansionOverlayRenderer else {
                        continue
                    }
                    renderer.togglePulsePhase()
                    renderer.setNeedsDisplay()
                }
            }
        }

        private static func makeTerritoryOverlays(from cells: [TerritoryMapCellRow]) -> [MKOverlay] {
            let grouped = Dictionary(grouping: cells) { cell in
                "\(cell.owner_user_id?.uuidString ?? "unknown")|\(cell.is_mine == true)"
            }
            return grouped.compactMap { _, cellsForStyle in
                guard let first = cellsForStyle.first,
                      let ownerId = first.owner_user_id
                else { return nil }
                let rings = normalizedRings(from: cellsForStyle.map(\.ring))
                guard !rings.isEmpty else { return nil }
                return TerritoryCellsOverlay(
                    rings: rings,
                    style: TerritoryOverlayStyle(ownerId: ownerId, isMine: first.is_mine == true)
                )
            }
        }

        private static func makeExpansionOverlays(
            from suggestions: [TerritoryExpansionRecommendationRow]
        ) -> [MKOverlay] {
            suggestions.compactMap { suggestion in
                let ring = suggestion.ring
                guard ring.count >= 3 else { return nil }
                let rings = normalizedRings(from: [ring])
                guard let firstRing = rings.first else { return nil }
                return TerritoryExpansionOverlay(rings: [firstRing])
            }
        }

        private static func normalizedRings(
            from rings: [[CLLocationCoordinate2D]]
        ) -> [[CLLocationCoordinate2D]] {
            rings.compactMap { ring -> [CLLocationCoordinate2D]? in
                guard ring.count >= 3 else { return nil }
                if let first = ring.first,
                   let last = ring.last,
                   abs(first.latitude - last.latitude) < 0.0000001,
                   abs(first.longitude - last.longitude) < 0.0000001 {
                    return Array(ring.dropLast())
                }
                return ring
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !isProgrammaticRegionChange {
                isUserChangingRegion = true
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isProgrammaticRegionChange else { return }
            isUserChangingRegion = false
            onRegionChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            onUserLocationUpdate(userLocation.location?.coordinate)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let expansionOverlay = overlay as? TerritoryExpansionOverlay {
                return TerritoryExpansionOverlayRenderer(overlay: expansionOverlay)
            }
            if let territoryOverlay = overlay as? TerritoryCellsOverlay {
                return TerritoryCellsOverlayRenderer(overlay: territoryOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView else {
                onSelectCell(nil)
                return
            }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            onSelectCell(TerritoryMapGeometry.selectedCell(at: coordinate, in: cells))
        }
    }
}

private struct TerritoryOverlayStyle {
    let ownerId: UUID
    let isMine: Bool
}

private final class TerritoryCellsOverlay: NSObject, MKOverlay {
    let rings: [[CLLocationCoordinate2D]]
    let style: TerritoryOverlayStyle
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(rings: [[CLLocationCoordinate2D]], style: TerritoryOverlayStyle) {
        self.rings = rings
        self.style = style
        let rect = TerritoryMapOverlayBounds.boundingRect(for: rings)
        self.boundingMapRect = rect
        self.coordinate = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        super.init()
    }
}

private final class TerritoryExpansionOverlay: NSObject, MKOverlay {
    let rings: [[CLLocationCoordinate2D]]
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(rings: [[CLLocationCoordinate2D]]) {
        self.rings = rings
        let rect = TerritoryMapOverlayBounds.boundingRect(for: rings)
        self.boundingMapRect = rect
        self.coordinate = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        super.init()
    }
}

private enum TerritoryMapOverlayBounds {
    static func boundingRect(for rings: [[CLLocationCoordinate2D]]) -> MKMapRect {
        var boundingRect: MKMapRect?
        for ring in rings {
            for coordinate in ring {
                let point = MKMapPoint(coordinate)
                let rect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
                boundingRect = boundingRect.map { $0.union(rect) } ?? rect
            }
        }
        return boundingRect ?? MKMapRect.world
    }
}

private final class TerritoryCellsOverlayRenderer: MKOverlayRenderer {
    private var territoryOverlay: TerritoryCellsOverlay {
        overlay as! TerritoryCellsOverlay
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let overlay = territoryOverlay
        context.setShouldAntialias(true)
        context.setFillColor(TerritoryOwnerColors.uiFill(for: overlay.style.ownerId, isMine: overlay.style.isMine).cgColor)
        context.setStrokeColor(TerritoryOwnerColors.uiFill(for: overlay.style.ownerId, isMine: overlay.style.isMine).cgColor)
        context.setLineWidth(max(1.0 / zoomScale, 0.35))
        drawRings(overlay.rings, in: context)
    }

    fileprivate func drawRings(_ rings: [[CLLocationCoordinate2D]], in context: CGContext) {
        for ring in rings {
            guard let first = ring.first else { continue }
            let firstPoint = point(for: MKMapPoint(first))
            context.beginPath()
            context.move(to: firstPoint)
            for coordinate in ring.dropFirst() {
                context.addLine(to: point(for: MKMapPoint(coordinate)))
            }
            context.closePath()
            context.drawPath(using: .fillStroke)
        }
    }
}

private final class TerritoryExpansionOverlayRenderer: MKOverlayRenderer {
    private var expansionOverlay: TerritoryExpansionOverlay {
        overlay as! TerritoryExpansionOverlay
    }

    private var pulseBright = true

    func togglePulsePhase() {
        pulseBright.toggle()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let fillAlpha: CGFloat = pulseBright ? 0.38 : 0.22
        let strokeAlpha: CGFloat = pulseBright ? 0.95 : 0.55
        context.setShouldAntialias(true)
        context.setFillColor(UIColor.systemOrange.withAlphaComponent(fillAlpha).cgColor)
        context.setStrokeColor(UIColor.systemYellow.withAlphaComponent(strokeAlpha).cgColor)
        context.setLineWidth(max(2.5 / zoomScale, 1.2))
        let rings = expansionOverlay.rings
        for ring in rings {
            guard let first = ring.first else { continue }
            let firstPoint = point(for: MKMapPoint(first))
            context.beginPath()
            context.move(to: firstPoint)
            for coordinate in ring.dropFirst() {
                context.addLine(to: point(for: MKMapPoint(coordinate)))
            }
            context.closePath()
            context.drawPath(using: .fillStroke)
        }
    }
}

final class TerritoryMapContainerView: UIView {
    let mapView: MKMapView

    init(mapView: MKMapView) {
        self.mapView = mapView
        super.init(frame: .zero)
        let trackingButton = MKUserTrackingButton(mapView: mapView)
        trackingButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.82)
        trackingButton.layer.cornerRadius = 8

        mapView.translatesAutoresizingMaskIntoConstraints = false
        trackingButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mapView)
        addSubview(trackingButton)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: topAnchor),
            mapView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomAnchor),
            trackingButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trackingButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
