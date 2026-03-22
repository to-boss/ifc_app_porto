import Foundation
import ARKit
import RealityKit
import Combine
import os

private let logger = Logger(subsystem: "com.ifcar.viewer", category: "ARSession")

enum ARState {
    case coaching
    case aligning
    case calibrating
    case loading
    case contentPlaced
}

@MainActor
class ARSessionManager: ObservableObject {
    @Published var state: ARState = .coaching
    @Published var gridRotation: Float = 0
    @Published var alignmentPointCount: Int = 0
    @Published var loadingError: String?
    @Published var debugLog: [String] = []

    func log(_ msg: String) {
        logger.info("\(msg)")
        debugLog.append(msg)
        if debugLog.count > 30 { debugLog.removeFirst() }
    }

    weak var arView: ARView?

    private var floorAnchor: AnchorEntity?
    private var gridEntity: FloorGridEntity?

    // Alignment
    private var alignmentPoints: [SIMD3<Float>] = []
    private var alignmentMarkers: [AnchorEntity] = []
    private var alignmentLine: AnchorEntity?

    private var modelAnchor: AnchorEntity?

    let gridSpacing: Float = 0.5

    // MARK: - Coaching

    func coachingDidFinish() {
        if state == .coaching {
            state = .aligning
        }
    }

    // MARK: - Plane Detection

    func handlePlaneAnchorAdded(_ anchor: ARPlaneAnchor) {
        guard anchor.alignment == .horizontal else { return }
        handleFloorDetected(anchor)
    }

    func handlePlaneAnchorUpdated(_ anchor: ARPlaneAnchor) {
        // Floor height will be set precisely from alignment taps
    }

    // MARK: - Floor

    private func handleFloorDetected(_ anchor: ARPlaneAnchor) {
        guard floorAnchor == nil else { return }

        let y = anchor.transform.columns.3.y
        let position = SIMD3<Float>(0, y, 0)

        let anchorEntity = AnchorEntity(world: position)
        let grid = FloorGridEntity(spacing: gridSpacing)
        anchorEntity.addChild(grid)
        arView?.scene.addAnchor(anchorEntity)

        floorAnchor = anchorEntity
        gridEntity = grid

        if state == .coaching || state == .aligning {
            state = .aligning
        }
    }

    // MARK: - Tap Handling

    func handleTap(at point: CGPoint) {
        guard let arView = arView else { return }

        if state == .aligning {
            handleAlignmentTap(at: point)
        }
    }

    // MARK: - 2-Point Wall Alignment

    private func handleAlignmentTap(at point: CGPoint) {
        guard let arView = arView else { return }

        let results = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
        guard let result = results.first else { return }

        let worldPos = SIMD3<Float>(
            result.worldTransform.columns.3.x,
            result.worldTransform.columns.3.y,
            result.worldTransform.columns.3.z
        )

        alignmentPoints.append(worldPos)
        placeAlignmentMarker(at: worldPos)
        alignmentPointCount = alignmentPoints.count

        if alignmentPoints.count == 2 {
            let p1 = alignmentPoints[0]
            let p2 = alignmentPoints[1]

            // Draw line between points
            drawAlignmentLine(from: p1, to: p2)

            // Compute grid rotation from the line direction
            let dx = p2.x - p1.x
            let dz = p2.z - p1.z
            gridRotation = atan2(dz, dx)
            updateGridRotation()

            // Set floor height from the average of the two tapped points
            let floorY = (p1.y + p2.y) / 2
            floorAnchor?.position.y = floorY

            state = .calibrating
        }
    }

    private func placeAlignmentMarker(at position: SIMD3<Float>) {
        guard let arView = arView else { return }

        var material = UnlitMaterial()
        material.color = .init(tint: .cyan)

        // Floor dot — flat disc
        let disc = MeshResource.generateCylinder(height: 0.005, radius: 0.04)
        let discEntity = ModelEntity(mesh: disc, materials: [material])

        // Vertical pole — tall thin cylinder shooting up so the point is visible from any angle
        let pole = MeshResource.generateCylinder(height: 1.0, radius: 0.003)
        let poleEntity = ModelEntity(mesh: pole, materials: [material])
        poleEntity.position.y = 0.5 // center of 1m pole

        // Small sphere on top of the pole
        let sphere = MeshResource.generateSphere(radius: 0.015)
        let sphereEntity = ModelEntity(mesh: sphere, materials: [material])
        sphereEntity.position.y = 1.0

        let anchor = AnchorEntity(world: position)
        anchor.addChild(discEntity)
        anchor.addChild(poleEntity)
        anchor.addChild(sphereEntity)
        arView.scene.addAnchor(anchor)
        alignmentMarkers.append(anchor)
    }

