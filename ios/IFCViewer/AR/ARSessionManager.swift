import Foundation
import ARKit
import RealityKit
import Combine
import os

private let logger = Logger(subsystem: "com.ifcar.viewer", category: "ARSession")

enum ARState {
    case coaching
    case loading           // loading room IFC + extracting floor plan
    case floorPlanPicking  // 2D floor plan overlay, pick edge + direction
    case edgeAligning      // centroid marker follows camera, Place button locks points
    case scaleConfirmation // auto-scale prompt when model/real lengths differ
    case floorSetting      // aim at floor, tap Set Floor to lock Y
    case heightAdjust      // vertical slider for floor Y offset
    case roomPlaced        // room placed, show fixture picker
    case fixtureLoading    // loading a fixture IFC
    case fixturePreviewing // ghost preview of fixture
    case wallStart         // centroid marker follows camera, waiting for Place
    case wallEnd           // live 3D wall preview, endpoint follows camera
    case wallAdjust        // both points locked, sliders for height/width
    case elementMoving     // moving a room element within its parent
    case done              // all models placed
}

@MainActor
class ARSessionManager: ObservableObject {
    @Published var state: ARState = .coaching
    @Published var loadingError: String?
    @Published var debugLog: [String] = []
    @Published var modelScale: Float = 1.0 {
        didSet { applyPreviewTransform() }
    }
    @Published var modelRotation: Float = 0 {
        didSet { applyPreviewTransform() }
    }

    // Edge-based alignment
    @Published var floorPlan: FloorPlan?
    @Published var selectedEdgeIndex: Int?
    @Published var edgeArrowAngle: Float = 0  // radians, set via circular dial
    @Published var floorPlanRotation: Float = 0  // radians, floor plan canvas rotation
    @Published var edgeAlignPointCount: Int = 0
    @Published var floorHeightOffset: Float = 0.0 {
        didSet { applyHeightOffset() }
    }
    @Published var computedScaleFactor: Float = 1.0
    @Published var modelEdgeLength: Float = 0
    @Published var realEdgeLength: Float = 0
    @Published var computedRotation: Float = 0
    @Published var selectedElement: ElementInfo?
    @Published var selectedScreenPoint: CGPoint = .zero
    @Published var showingDetails: Bool = false
    @Published var exportFileURL: URL?
    @Published var bcfIssues: [BCFIssue] = []
    @Published var wallHeight: Float = 2.5 {
        didSet { regenerateWallPreview() }
    }
    @Published var wallThickness: Float = 0.2 {
        didSet { regenerateWallPreview() }
    }

    func log(_ msg: String) {
        logger.info("\(msg)")
        debugLog.append(msg)
        if debugLog.count > 30 { debugLog.removeFirst() }
    }

    weak var arView: ARView?
    private let maxSelectionDistance: Float = 10.0  // meters

    private var floorAnchor: AnchorEntity?
    private var gridEntity: FloorGridEntity?

    // Edge alignment
    private var edgeAlignPoints: [SIMD3<Float>] = []
    private var alignmentMarkers: [AnchorEntity] = []
    private var alignmentLine: AnchorEntity?
    private var parsedElements: [ValidatedElement]?
    private var modelMinY: Float = 0  // lowest vertex Y (negative when centered)
    private var edgeAlignMarker: AnchorEntity?
    private var edgeLiveLineAnchor: AnchorEntity?
    private var floorMarker: AnchorEntity?
    private var debugGuideAnchors: [AnchorEntity] = []

    // Wall plane tracking (vertical plane detection)
    private var detectedWallPlanes: [UUID: ARPlaneAnchor] = [:]
    @Published var isSnappedToWallPlane: Bool = false
    @Published var detectedWallPlaneCount: Int = 0
    private var snappedWallPlaneId: UUID?
    private var point1WallPlaneId: UUID?

    private var roomAnchor: AnchorEntity?
    private var roomEntity: Entity?

    struct PlacedFixture {
        let anchor: AnchorEntity
        let filename: String
    }
    private var placedFixtures: [PlacedFixture] = []
    private var pendingFixtureFilename: String?

    private var previewAnchor: AnchorEntity?
    private var previewEntity: Entity?
    private var originalMaterials: [(ModelEntity, [Material])] = []

    /// Maps IFC element id → metadata for all loaded models
    private var elementMetadata: [UInt64: ValidatedElement] = [:]
    /// The tapped entity, used to track its screen position
    private var selectedEntityRef: Entity?
    private var selectedOriginalMaterials: [(ModelEntity, [Material])] = []

    // Element moving (room elements)
    private var movingEntity: Entity?
    private var movingOriginalPosition: SIMD3<Float>?
    private var deletedElementIds: Set<UInt64> = []
    private var movedElementOffsets: [UInt64: SIMD3<Float>] = [:]

    // Hidden elements
    struct HiddenElement: Identifiable {
        let id: UInt64
        let name: String
        let ifcType: String
        let entity: Entity
    }
    @Published var hiddenElements: [HiddenElement] = []

    // Wall building
    private var wallStartPoint: SIMD3<Float>?
    private var wallEndPoint: SIMD3<Float>?
    private var wallCentroidMarker: AnchorEntity?
    private var wallPreviewAnchor: AnchorEntity?
    private var wallPreviewEntity: ModelEntity?
    private var wallIdCounter: UInt64 = 900_000
    private var currentWallElement: IfcElement?

    struct CreatedWall {
        let anchor: AnchorEntity
        let element: IfcElement
        let height: Float
        let thickness: Float
        let length: Float
    }
    private var createdWalls: [CreatedWall] = []

    let gridSpacing: Float = 0.5

    // MARK: - Coaching

    func coachingDidFinish() {
        if state == .coaching {
            state = .loading
            loadAndExtractFloorPlan()
        }
    }

    // MARK: - Plane Detection

    func handlePlaneAnchorAdded(_ anchor: ARPlaneAnchor) {
        if anchor.alignment == .horizontal {
            handleFloorDetected(anchor)
        } else if anchor.alignment == .vertical {
            detectedWallPlanes[anchor.identifier] = anchor
            detectedWallPlaneCount = detectedWallPlanes.count
            log("Wall plane detected (\(detectedWallPlanes.count) total)")
        }
    }

    func handlePlaneAnchorUpdated(_ anchor: ARPlaneAnchor) {
        if anchor.alignment == .vertical {
            detectedWallPlanes[anchor.identifier] = anchor
        }
    }

