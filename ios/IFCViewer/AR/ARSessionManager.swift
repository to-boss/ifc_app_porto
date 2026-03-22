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
    case loading           // loading room IFC
    case previewing        // ghost preview of room
    case roomPlaced        // room placed, show fixture picker
    case fixtureLoading    // loading a fixture IFC
    case fixturePreviewing // ghost preview of fixture
    case wallStart         // centroid marker follows camera, waiting for Place
    case wallEnd           // live 3D wall preview, endpoint follows camera
    case wallAdjust        // both points locked, sliders for height/width
    case done              // all models placed
}

@MainActor
class ARSessionManager: ObservableObject {
    @Published var state: ARState = .coaching
    @Published var gridRotation: Float = 0
    @Published var alignmentPointCount: Int = 0
    @Published var loadingError: String?
    @Published var debugLog: [String] = []
    @Published var modelScale: Float = 1.0 {
        didSet { applyPreviewTransform() }
    }
    @Published var modelRotation: Float = 0 {
        didSet { applyPreviewTransform() }
    }
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

    private var floorAnchor: AnchorEntity?
    private var gridEntity: FloorGridEntity?

    // Alignment
    private var alignmentPoints: [SIMD3<Float>] = []
    private var alignmentMarkers: [AnchorEntity] = []
    private var alignmentLine: AnchorEntity?

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
            return
        }

        // Entity tap detection when models are placed
        if state == .roomPlaced || state == .done {
            // If action menu is showing, dismiss it
            if selectedElement != nil {
                selectedElement = nil
                selectedEntityRef = nil
                showingDetails = false
                return
            }

            // Hit-test against placed entities
            let hits = arView.entities(at: point)
            for entity in hits {
                // Walk up to find a named ifc_ entity
                var current: Entity? = entity
                while let e = current {
                    if e.name.hasPrefix("ifc_"),
                       let idStr = e.name.split(separator: "_").last,
                       let id = UInt64(idStr),
                       let meta = elementMetadata[id] {
                        // Find the owning anchor
                        if let anchor = findOwningAnchor(for: e) {
                            selectedEntityRef = anchor
                            selectedScreenPoint = point
                            selectedElement = ElementInfo(
                                id: id,
                                ifcType: meta.ifcType,
                                name: meta.name,
                                globalId: meta.globalId,
                                properties: meta.properties,
                                anchor: anchor
                            )
                            log("Selected: \(meta.ifcType) #\(id)")
                            return
                        }
                    }
                    current = e.parent
                }
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
        loadModel(named: "BaseRoom-v2")
    }

    // MARK: - IFC Model Loading

    private func loadModel(named filename: String) {
        loadingError = nil
        log("Loading \(filename)...")
        IFCLoader.onLog = { [weak self] msg in self?.log(msg) }

        let targetState: ARState = (state == .loading) ? .previewing : .fixturePreviewing

        Task.detached {
            do {
                let elements = try await IFCLoader.parseAndValidate(named: filename)
                await MainActor.run {
                    self.finishLoading(elements, targetState: targetState)
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

    private func finishLoading(_ elements: [ValidatedElement], targetState: ARState) {
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
            state = targetState
        } catch {
            log("FAILED: \(error)")
            loadingError = "\(error)"
            state = .roomPlaced
        }
    }

    // MARK: - Fixture Loading

    func loadFixture(named filename: String) {
        pendingFixtureFilename = filename
        state = .fixtureLoading
        loadModel(named: filename)
    }

    // MARK: - Preview

    func updatePreviewPosition() {
        guard let arView = arView else { return }

        // Update preview anchor position
        if state == .previewing || state == .fixturePreviewing {
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let results = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal)
            if let result = results.first {
                let col = result.worldTransform.columns.3
                previewAnchor?.position = SIMD3<Float>(col.x, col.y, col.z)
            }
        }

        // Wall building: update centroid marker and live preview
        if state == .wallStart || state == .wallEnd {
            updateWallPreview()
        }

        // Track selected entity screen position for the bubble
        if let entity = selectedEntityRef, selectedElement != nil {
            let worldPos = entity.position(relativeTo: nil)
            if let screenPt = arView.project(worldPos) {
                selectedScreenPoint = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))
            }
        }
    }

    private func applyPreviewTransform() {
        previewEntity?.scale = SIMD3<Float>(repeating: modelScale)
        previewEntity?.orientation = simd_quatf(angle: gridRotation + modelRotation, axis: SIMD3(0, 1, 0))
    }

    func placeRoom() {
        guard state == .previewing, let anchor = previewAnchor, let entity = previewEntity else { return }

        IFCLoader.restoreMaterials(originalMaterials)
        originalMaterials = []

        roomAnchor = anchor
        roomEntity = entity
        previewAnchor = nil
        previewEntity = nil

        log("Room placed at \(anchor.position)")
        state = .roomPlaced
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
        let anchor = info.anchor

        // Remove from placed list
        placedFixtures.removeAll { $0.anchor === anchor }

        // Get the root entity (first child of anchor)
        guard let entity = anchor.children.first else {
            selectedElement = nil
            return
        }

        // Apply ghost effect for preview
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

    func showDetails() {
        showingDetails = true
    }

    func deleteSelectedElement() {
        guard let info = selectedElement else { return }
        let anchor = info.anchor

        arView?.scene.removeAnchor(anchor)
        placedFixtures.removeAll { $0.anchor === anchor }
        createdWalls.removeAll { $0.anchor === anchor }
        elementMetadata.removeValue(forKey: info.id)

        log("Deleted \(info.ifcType) #\(info.id)")
        selectedElement = nil
        selectedEntityRef = nil
    }

    func dismissSelection() {
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

        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let results = arView.raycast(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal)
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

        log("Exporting \(fixtureInputs.count) fixtures + \(wallInputs.count) walls + room as fresh IFC4...")

        do {
            let ifcText = try exportCombinedIfcWithWalls(roomData: roomData, fixtures: fixtureInputs, walls: wallInputs)

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
        gridEntity?.orientation = simd_quatf(angle: gridRotation, axis: SIMD3(0, 1, 0))
    }

    func adjustRotation(by delta: Float) {
        guard state == .calibrating else { return }
        gridRotation += delta
        updateGridRotation()
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
        showingDetails = false
        modelScale = 1.0
        modelRotation = 0

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

        state = floorAnchor != nil ? .aligning : .coaching
    }
}
