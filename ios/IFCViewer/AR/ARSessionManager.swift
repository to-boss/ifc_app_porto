import Foundation
import ARKit
import RealityKit
import Combine

enum ARState {
    case coaching
    case aligning
    case calibrating
    case ready
    case contentPlaced
}

@MainActor
class ARSessionManager: ObservableObject {
    @Published var state: ARState = .coaching
    @Published var gridRotation: Float = 0
    @Published var alignmentPointCount: Int = 0

    var statusText: String {
        switch state {
        case .coaching:
            return "Move your device to scan the floor"
        case .aligning:
            return alignmentPointCount == 0
                ? "Tap 2 points along a wall edge"
                : "Tap a second point along the wall"
        case .calibrating:
            return "Twist to fine-tune, then confirm"
        case .ready:
            return "Tap to place column"
        case .contentPlaced:
            return "Tap to place more columns"
        }
    }

    weak var arView: ARView?

    private var floorAnchor: AnchorEntity?
    private var gridEntity: FloorGridEntity?

    // Alignment
    private var alignmentPoints: [SIMD3<Float>] = []
    private var alignmentMarkers: [AnchorEntity] = []
    private var alignmentLine: AnchorEntity?

    private var columns: [ModelEntity] = []

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
        } else if state == .ready || state == .contentPlaced {
            handlePlacementTap(at: point)
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
        state = .ready
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

    // MARK: - Column Placement

    private func handlePlacementTap(at point: CGPoint) {
        guard let arView = arView else { return }

        let results = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal)
        guard let result = results.first else { return }

        let worldPosition = SIMD3<Float>(
            result.worldTransform.columns.3.x,
            result.worldTransform.columns.3.y,
            result.worldTransform.columns.3.z
        )

        let snapped = snapToGrid(worldPosition)
        placeColumn(at: snapped)
    }

    private func placeColumn(at position: SIMD3<Float>) {
        let height: Float = 3.0
        let radius: Float = 0.15

        let mesh = MeshResource.generateCylinder(height: height, radius: radius)
        let material = SimpleMaterial(color: .init(white: 0.7, alpha: 1.0), roughness: 0.8, isMetallic: false)
        let column = ModelEntity(mesh: mesh, materials: [material])

        let columnPos = SIMD3<Float>(position.x, position.y + height / 2, position.z)
        let anchor = AnchorEntity(world: columnPos)
        anchor.addChild(column)
        arView?.scene.addAnchor(anchor)

        columns.append(column)
        state = .contentPlaced
    }

    func snapToGrid(_ worldPoint: SIMD3<Float>) -> SIMD3<Float> {
        let cosA = cosf(-gridRotation)
        let sinA = sinf(-gridRotation)
        let local = SIMD3<Float>(
            worldPoint.x * cosA - worldPoint.z * sinA,
            worldPoint.y,
            worldPoint.x * sinA + worldPoint.z * cosA
        )
        let snapped = SIMD3<Float>(
            (local.x / gridSpacing).rounded() * gridSpacing,
            local.y,
            (local.z / gridSpacing).rounded() * gridSpacing
        )
        let cosB = cosf(gridRotation)
        let sinB = sinf(gridRotation)
        return SIMD3<Float>(
            snapped.x * cosB - snapped.z * sinB,
            snapped.y,
            snapped.x * sinB + snapped.z * cosB
        )
    }

    // MARK: - Reset

    func reset() {
        for column in columns {
            column.parent?.removeFromParent()
        }
        columns.removeAll()
        clearAlignmentVisuals()

        state = floorAnchor != nil ? .aligning : .coaching
    }
}