    func handlePlaneAnchorRemoved(_ anchor: ARPlaneAnchor) {
        if anchor.alignment == .vertical {
            detectedWallPlanes.removeValue(forKey: anchor.identifier)
            detectedWallPlaneCount = detectedWallPlanes.count
        }
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

        // Floor detected — coaching overlay can dismiss now
        if state == .coaching {
            state = .loading
            loadAndExtractFloorPlan()
        }
    }

    // MARK: - Tap Handling

    func handleTap(at point: CGPoint) {
        guard let arView = arView else { return }

        // edgeAligning uses centroid + Place button, not taps

        // Entity tap detection when models are placed
        if state == .roomPlaced || state == .done {
            // If action menu is showing, dismiss it
            if selectedElement != nil {
                IFCLoader.restoreMaterials(selectedOriginalMaterials)
                selectedOriginalMaterials = []
                selectedElement = nil
                selectedEntityRef = nil
                showingDetails = false
                return
            }

            // Screen-space hit test (forgiving) + distance filter
            let cameraPos = arView.cameraTransform.translation
            let hits = arView.entities(at: point)

            // Find the closest valid ifc_ entity within range
            var bestEntity: Entity?
            var bestId: UInt64 = 0
            var bestMeta: ValidatedElement?
            var bestDist: Float = maxSelectionDistance

            for entity in hits {
                var current: Entity? = entity
                while let e = current {
                    if e.name.hasPrefix("ifc_"),
                       let idStr = e.name.split(separator: "_").last,
                       let id = UInt64(idStr),
                       let meta = elementMetadata[id] {
                        let worldPos = e.position(relativeTo: nil)
                        let dist = simd_distance(worldPos, cameraPos)
                        if dist < bestDist {
                            bestEntity = e
                            bestId = id
                            bestMeta = meta
                            bestDist = dist
                        }
                        break
                    }
                    current = e.parent
                }
            }

            if let e = bestEntity, let meta = bestMeta, let anchor = findOwningAnchor(for: e) {
                let isRoom = (anchor === roomAnchor)
                selectedEntityRef = e
                // Use visual center for bubble position
                let bounds = e.visualBounds(relativeTo: nil)
                let center3D = bounds.center
                if let screenPt = arView.project(center3D) {
                    selectedScreenPoint = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))
                } else {
                    selectedScreenPoint = point
                }
                selectedElement = ElementInfo(
                    id: bestId,
                    ifcType: meta.ifcType,
                    name: meta.name,
                    globalId: meta.globalId,
                    properties: meta.properties,
                    anchor: anchor,
                    entity: e,
                    isRoomElement: isRoom
                )
                // Highlight: collect this entity + all descendant ModelEntities
                selectedOriginalMaterials = IFCLoader.collectMaterials(from: e)
                if let model = e as? ModelEntity, let mats = model.model?.materials {
                    selectedOriginalMaterials.insert((model, mats), at: 0)
                }
                var highlight = PhysicallyBasedMaterial()
                highlight.baseColor = .init(tint: .systemYellow)
                highlight.metallic = .init(floatLiteral: 0.1)
                highlight.roughness = .init(floatLiteral: 0.5)
                highlight.blending = .transparent(opacity: .init(floatLiteral: 0.8))
                for (model, _) in selectedOriginalMaterials {
                    model.model?.materials = [highlight]
                }
                log("Selected: \(meta.ifcType) #\(bestId) at \(String(format: "%.2f", bestDist))m\(isRoom ? " (room)" : "")")
            }
        }
    }

    private func findOwningAnchor(for entity: Entity) -> AnchorEntity? {
        var current: Entity? = entity
        while let e = current {
            if let anchor = e as? AnchorEntity {
                return anchor
            }
            current = e.parent
        }
        return nil
    }

    // MARK: - Edge-Based Alignment

    private func loadAndExtractFloorPlan() {
        guard state == .loading else { return }
        loadingError = nil
        log("Loading room + extracting floor plan...")
        IFCLoader.onLog = { [weak self] msg in self?.log(msg) }

        Task.detached {
            do {
                // Parse IFC
                let elements = try await IFCLoader.parseAndValidate(named: "BaseRoom-v2")

                // Extract floor plan
                guard let url = Bundle.main.url(forResource: "BaseRoom-v2", withExtension: "ifc"),
                      let ifcData = try? Data(contentsOf: url) else {
                    throw IFCLoaderError.bundleFileNotFound("BaseRoom-v2")
                }
                let plan = try extractFloorPlan(data: ifcData)

                // Compute model floor level (minimum Y across all vertices)
                var minY: Float = .infinity
                for elem in elements {
                    for i in stride(from: 1, to: elem.positions.count, by: 3) {
                        minY = min(minY, elem.positions[i])
                    }
                }

                await MainActor.run {
                    self.parsedElements = elements
                    self.modelMinY = minY == .infinity ? 0 : minY
                    self.floorPlan = plan
                    self.selectedEdgeIndex = nil
                    self.edgeArrowAngle = 0
                    self.log(String(format: "Floor plan: %d edges, model floor Y: %.2fm", plan.edges.count, self.modelMinY))
                    self.state = .floorPlanPicking
                }
            } catch {
                await MainActor.run {
                    self.log("FAILED: \(error)")
                    self.loadingError = "\(error)"
                }
            }
        }
    }

    func confirmEdgeSelection() {
        guard let arView = arView, state == .floorPlanPicking, selectedEdgeIndex != nil else { return }
        edgeAlignPoints.removeAll()
        edgeAlignPointCount = 0
        snappedWallPlaneId = nil
        point1WallPlaneId = nil
        isSnappedToWallPlane = false

        // Create centroid marker (same pattern as wall building)
        var material = UnlitMaterial()
        material.color = .init(tint: .cyan)
        let disc = MeshResource.generateCylinder(height: 0.005, radius: 0.04)
        let discEntity = ModelEntity(mesh: disc, materials: [material])
        let sphere = MeshResource.generateSphere(radius: 0.02)
        let sphereEntity = ModelEntity(mesh: sphere, materials: [material])
        sphereEntity.position.y = 0.025
        let marker = AnchorEntity(world: .zero)
        marker.addChild(discEntity)
        marker.addChild(sphereEntity)
        arView.scene.addAnchor(marker)
        edgeAlignMarker = marker

        state = .edgeAligning
        log("Edge confirmed — aim at wall endpoint and tap Place")
    }

    /// Called by toolbar "Place" button during edge alignment.
    func placeEdgePoint() {
        guard state == .edgeAligning, let marker = edgeAlignMarker else { return }
        let pos = marker.position

        edgeAlignPoints.append(pos)
        placeAlignmentMarker(at: pos)
        edgeAlignPointCount = edgeAlignPoints.count

        if edgeAlignPoints.count == 1 {
            // Track which wall plane point 1 snapped to
            point1WallPlaneId = snappedWallPlaneId
            // Create live line from point 1 to centroid
            if let arView = arView {
                let lineAnchor = AnchorEntity(world: pos)
                let mesh = MeshResource.generateBox(width: 0.003, height: 0.003, depth: 0.003)
                var mat = UnlitMaterial()
                mat.color = .init(tint: .cyan)
                let lineEntity = ModelEntity(mesh: mesh, materials: [mat])
                lineEntity.name = "liveLine"
                lineAnchor.addChild(lineEntity)
                arView.scene.addAnchor(lineAnchor)
                edgeLiveLineAnchor = lineAnchor
            }
            log("Point 1 locked — aim at the other end")
        } else if edgeAlignPoints.count == 2 {
            // Remove live line
            if let line = edgeLiveLineAnchor {
                arView?.scene.removeAnchor(line)
                edgeLiveLineAnchor = nil
            }
            drawAlignmentLine(from: edgeAlignPoints[0], to: edgeAlignPoints[1])

            // Remove centroid marker
            arView?.scene.removeAnchor(marker)
            edgeAlignMarker = nil

            computeAlignmentAndPlace()
        }
    }

    func cancelEdgeAlignment() {
        if let marker = edgeAlignMarker {
            arView?.scene.removeAnchor(marker)
            edgeAlignMarker = nil
        }
        clearAlignmentVisuals()
        state = .floorPlanPicking
        log("Edge alignment cancelled")
    }

    private func computeAlignmentAndPlace() {
        guard let idx = selectedEdgeIndex,
              let plan = floorPlan,
              idx < plan.edges.count,
              edgeAlignPoints.count == 2 else { return }

        let edge = plan.edges[idx]
        let r1 = edgeAlignPoints[0]
        let r2 = edgeAlignPoints[1]

        // Compute scale factor
        let realLen = sqrt((r2.x - r1.x) * (r2.x - r1.x) + (r2.z - r1.z) * (r2.z - r1.z))
        let modelLen = sqrt((edge.x2 - edge.x1) * (edge.x2 - edge.x1) + (edge.z2 - edge.z1) * (edge.z2 - edge.z1))
        let scale = modelLen > 0.01 ? realLen / modelLen : 1.0

        modelEdgeLength = modelLen
        realEdgeLength = realLen
        computedScaleFactor = scale

        // Model edge direction (XZ plane)
        let mDx = edge.x2 - edge.x1
        let mDz = edge.z2 - edge.z1
        let mAngle = atan2(mDz, mDx)

        // Real-world edge direction (XZ plane)
        let rDx = r2.x - r1.x
        let rDz = r2.z - r1.z
        var rAngle = atan2(rDz, rDx)

        // Refine rotation using wall plane normal if both points snapped to the same wall
        if let planeId = point1WallPlaneId,
           planeId == snappedWallPlaneId,
           let plane = detectedWallPlanes[planeId] {
            let planeDir = wallPlaneDirection(plane)
            // Choose direction (planeDir or planeDir+pi) closest to user's tapped direction
            let diff = atan2(sin(planeDir - rAngle), cos(planeDir - rAngle))
            if abs(diff) <= Float.pi / 2 {
                rAngle = planeDir
            } else {
                rAngle = planeDir + .pi
            }
            log(String(format: "ALIGN: rotation refined by wall plane (%.1f°)", rAngle * 180 / .pi))
        }

        // Rotation: simd_quatf(angle:θ, axis:Y) maps direction α to α-θ
        // So to map mAngle to rAngle: mAngle - θ = rAngle → θ = mAngle - rAngle
        var rotation = mAngle - rAngle

        // Arrow offset from perpendicular determines which side user is on
        let perpAngle = mAngle + .pi / 2
        let arrowOffset = edgeArrowAngle - perpAngle
        let normalizedOffset = atan2(sin(arrowOffset), cos(arrowOffset))
        if abs(normalizedOffset) > .pi / 2 {
            rotation += .pi
        }
        computedRotation = rotation

        log(String(format: "Edge: %.2fm model, %.2fm real, scale %.2fx, rot %.1f°", modelLen, realLen, scale, rotation * 180 / .pi))

        // If scale differs by more than 10%, ask user to confirm
        if abs(scale - 1.0) > 0.10 {
            state = .scaleConfirmation
            return
        }

        // Always apply computed scale (even small corrections matter)
        placeModelWithScale(scaleFactor: scale)
    }

    func acceptAutoScale() {
        guard state == .scaleConfirmation else { return }
        placeModelWithScale(scaleFactor: computedScaleFactor)
    }

    func rejectAutoScale() {
        guard state == .scaleConfirmation else { return }
        placeModelWithScale(scaleFactor: 1.0)
    }

    private func placeModelWithScale(scaleFactor: Float) {
        guard let idx = selectedEdgeIndex,
              let plan = floorPlan,
              idx < plan.edges.count,
              edgeAlignPoints.count == 2,
              let elements = parsedElements else { return }

        let edge = plan.edges[idx]
        let r1 = edgeAlignPoints[0]
        let r2 = edgeAlignPoints[1]
        let rotation = computedRotation

        // Rotate model edge midpoint (scaled) using Y-axis rotation matrix:
        // x' = x·cos(θ) + z·sin(θ),  z' = -x·sin(θ) + z·cos(θ)
        let mMidX = (edge.x1 + edge.x2) / 2 * scaleFactor
        let mMidZ = (edge.z1 + edge.z2) / 2 * scaleFactor
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        let rotatedMidX = mMidX * cosR + mMidZ * sinR
        let rotatedMidZ = -mMidX * sinR + mMidZ * cosR

        // Real edge midpoint
        let rMidX = (r1.x + r2.x) / 2
        let rMidZ = (r1.z + r2.z) / 2
        let rMidY = (r1.y + r2.y) / 2

        let tx = rMidX - rotatedMidX
        let tz = rMidZ - rotatedMidZ

        do {
            let (entity, metadata) = try IFCLoader.buildEntities(from: elements)
            elementMetadata.merge(metadata) { _, new in new }

            entity.scale = SIMD3<Float>(repeating: scaleFactor)
            entity.orientation = simd_quatf(angle: rotation, axis: SIMD3(0, 1, 0))

            // Offset Y so model floor (modelMinY) sits at real floor level (rMidY)
            let anchorY = rMidY - modelMinY * scaleFactor
            let anchor = AnchorEntity(world: SIMD3<Float>(tx, anchorY, tz))
            anchor.addChild(entity)
            arView?.scene.addAnchor(anchor)

            roomAnchor = anchor
            roomEntity = entity
            floorHeightOffset = 0
            computedScaleFactor = scaleFactor

            log(String(format: "Model placed (rotation: %.1f°, scale: %.2fx)", rotation * 180 / .pi, scaleFactor))
            drawDebugGuides(edge: edge, scaleFactor: scaleFactor, rotation: rotation, tx: tx, tz: tz, rMidY: rMidY)

            // Store base Y for height fine-tuning
            floorBaseY = anchorY
            floorHeightOffset = 0

            state = .heightAdjust
        } catch {
            log("FAILED to build entities: \(error)")
            loadingError = "\(error)"
        }
    }

    private func drawDebugGuides(edge: FloorPlanEdge, scaleFactor: Float, rotation: Float, tx: Float, tz: Float, rMidY: Float) {
        guard let arView = arView else { return }
        let cosR = cos(rotation)
        let sinR = sin(rotation)

        // Transform model edge endpoints to world space
        let e1x = edge.x1 * scaleFactor
        let e1z = edge.z1 * scaleFactor
        let e2x = edge.x2 * scaleFactor
        let e2z = edge.z2 * scaleFactor

        let w1x = e1x * cosR + e1z * sinR + tx
        let w1z = -e1x * sinR + e1z * cosR + tz
        let w2x = e2x * cosR + e2z * sinR + tx
        let w2z = -e2x * sinR + e2z * cosR + tz

        let p1 = SIMD3<Float>(w1x, rMidY + 0.01, w1z)
        let p2 = SIMD3<Float>(w2x, rMidY + 0.01, w2z)

        // Green line for model edge in world space
        let dx = p2.x - p1.x
        let dz = p2.z - p1.z
        let length = sqrt(dx * dx + dz * dz)
        let angle = atan2(dz, dx)
        let mid = (p1 + p2) / 2

        var greenMat = UnlitMaterial()
        greenMat.color = .init(tint: .green)
        let lineMesh = MeshResource.generateBox(width: max(length, 0.01), height: 0.006, depth: 0.012)
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [greenMat])
        lineEntity.orientation = simd_quatf(angle: -angle, axis: SIMD3(0, 1, 0))

        let lineAnchor = AnchorEntity(world: mid)
        lineAnchor.addChild(lineEntity)
        arView.scene.addAnchor(lineAnchor)
        debugGuideAnchors.append(lineAnchor)

        // Green dots at model edge endpoints
        let dotMesh = MeshResource.generateSphere(radius: 0.025)
        for pt in [p1, p2] {
            let dot = ModelEntity(mesh: dotMesh, materials: [greenMat])
            let dotAnchor = AnchorEntity(world: pt)
            dotAnchor.addChild(dot)
            arView.scene.addAnchor(dotAnchor)
            debugGuideAnchors.append(dotAnchor)
        }

        // Red dot at model origin (anchor point)
        var redMat = UnlitMaterial()
        redMat.color = .init(tint: .red)
        let originDot = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.03), materials: [redMat])
        let originAnchor = AnchorEntity(world: SIMD3<Float>(tx, rMidY + 0.02, tz))
        originAnchor.addChild(originDot)
        arView.scene.addAnchor(originAnchor)
        debugGuideAnchors.append(originAnchor)

        log(String(format: "Debug: model edge world (%.2f,%.2f)→(%.2f,%.2f), anchor (%.2f,%.2f)", w1x, w1z, w2x, w2z, tx, tz))
    }

    private func clearDebugGuides() {
        for anchor in debugGuideAnchors {
            arView?.scene.removeAnchor(anchor)
        }
        debugGuideAnchors.removeAll()
    }

    private var floorBaseY: Float = 0  // anchor Y before height offset

    /// User aims at floor and taps "Set Floor" — lock the Y.
    func setFloorPoint() {
        guard state == .floorSetting, let marker = floorMarker, let anchor = roomAnchor else { return }

        let floorY = marker.position.y
        floorBaseY = floorY - modelMinY * computedScaleFactor
        anchor.position.y = floorBaseY
        floorHeightOffset = 0

        // Remove floor marker
        arView?.scene.removeAnchor(marker)
        floorMarker = nil

        log(String(format: "Floor set at Y=%.3f", floorY))
        clearDebugGuides()
        state = .heightAdjust
    }

    private func applyHeightOffset() {
        guard let anchor = roomAnchor else { return }
        anchor.position.y = floorBaseY + floorHeightOffset
    }

    func confirmHeight() {
        guard state == .heightAdjust else { return }
        applyHeightOffset()
        log("Height confirmed (offset: \(String(format: "%+.1f", floorHeightOffset * 100)) cm)")
        state = .roomPlaced
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

    // MARK: - Wall Plane Snapping

    /// Find the nearest detected vertical plane within threshold distance.
    /// Returns the plane and the point projected onto its surface.
    private func findNearestWallPlane(to worldPos: SIMD3<Float>, threshold: Float = 0.15) -> (ARPlaneAnchor, SIMD3<Float>)? {
        var bestAnchor: ARPlaneAnchor?
        var bestSnappedPos: SIMD3<Float>?
        var bestDist: Float = threshold

        for (_, plane) in detectedWallPlanes {
            // Plane normal from transform column 2 (local Z-axis)
            let col2 = plane.transform.columns.2
            let normal = SIMD3<Float>(col2.x, col2.y, col2.z)
            let col3 = plane.transform.columns.3
            let planeCenter = SIMD3<Float>(col3.x, col3.y, col3.z)

            // Signed distance from point to plane
            let diff = worldPos - planeCenter
            let signedDist = simd_dot(diff, normal)
            let absDist = abs(signedDist)

            if absDist < bestDist {
                // Project point onto plane surface
                let snapped = worldPos - signedDist * normal

                // Check snapped point is roughly within plane extent (in plane-local coords)
                let invTransform = simd_inverse(plane.transform)
                let localPos = invTransform * SIMD4<Float>(snapped.x, snapped.y, snapped.z, 1.0)
                let planeExtent = plane.planeExtent
                let halfW = planeExtent.width / 2 + 0.1  // small margin
                let halfH = planeExtent.height / 2 + 0.1
                if abs(localPos.x) <= halfW && abs(localPos.z) <= halfH {
                    bestDist = absDist
                    bestAnchor = plane
                    bestSnappedPos = snapped
                }
            }
        }

        if let anchor = bestAnchor, let pos = bestSnappedPos {
            return (anchor, pos)
        }
        return nil
    }

    /// Get the wall direction (along the wall surface in XZ) from a vertical plane's normal.
    private func wallPlaneDirection(_ plane: ARPlaneAnchor) -> Float {
        let col2 = plane.transform.columns.2
        // Wall runs perpendicular to normal in XZ plane: (-nz, nx)
        return atan2(col2.x, -col2.z)
    }

    /// Update the centroid marker material color based on snap state.
    private func updateMarkerColor(snapped: Bool) {
        guard let marker = edgeAlignMarker else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: snapped ? .green : .cyan)
        for child in marker.children {
            if let model = child as? ModelEntity {
                model.model?.materials = [material]
            }
        }
    }

    private func clearAlignmentVisuals() {
        for marker in alignmentMarkers {
            arView?.scene.removeAnchor(marker)
        }
        alignmentMarkers.removeAll()
        edgeAlignPoints.removeAll()
        edgeAlignPointCount = 0

        if let line = alignmentLine {
            arView?.scene.removeAnchor(line)
            alignmentLine = nil
        }
    }

    // MARK: - Fixture Loading

    private func loadFixtureModel(named filename: String) {
        loadingError = nil
        log("Loading \(filename)...")
        IFCLoader.onLog = { [weak self] msg in self?.log(msg) }

        Task.detached {
            do {
                let elements = try await IFCLoader.parseAndValidate(named: filename)
                await MainActor.run {
                    self.finishFixtureLoading(elements)
                }
            } catch {
                await MainActor.run {
                    self.log("FAILED: \(error)")
                    self.loadingError = "\(error)"
                    self.state = .roomPlaced
                }
            }
        }
    }

    private func finishFixtureLoading(_ elements: [ValidatedElement]) {
        do {
            let (entity, metadata) = try IFCLoader.buildEntities(from: elements)
            elementMetadata.merge(metadata) { _, new in new }
            log("Built \(entity.children.count) mesh children")

            guard let arView = arView else {
                log("ERROR: arView is nil")
                return
            }
            guard let floorAnchor = floorAnchor else {
                log("ERROR: floorAnchor is nil")
                return
            }

            // Store original materials before applying ghost effect
            originalMaterials = IFCLoader.collectMaterials(from: entity)
            IFCLoader.applyGhostEffect(to: entity)

            // Place as ghost preview at camera position
            let anchor = AnchorEntity(world: floorAnchor.position)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            previewAnchor = anchor
            previewEntity = entity
            modelScale = 1.0
            modelRotation = 0
            applyPreviewTransform()

            log("Preview ghost active — move camera to position, adjust scale/rotation, then Place")
            state = .fixturePreviewing
        } catch {
            log("FAILED: \(error)")
            loadingError = "\(error)"
            state = .roomPlaced
        }
    }

    func loadFixture(named filename: String) {
        pendingFixtureFilename = filename
        state = .fixtureLoading
        loadFixtureModel(named: filename)
    }

    // MARK: - Preview

    func updatePreviewPosition() {
        guard let arView = arView else { return }

        // Raycast from upper-center of screen so ghost appears further ahead
        let aimPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.height * 0.35)

        // Update preview anchor position (fixtures only — room is placed via edge alignment)
        if state == .fixturePreviewing {
            let results = arView.raycast(from: aimPoint, allowing: .existingPlaneGeometry, alignment: .horizontal)
            if let result = results.first {
                let col = result.worldTransform.columns.3
                previewAnchor?.position = SIMD3<Float>(col.x, col.y, col.z)
            }
        }

        // Element moving: update position within room
        if state == .elementMoving, let entity = movingEntity, let roomEnt = roomEntity {
            let center = aimPoint
            let results = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal)
            if let result = results.first {
                let col = result.worldTransform.columns.3
                let worldPos = SIMD3<Float>(col.x, col.y, col.z)
                let localPos = roomEnt.convert(position: worldPos, from: nil)
                entity.position = localPos
            }
        }

        // Edge alignment: move centroid marker + update live line
        if state == .edgeAligning {
            let results = arView.raycast(from: aimPoint, allowing: .existingPlaneGeometry, alignment: .horizontal)
            if let result = results.first {
                let col = result.worldTransform.columns.3
                var markerPos = SIMD3<Float>(col.x, col.y, col.z)

                // Try to snap X/Z to nearest vertical wall plane
                if let (wallPlane, snappedPos) = findNearestWallPlane(to: markerPos) {
                    markerPos.x = snappedPos.x
                    markerPos.z = snappedPos.z
                    if snappedWallPlaneId != wallPlane.identifier {
                        snappedWallPlaneId = wallPlane.identifier
                        updateMarkerColor(snapped: true)
                    }
                    if !isSnappedToWallPlane { isSnappedToWallPlane = true }
                } else {
                    if isSnappedToWallPlane {
                        snappedWallPlaneId = nil
                        isSnappedToWallPlane = false
                        updateMarkerColor(snapped: false)
                    }
                }

                edgeAlignMarker?.position = markerPos

                // Update live line from point 1 to current marker
                if edgeAlignPoints.count == 1, let lineAnchor = edgeLiveLineAnchor {
                    let p1 = edgeAlignPoints[0]
                    let dx = markerPos.x - p1.x
                    let dz = markerPos.z - p1.z
                    let length = sqrt(dx * dx + dz * dz)
                    let angle = atan2(dz, dx)
                    let mid = SIMD3<Float>((p1.x + markerPos.x) / 2, (p1.y + markerPos.y) / 2 + 0.001, (p1.z + markerPos.z) / 2)
                    lineAnchor.position = mid
                    if let lineEntity = lineAnchor.children.first as? ModelEntity, length > 0.01 {
                        lineEntity.model = ModelComponent(
                            mesh: MeshResource.generateBox(width: max(length, 0.01), height: 0.003, depth: 0.008),
                            materials: lineEntity.model?.materials ?? []
                        )
                        lineEntity.orientation = simd_quatf(angle: -angle, axis: SIMD3(0, 1, 0))
                    }
                }
            }
        }

        // Floor setting: move yellow marker to camera aim point
        if state == .floorSetting {
            let results = arView.raycast(from: aimPoint, allowing: .existingPlaneGeometry, alignment: .horizontal)
            if let result = results.first {
                let col = result.worldTransform.columns.3
                floorMarker?.position = SIMD3<Float>(col.x, col.y, col.z)
            }
        }

        // Wall building: update centroid marker and live preview
        if state == .wallStart || state == .wallEnd {
            updateWallPreview()
        }

        // Track selected entity screen position for the bubble (use visual center)
        if let entity = selectedEntityRef, selectedElement != nil {
            let center3D = entity.visualBounds(relativeTo: nil).center
            if let screenPt = arView.project(center3D) {
                selectedScreenPoint = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))
            }
        }
    }

    private func applyPreviewTransform() {
        previewEntity?.scale = SIMD3<Float>(repeating: modelScale)
        previewEntity?.orientation = simd_quatf(angle: computedRotation + modelRotation, axis: SIMD3(0, 1, 0))
    }

    func placeFixture() {
        guard state == .fixturePreviewing, let anchor = previewAnchor else { return }

        // Restore original opaque materials for the fixture
        IFCLoader.restoreMaterials(originalMaterials)
        originalMaterials = []

        let filename = pendingFixtureFilename ?? "unknown"
        placedFixtures.append(PlacedFixture(anchor: anchor, filename: filename))
        pendingFixtureFilename = nil
        previewAnchor = nil
        previewEntity = nil

        log("Fixture placed at \(anchor.position)")
        state = .roomPlaced
    }

    func finishSession() {
        state = .done
        log("Session complete")
    }

    // MARK: - Element Actions (Move / Details / Delete)

    func moveSelectedElement() {
        guard let info = selectedElement else { return }

        // Restore highlight before applying ghost
        IFCLoader.restoreMaterials(selectedOriginalMaterials)
        selectedOriginalMaterials = []

        if info.isRoomElement {
            // Move within room: change local position
            let entity = info.entity
            movingEntity = entity
            movingOriginalPosition = entity.position

            if let model = entity as? ModelEntity {
                originalMaterials = [(model, model.model?.materials ?? [])]
            }
            IFCLoader.applyGhostEffect(to: entity)

            selectedElement = nil
            selectedEntityRef = nil
            state = .elementMoving
            log("Moving room element \(info.ifcType) #\(info.id)")
        } else {
            // Fixture/wall: move the whole anchor
            let anchor = info.anchor
            placedFixtures.removeAll { $0.anchor === anchor }
            createdWalls.removeAll { $0.anchor === anchor }

            guard let entity = anchor.children.first else {
                selectedElement = nil
                return
            }

            originalMaterials = IFCLoader.collectMaterials(from: entity)
            IFCLoader.applyGhostEffect(to: entity)

            previewAnchor = anchor
            previewEntity = entity
            modelScale = entity.scale.x
            modelRotation = 0
            selectedElement = nil
            selectedEntityRef = nil

            state = .fixturePreviewing
            log("Moving element \(info.ifcType) #\(info.id)")
        }
    }

    func placeMovingElement() {
        guard state == .elementMoving, let entity = movingEntity, let orig = movingOriginalPosition else { return }

        // Record cumulative move offset
        if let idStr = entity.name.split(separator: "_").last, let id = UInt64(idStr) {
            let delta = entity.position - orig
            movedElementOffsets[id, default: .zero] += delta
        }

        IFCLoader.restoreMaterials(originalMaterials)
        originalMaterials = []
        movingEntity = nil
        movingOriginalPosition = nil
        state = .roomPlaced
        log("Element placed")
    }

    func cancelMovingElement() {
        guard let entity = movingEntity, let orig = movingOriginalPosition else { return }
        entity.position = orig
        IFCLoader.restoreMaterials(originalMaterials)
        originalMaterials = []
        movingEntity = nil
        movingOriginalPosition = nil
        state = .roomPlaced
        log("Move cancelled")
    }

    func showDetails() {
        showingDetails = true
    }

    func deleteSelectedElement() {
        guard let info = selectedElement else { return }

        selectedOriginalMaterials = []  // entity is being removed, no need to restore

        if info.isRoomElement {
            // Remove just this entity from the room
            deletedElementIds.insert(info.id)
            info.entity.removeFromParent()
        } else {
            // Remove the whole anchor
            arView?.scene.removeAnchor(info.anchor)
            placedFixtures.removeAll { $0.anchor === info.anchor }
            createdWalls.removeAll { $0.anchor === info.anchor }
        }
        elementMetadata.removeValue(forKey: info.id)

        log("Deleted \(info.ifcType) #\(info.id)")
        selectedElement = nil
        selectedEntityRef = nil
    }

    func hideSelectedElement() {
        guard let info = selectedElement else { return }

        IFCLoader.restoreMaterials(selectedOriginalMaterials)
        selectedOriginalMaterials = []

        info.entity.isEnabled = false
        hiddenElements.append(HiddenElement(
            id: info.id,
            name: info.name ?? "Unnamed",
            ifcType: info.ifcType,
            entity: info.entity
        ))

        log("Hidden \(info.ifcType) #\(info.id)")
        selectedElement = nil
        selectedEntityRef = nil
    }

    func unhideElement(_ element: HiddenElement) {
        element.entity.isEnabled = true
        hiddenElements.removeAll { $0.id == element.id }
        log("Unhidden \(element.ifcType) #\(element.id)")
    }

    func unhideAllElements() {
        for element in hiddenElements {
            element.entity.isEnabled = true
        }
        log("Unhidden \(hiddenElements.count) elements")
        hiddenElements.removeAll()
    }

    func dismissSelection() {
        IFCLoader.restoreMaterials(selectedOriginalMaterials)
        selectedOriginalMaterials = []
        selectedElement = nil
        selectedEntityRef = nil
        showingDetails = false
    }

    // MARK: - Wall Building

    func startWallBuilding() {
        guard let arView = arView else { return }

        wallStartPoint = nil
        wallEndPoint = nil
        wallHeight = 2.5
        wallThickness = 0.2

        // Create centroid marker
        var material = UnlitMaterial()
        material.color = .init(tint: .cyan)

        let disc = MeshResource.generateCylinder(height: 0.005, radius: 0.04)
        let discEntity = ModelEntity(mesh: disc, materials: [material])

        let sphere = MeshResource.generateSphere(radius: 0.02)
        let sphereEntity = ModelEntity(mesh: sphere, materials: [material])
        sphereEntity.position.y = 0.025

        let marker = AnchorEntity(world: .zero)
        marker.addChild(discEntity)
        marker.addChild(sphereEntity)
        arView.scene.addAnchor(marker)
        wallCentroidMarker = marker

        state = .wallStart
        log("Wall building: tap Place to set start point")
    }

    func placeWallStart() {
        guard state == .wallStart, let marker = wallCentroidMarker else { return }
        wallStartPoint = marker.position
        log("Wall start at \(marker.position)")
        state = .wallEnd
    }

    func placeWallEnd() {
        guard state == .wallEnd, let marker = wallCentroidMarker else { return }
        wallEndPoint = marker.position
        log("Wall end at \(marker.position)")
        state = .wallAdjust
    }

    func confirmWall() {
        guard state == .wallAdjust,
              let anchor = wallPreviewAnchor,
              let entity = wallPreviewEntity,
              let element = currentWallElement,
              let startPt = wallStartPoint,
              let endPt = wallEndPoint else { return }

        // Compute wall length
        let dx = endPt.x - startPt.x
        let dz = endPt.z - startPt.z
        let wallLength = sqrt(dx * dx + dz * dz)

        // Apply opaque wall material
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = UIColor(
            red: CGFloat(element.color.r),
            green: CGFloat(element.color.g),
            blue: CGFloat(element.color.b),
            alpha: CGFloat(element.color.a)
        )
        material.metallic = .init(floatLiteral: 0.0)
        material.roughness = .init(floatLiteral: 0.8)
        entity.model?.materials = [material]

        // Register for tap-to-inspect
        wallIdCounter += 1
        let wallId = wallIdCounter
        entity.name = "ifc_\(wallId)"

        let validatedElement = ValidatedElement(
            id: wallId,
            ifcType: element.ifcType,
            name: element.name,
            globalId: nil,
            positions: element.geometry?.positions ?? [],
            normals: element.geometry?.normals ?? [],
            indices: element.geometry?.indices ?? [],
            color: (element.color.r, element.color.g, element.color.b, element.color.a),
            properties: []
        )
        elementMetadata[wallId] = validatedElement

        createdWalls.append(CreatedWall(anchor: anchor, element: element, height: wallHeight, thickness: wallThickness, length: wallLength))

        // Cleanup
        if let marker = wallCentroidMarker {
            arView?.scene.removeAnchor(marker)
            wallCentroidMarker = nil
        }
        wallPreviewAnchor = nil
        wallPreviewEntity = nil
        wallStartPoint = nil
        wallEndPoint = nil
        currentWallElement = nil

        log("Wall placed")
        state = .roomPlaced
    }

    func cancelWallBuilding() {
        if let marker = wallCentroidMarker {
            arView?.scene.removeAnchor(marker)
            wallCentroidMarker = nil
        }
        if let anchor = wallPreviewAnchor {
            arView?.scene.removeAnchor(anchor)
            wallPreviewAnchor = nil
        }
        wallPreviewEntity = nil
        wallStartPoint = nil
        wallEndPoint = nil
        currentWallElement = nil

        log("Wall building cancelled")
        state = .roomPlaced
    }

    private func regenerateWallPreview() {
        guard (state == .wallAdjust || state == .wallEnd),
              let startPt = wallStartPoint else { return }

        let endPt: SIMD3<Float>
        if let locked = wallEndPoint {
            endPt = locked
        } else if let marker = wallCentroidMarker {
            endPt = marker.position
        } else {
            return
        }

        guard let roomAnchor = roomAnchor else { return }
        let roomPos = roomAnchor.position

        // Compute wall coordinates relative to room anchor
        let relStartX = startPt.x - roomPos.x
        let relStartZ = startPt.z - roomPos.z
        let relEndX = endPt.x - roomPos.x
        let relEndZ = endPt.z - roomPos.z

        // Generate wall mesh via Rust
        let element = createWallMesh(
            startX: relStartX, startZ: relStartZ,
            endX: relEndX, endZ: relEndZ,
            height: wallHeight, thickness: wallThickness
        )
        currentWallElement = element

        guard let geometry = element.geometry,
              !geometry.positions.isEmpty else { return }

        do {
            let mesh = try IFCLoader.convertToMesh(
                positions: geometry.positions,
                normals: geometry.normals,
                indices: geometry.indices
            )

            // Ghost material for preview
            var ghost = PhysicallyBasedMaterial()
            ghost.baseColor = .init(tint: UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0))
            ghost.blending = .transparent(opacity: .init(floatLiteral: 0.65))
            ghost.metallic = .init(floatLiteral: 0.1)
            ghost.roughness = .init(floatLiteral: 0.5)

            if let existing = wallPreviewEntity {
                // Update mesh in place
                existing.model = ModelComponent(mesh: mesh, materials: [ghost])
                existing.collision = CollisionComponent(shapes: [ShapeResource.generateConvex(from: mesh)])
            } else {
                // Create new entity
                let entity = ModelEntity(mesh: mesh, materials: [ghost])
                entity.collision = CollisionComponent(shapes: [ShapeResource.generateConvex(from: mesh)])

                let anchor: AnchorEntity
                if let existing = wallPreviewAnchor {
                    anchor = existing
                    anchor.children.removeAll()
                } else {
                    anchor = AnchorEntity(world: roomPos)
                    arView?.scene.addAnchor(anchor)
                    wallPreviewAnchor = anchor
                }
                anchor.addChild(entity)
                wallPreviewEntity = entity
            }
        } catch {
            log("Wall preview mesh failed: \(error)")
        }
    }

    private func updateWallPreview() {
        guard let arView = arView else { return }

        let aimPoint = CGPoint(x: arView.bounds.midX, y: arView.bounds.height * 0.35)
        let results = arView.raycast(from: aimPoint, allowing: .existingPlaneGeometry, alignment: .horizontal)
        guard let result = results.first else { return }
        let col = result.worldTransform.columns.3
        let floorPoint = SIMD3<Float>(col.x, col.y, col.z)

        if state == .wallStart {
            // Move centroid marker to follow camera
            wallCentroidMarker?.position = floorPoint
        } else if state == .wallEnd {
            // Move centroid marker and regenerate wall preview
            wallCentroidMarker?.position = floorPoint
            regenerateWallPreview()
        }
        // wallAdjust: no position update needed
    }

    // MARK: - Export

    func exportMergedIFC() {
        guard let roomAnchor = roomAnchor else {
            log("No room placed")
            return
        }

        // Read room IFC as Data
        guard let roomURL = Bundle.main.url(forResource: "BaseRoom-v2", withExtension: "ifc"),
              let roomData = try? Data(contentsOf: roomURL) else {
            log("Failed to read room IFC")
            return
        }

        // Build fixture inputs
        var fixtureInputs: [FixtureExportInput] = []
        let roomPos = roomAnchor.position

        log("placedFixtures count: \(placedFixtures.count)")
        for fixture in placedFixtures {
            guard let fixtureURL = Bundle.main.url(forResource: fixture.filename, withExtension: "ifc"),
                  let fixtureData = try? Data(contentsOf: fixtureURL) else {
                log("Failed to read \(fixture.filename).ifc")
                continue
            }

            // Get fixture position relative to room
            let pos = fixture.anchor.position
            let relX = pos.x - roomPos.x
            let relY = pos.y - roomPos.y
            let relZ = pos.z - roomPos.z

            // Get rotation from the entity's orientation
            let entity = fixture.anchor.children.first
            let angle = entity?.orientation.angle ?? 0

            fixtureInputs.append(FixtureExportInput(
                ifcData: fixtureData,
                relX: relX,
                relY: relY,
                relZ: relZ,
                rotationY: angle
            ))
        }

        // Build wall inputs
        var wallInputs: [WallExportInput] = []
        for wall in createdWalls {
            guard let geometry = wall.element.geometry else { continue }
            // Wall positions are already relative to room (computed that way in regenerateWallPreview)
            wallInputs.append(WallExportInput(
                positions: geometry.positions,
                normals: geometry.normals,
                indices: geometry.indices,
                relX: 0,
                relY: 0,
                relZ: 0,
                height: wall.height,
                thickness: wall.thickness,
                length: wall.length
            ))
        }

        // Build move inputs
        var moveInputs: [ElementMoveInput] = []
        for (id, offset) in movedElementOffsets {
            moveInputs.append(ElementMoveInput(elementId: id, offsetX: offset.x, offsetY: offset.y, offsetZ: offset.z))
        }

        log("Exporting \(fixtureInputs.count) fixtures + \(wallInputs.count) walls + room (\(deletedElementIds.count) deleted, \(moveInputs.count) moved) as fresh IFC4...")

        do {
            let ifcText = try exportCombinedIfcWithWalls(roomData: roomData, fixtures: fixtureInputs, walls: wallInputs, deletedElementIds: Array(deletedElementIds), movedElements: moveInputs)

            // Write to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "IFC-AR-Export.ifc"
            let fileURL = tempDir.appendingPathComponent(filename)
            try ifcText.write(to: fileURL, atomically: true, encoding: .utf8)
            log("Exported \(fileURL.lastPathComponent) (\(ifcText.count) bytes)")
            exportFileURL = fileURL
        } catch {
            log("Export failed: \(error)")
        }
    }

    // MARK: - BCF Capture

    struct CameraViewpoint {
        let position: SIMD3<Float>
        let direction: SIMD3<Float>
        let up: SIMD3<Float>
        let fieldOfView: Float // degrees
    }

    func captureSnapshot() async -> UIImage? {
        guard let arView = arView else { return nil }
        return await withCheckedContinuation { cont in
            arView.snapshot(saveToHDR: false) { image in
                cont.resume(returning: image)
            }
        }
    }

    func currentViewpoint() -> CameraViewpoint? {
        guard let frame = arView?.session.currentFrame else { return nil }
        let camera = frame.camera
        let t = camera.transform

        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        // Camera looks along -Z in local space
        let direction = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        // Up is +Y in local space
        let up = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)

        // Vertical FOV from intrinsics
        let intrinsics = camera.intrinsics
        let focalLength = intrinsics[1][1]
        let imageHeight = Float(camera.imageResolution.height)
        let fovDegrees = 2 * atan(imageHeight / (2 * focalLength)) * 180 / .pi

        return CameraViewpoint(position: position, direction: direction, up: up, fieldOfView: fovDegrees)
    }

    // MARK: - Grid Rotation

    func updateGridRotation() {
        gridEntity?.orientation = simd_quatf(angle: computedRotation, axis: SIMD3(0, 1, 0))
    }

    // MARK: - Reset

    func reset() {
        if let anchor = roomAnchor {
            arView?.scene.removeAnchor(anchor)
            roomAnchor = nil
        }
        roomEntity = nil
        for fixture in placedFixtures {
            arView?.scene.removeAnchor(fixture.anchor)
        }
        placedFixtures.removeAll()
        for wall in createdWalls {
            arView?.scene.removeAnchor(wall.anchor)
        }
        createdWalls.removeAll()
        if let anchor = previewAnchor {
            arView?.scene.removeAnchor(anchor)
            previewAnchor = nil
        }
        previewEntity = nil
        originalMaterials = []
        elementMetadata = [:]
        selectedElement = nil
        selectedEntityRef = nil
        selectedOriginalMaterials = []
        showingDetails = false
        modelScale = 1.0
        modelRotation = 0

        // Clear element moving state
        if let entity = movingEntity, let orig = movingOriginalPosition {
            entity.position = orig
        }
        movingEntity = nil
        movingOriginalPosition = nil
        deletedElementIds.removeAll()
        movedElementOffsets.removeAll()

        // Clear wall building state
        if let marker = wallCentroidMarker {
            arView?.scene.removeAnchor(marker)
            wallCentroidMarker = nil
        }
        if let anchor = wallPreviewAnchor {
            arView?.scene.removeAnchor(anchor)
            wallPreviewAnchor = nil
        }
        wallPreviewEntity = nil
        wallStartPoint = nil
        wallEndPoint = nil
        currentWallElement = nil

        clearAlignmentVisuals()
        loadingError = nil

        // Clear edge alignment state
        floorPlan = nil
        selectedEdgeIndex = nil
        edgeArrowAngle = 0
        floorPlanRotation = 0
        edgeAlignPointCount = 0
        floorHeightOffset = 0
        parsedElements = nil
        modelMinY = 0
        computedRotation = 0
        computedScaleFactor = 1.0
        modelEdgeLength = 0
        realEdgeLength = 0
        if let marker = edgeAlignMarker {
            arView?.scene.removeAnchor(marker)
            edgeAlignMarker = nil
        }
        if let line = edgeLiveLineAnchor {
            arView?.scene.removeAnchor(line)
            edgeLiveLineAnchor = nil
        }
        if let marker = floorMarker {
            arView?.scene.removeAnchor(marker)
            floorMarker = nil
        }
        floorBaseY = 0
        clearDebugGuides()

        state = .coaching
    }
}
