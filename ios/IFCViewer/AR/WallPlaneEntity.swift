import RealityKit
import UIKit

/// A semi-transparent overlay that visualizes a detected wall surface,
/// with a bright line at the base showing where the wall meets the floor.
class WallPlaneEntity: Entity, HasModel {
    private var edgeLine: ModelEntity?

    init(width: Float, height: Float) {
        super.init()
        updateExtent(width: width, height: height)
    }

    @MainActor @preconcurrency required init() {
        super.init()
    }

    func updateExtent(width: Float, height: Float) {
        // Wall overlay
        let mesh = MeshResource.generatePlane(width: width, height: height)
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.2))
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
        self.model = ModelComponent(mesh: mesh, materials: [material])

        // Floor-level edge line — bright cyan line at the base of the wall
        if let existing = edgeLine {
            existing.removeFromParent()
        }

        let lineWidth: Float = width + 0.5 // extend slightly beyond wall edges
        let lineMesh = MeshResource.generateBox(width: lineWidth, height: 0.002, depth: 0.008)
        var lineMaterial = UnlitMaterial()
        lineMaterial.color = .init(tint: UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0))
        let line = ModelEntity(mesh: lineMesh, materials: [lineMaterial])

        // Position at bottom edge of the wall plane
        // The wall plane is centered on the anchor; bottom edge is at -height/2
        line.position = SIMD3<Float>(0, -height / 2, 0.01) // slightly in front of wall
        edgeLine = line
        self.addChild(line)
    }
}