    private func drawAlignmentLine(from p1: SIMD3<Float>, to p2: SIMD3<Float>) {
        guard let arView = arView else { return }

        let dx = p2.x - p1.x
        let dz = p2.z - p1.z
        let length = sqrt(dx * dx + dz * dz)
        let midpoint = (p1 + p2) / 2
        let angle = atan2(dz, dx)

        // Extend the line well beyond the two points for visibility
        let extendedLength = max(length, 10.0)

        let mesh = MeshResource.generateBox(width: extendedLength, height: 0.003, depth: 0.008)
        var material = UnlitMaterial()
        material.color = .init(tint: .cyan)
        let lineEntity = ModelEntity(mesh: mesh, materials: [material])
        lineEntity.orientation = simd_quatf(angle: -angle, axis: SIMD3(0, 1, 0))

        let anchor = AnchorEntity(world: SIMD3<Float>(midpoint.x, midpoint.y + 0.001, midpoint.z))
        anchor.addChild(lineEntity)
        arView.scene.addAnchor(anchor)
        alignmentLine = anchor
    }

    private func clearAlignmentVisuals() {
        for marker in alignmentMarkers {
            arView?.scene.removeAnchor(marker)
        }
        alignmentMarkers.removeAll()
        alignmentPoints.removeAll()
        alignmentPointCount = 0

        if let line = alignmentLine {
            arView?.scene.removeAnchor(line)
            alignmentLine = nil
        }
    }

    // MARK: - Calibration

    func confirmAlignment() {
        clearAlignmentVisuals()
        state = .loading
        loadIFCModel()
    }

    // MARK: - IFC Model Loading

    private func loadIFCModel() {
        loadingError = nil
        log("Starting IFC model load...")
        IFCLoader.onLog = { [weak self] msg in self?.log(msg) }

        // Phase 1: Parse on background thread
        // Phase 2: Build meshes on main thread (MeshResource requires @MainActor)
        Task.detached {
            do {
                let elements = try await IFCLoader.parseAndValidate(named: "Objekt_WC")

                // Hop to main actor for mesh building + scene placement
                await MainActor.run {
                    self.finishLoading(elements)
                }
            } catch {
                await MainActor.run {
                    self.log("FAILED: \(error)")
                    self.loadingError = "\(error)"
                    self.state = .contentPlaced
                }
            }
        }
    }

    private func finishLoading(_ elements: [ValidatedElement]) {
        do {
            let entity = try IFCLoader.buildEntities(from: elements)
            log("Built \(entity.children.count) mesh children")

            guard let arView = arView else {
                log("ERROR: arView is nil")
                return
            }
            guard let floorAnchor = floorAnchor else {
                log("ERROR: floorAnchor is nil")
                return
            }

            log("Placing at \(floorAnchor.position), rot=\(gridRotation)")
            let anchor = AnchorEntity(world: floorAnchor.position)
            anchor.orientation = simd_quatf(angle: gridRotation, axis: SIMD3(0, 1, 0))
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            modelAnchor = anchor

            log("Model placed OK")
            state = .contentPlaced
        } catch {
            log("FAILED: \(error)")
            loadingError = "\(error)"
            state = .contentPlaced
        }
    }

    // MARK: - Grid Rotation

    func updateGridRotation() {
        gridEntity?.orientation = simd_quatf(angle: gridRotation, axis: SIMD3(0, 1, 0))
    }

    func adjustRotation(by delta: Float) {
        guard state == .calibrating else { return }
        gridRotation += delta
        updateGridRotation()
    }

    // MARK: - Reset

    func reset() {
        if let anchor = modelAnchor {
            arView?.scene.removeAnchor(anchor)
            modelAnchor = nil
        }
        clearAlignmentVisuals()
        loadingError = nil

        state = floorAnchor != nil ? .aligning : .coaching
    }
}
