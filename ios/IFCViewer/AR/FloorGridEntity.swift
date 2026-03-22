import RealityKit
import UIKit

/// A grid overlay that covers the entire visible floor.
/// Uses a large fixed-size plane (50×50m) so the edges are never visible.
class FloorGridEntity: Entity, HasModel {
    private let spacing: Float
    private static let gridSize: Float = 50.0 // meters — large enough to feel infinite

    init(spacing: Float = 0.5) {
        self.spacing = spacing
        super.init()
        buildGrid()
    }

    @MainActor @preconcurrency required init() {
        self.spacing = 0.5
        super.init()
        buildGrid()
    }

    private func buildGrid() {
        let size = Self.gridSize
        let cellCount = Int(size / spacing) // 100 cells at 0.5m spacing

        let textureSize = 1024
        let gridImage = generateGridImage(
            size: CGSize(width: textureSize, height: textureSize),
            cellCount: cellCount
        )

        let mesh = MeshResource.generatePlane(width: size, depth: size)

        var material = UnlitMaterial()
        if let cgImage = gridImage.cgImage,
           let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) {
            material.color = .init(tint: .white.withAlphaComponent(0.5), texture: .init(texture))
        } else {
            material.color = .init(tint: .white.withAlphaComponent(0.15))
        }
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))

        self.model = ModelComponent(mesh: mesh, materials: [material])
    }

    private func generateGridImage(size: CGSize, cellCount: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ctx = context.cgContext
            ctx.clear(CGRect(origin: .zero, size: size))

            // Grid lines
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(1.0)

            let cellPixels = size.width / CGFloat(cellCount)

            for i in 0...cellCount {
                let pos = CGFloat(i) * cellPixels
                ctx.move(to: CGPoint(x: pos, y: 0))
                ctx.addLine(to: CGPoint(x: pos, y: size.height))
                ctx.move(to: CGPoint(x: 0, y: pos))
                ctx.addLine(to: CGPoint(x: size.width, y: pos))
            }
            ctx.strokePath()

            // Thicker center axis lines
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(2.5)

            let center = size.width / 2
            ctx.move(to: CGPoint(x: center, y: 0))
            ctx.addLine(to: CGPoint(x: center, y: size.height))
            ctx.move(to: CGPoint(x: 0, y: center))
            ctx.addLine(to: CGPoint(x: size.width, y: center))
            ctx.strokePath()
        }
    }
}
