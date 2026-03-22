import Foundation
import ARKit
import RealityKit
import Combine

enum ARState {
    case coaching
    case scanning
    case calibrating
    case ready
    case contentPlaced
}

@MainActor
class ARSessionManager: ObservableObject {
    @Published var state: ARState = .coaching
    @Published var gridRotation: Float = 0

    var statusText: String {
        switch state {
        case .coaching:
            return "Move your device to scan the floor"
        case .scanning:
            return "Scanning walls..."
        case .calibrating:
            return "Twist to adjust grid, then confirm"
        case .ready:
            return "Tap to place column"
        case .contentPlaced:
            return "Tap to place more columns"
        }
    }

    weak var arView: ARView?

    private var floorAnchor: AnchorEntity?
    private var gridEntity: FloorGridEntity?
    private var floorHeight: Float?

    private var wallEntities: [UUID: (AnchorEntity, WallPlaneEntity)] = [:]
    private var wallAnchors: [UUID: ARPlaneAnchor] = [:]
    private var columns: [ModelEntity] = []

    let gridSpacing: Float = 0.5
    private let minWallExtent: Float = 1.0 // minimum 1m to count as a wall

    // MARK: - Coaching

    func coachingDidFinish() {
        if state == .coaching {
            state = .scanning
        }
    }

    // MARK: - Plane Detection

    func handlePlaneAnchorAdded(_ anchor: ARPlaneAnchor) {
        if anchor.alignment == .horizontal {
            handleFloorDetected(anchor)
        } else if anchor.alignment == .vertical {
            handleWallDetected(anchor)
        }
    }

    func handlePlaneAnchorUpdated(_ anchor: ARPlaneAnchor) {
        if anchor.alignment == .horizontal {
            // Track lowest floor height
            let y = anchor.transform.columns.3.y
            if let current = floorHeight, y < current - 0.03 {
                floorHeight = y
                updateFloorAnchorHeight(y)
            }
        } else if anchor.alignment == .vertical {
            // Update wall entity extent
            if let (_, wallEntity) = wallEntities[anchor.identifier] {
                wallEntity.updateExtent(
                    width: anchor.planeExtent.width,
                    height: anchor.planeExtent.height
                )
            }
            // Update stored anchor and recalculate alignment
            if wallAnchors[anchor.identifier] != nil {
                wallAnchors[anchor.identifier] = anchor
                if state == .calibrating {
                    recalculateWallAlignment()
                }
            }
        }
    }

    func handlePlaneAnchorRemoved(_ anchor: ARPlaneAnchor) {
        if let (anchorEntity, _) = wallEntities.removeValue(forKey: anchor.identifier) {
            arView?.scene.removeAnchor(anchorEntity)
        }
        wallAnchors.removeValue(forKey: anchor.identifier)
    }

    // MARK: - Floor (lowest plane, world anchor)

    private func handleFloorDetected(_ anchor: ARPlaneAnchor) {
        let y = anchor.transform.columns.3.y

        if let currentHeight = floorHeight {
            // Only update if this plane is significantly lower (likely the real floor)
            if y < currentHeight - 0.03 {
                floorHeight = y
                updateFloorAnchorHeight(y)
            }
            return
        }

        // First floor detection — create grid at world position (not tracking the anchor)
        floorHeight = y
        let position = SIMD3<Float>(
            anchor.transform.columns.3.x,
            y,
            anchor.transform.columns.3.z
        )

        let anchorEntity = AnchorEntity(world: position)
        let grid = FloorGridEntity(spacing: gridSpacing)
        anchorEntity.addChild(grid)
        arView?.scene.addAnchor(anchorEntity)

        floorAnchor = anchorEntity
        gridEntity = grid

        if state == .coaching || state == .scanning {
            state = .scanning
        }
    }

    private func updateFloorAnchorHeight(_ newY: Float) {
        guard let anchor = floorAnchor else { return }
        var pos = anchor.position
        pos.y = newY
        anchor.position = pos
    }

    // MARK: - Wall Detection & Grid Alignment

    private func handleWallDetected(_ anchor: ARPlaneAnchor) {
        // Filter out small/noisy planes
        guard anchor.planeExtent.width >= minWallExtent,
              anchor.planeExtent.height >= minWallExtent else {
            return
        }

        // Visualize the wall
        let anchorEntity = AnchorEntity(anchor: anchor)
        let wallEntity = WallPlaneEntity(
            width: anchor.planeExtent.width,
            height: anchor.planeExtent.height
        )
        anchorEntity.addChild(wallEntity)
        arView?.scene.addAnchor(anchorEntity)
        wallEntities[anchor.identifier] = (anchorEntity, wallEntity)
        wallAnchors[anchor.identifier] = anchor

        // Recalculate alignment from all walls
        if floorAnchor != nil {
            recalculateWallAlignment()
            if state == .scanning {
                state = .calibrating
            }
        }
    }

    /// Average all wall normals and snap to nearest 90° for grid alignment.
    private func recalculateWallAlignment() {
        guard !wallAnchors.isEmpty else { return }

        // Collect all wall normals projected onto XZ plane
        var angles: [Float] = []
        for anchor in wallAnchors.values {
            let normalX = anchor.transform.columns.2.x
            let normalZ = anchor.transform.columns.2.z
            let angle = atan2(normalX, normalZ)
            // Normalize to [0, π/2) range — walls are typically orthogonal
            let normalized = angle.truncatingRemainder(dividingBy: .pi / 2)
            angles.append(normalized)
        }

        // Circular mean of angles (handles wraparound)
        let sinSum = angles.reduce(Float(0)) { $0 + sin(2 * $1) }
        let cosSum = angles.reduce(Float(0)) { $0 + cos(2 * $1) }
        let meanAngle = atan2(sinSum, cosSum) / 2

        // Snap to nearest 90°
        let snappedAngle = (meanAngle / (.pi / 2)).rounded() * (.pi / 2)

        gridRotation = snappedAngle
        updateGridRotation()
    }

    // MARK: - Calibration

    func confirmAlignment() {
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

    func handleTap(at point: CGPoint) {
        guard state == .ready || state == .contentPlaced else { return }
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

        if !wallAnchors.isEmpty {
            state = .calibrating
        } else if floorAnchor != nil {
            state = .scanning
        } else {
            state = .coaching
        }
    }
}
