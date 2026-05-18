import MapKit
import SwiftUI

struct TerritoryMapRepresentable: UIViewRepresentable {
    var region: MKCoordinateRegion
    var cells: [TerritoryMapCellRow]
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelectCell: (TerritoryMapCellRow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRegionChange: onRegionChange, onSelectCell: onSelectCell)
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
        context.coordinator.cells = cells

        if !context.coordinator.isUserChangingRegion,
           !TerritoryMapGeometry.regionsApproximatelyEqual(mapView.region, region) {
            context.coordinator.isProgrammaticRegionChange = true
            mapView.setRegion(region, animated: false)
            context.coordinator.isProgrammaticRegionChange = false
        }

        context.coordinator.updateOverlays(on: mapView, cells: cells)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var cells: [TerritoryMapCellRow] = []
        var onRegionChange: (MKCoordinateRegion) -> Void
        var onSelectCell: (TerritoryMapCellRow?) -> Void
        var isProgrammaticRegionChange = false
        var isUserChangingRegion = false
        private var territoryOverlays: [MKOverlay] = []
        private var renderedCellIds = Set<String>()

        init(
            onRegionChange: @escaping (MKCoordinateRegion) -> Void,
            onSelectCell: @escaping (TerritoryMapCellRow?) -> Void
        ) {
            self.onRegionChange = onRegionChange
            self.onSelectCell = onSelectCell
        }

        func updateOverlays(on mapView: MKMapView, cells: [TerritoryMapCellRow]) {
            let nextIds = Set(cells.map(\.cell_id))
            guard nextIds != renderedCellIds else {
                print("[TerritoryMap][Renderer] skip overlay update cells=\(cells.count)")
                return
            }
            mapView.removeOverlays(territoryOverlays)
            territoryOverlays = Self.makeOverlays(from: cells)
            renderedCellIds = nextIds
            mapView.addOverlays(territoryOverlays, level: .aboveRoads)
            print("[TerritoryMap][Renderer] update cells=\(cells.count) overlays=\(territoryOverlays.count) owners=\(Set(cells.compactMap(\.owner_user_id)).count)")
        }

        private static func makeOverlays(from cells: [TerritoryMapCellRow]) -> [MKOverlay] {
            let grouped = Dictionary(grouping: cells) { cell in
                "\(cell.owner_user_id?.uuidString ?? "unknown")|\(cell.is_mine == true)"
            }
            return grouped.compactMap { _, cellsForStyle in
                guard let first = cellsForStyle.first,
                      let ownerId = first.owner_user_id
                else { return nil }
                let rings = cellsForStyle.compactMap { cell -> [CLLocationCoordinate2D]? in
                    let ring = cell.ring
                    guard ring.count >= 3 else { return nil }
                    if let first = ring.first,
                       let last = ring.last,
                       abs(first.latitude - last.latitude) < 0.0000001,
                       abs(first.longitude - last.longitude) < 0.0000001 {
                        return Array(ring.dropLast())
                    }
                    return ring
                }
                guard !rings.isEmpty else { return nil }
                return TerritoryCellsOverlay(
                    rings: rings,
                    style: TerritoryOverlayStyle(ownerId: ownerId, isMine: first.is_mine == true)
                )
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
            print("[TerritoryMap][Renderer] regionDidChange center=(\(mapView.region.center.latitude),\(mapView.region.center.longitude)) span=(\(mapView.region.span.latitudeDelta),\(mapView.region.span.longitudeDelta))")
            onRegionChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let territoryOverlay = overlay as? TerritoryCellsOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            return TerritoryCellsOverlayRenderer(overlay: territoryOverlay)
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

        var boundingRect: MKMapRect?
        for ring in rings {
            for coordinate in ring {
                let point = MKMapPoint(coordinate)
                let rect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
                boundingRect = boundingRect.map { $0.union(rect) } ?? rect
            }
        }

        let rect = boundingRect ?? MKMapRect.world
        self.boundingMapRect = rect
        self.coordinate = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        super.init()
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

        for ring in overlay.rings {
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
