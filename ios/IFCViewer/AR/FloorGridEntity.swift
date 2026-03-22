import RealityKit
import UIKit

/// A grid overlay that covers the visible floor.
/// Strong visible lines that gently fade only at the far edges.
class FloorGridEntity: Entity, HasModel {
    private let spacing: Float
    private static let gridSize: Float = 30.0

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
        let cellCount = Int(size / spacing)

        let textureSize = 2048
        let gridImage = generateGridImage(
            size: CGSize(width: textureSize, height: textureSize),
            cellCount: cellCount
        )

        let mesh = MeshResource.generatePlane(width: size, depth: size)

        var material = UnlitMaterial()
        if let cgImage = gridImage.cgImage,
           let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        } else {
            material.color = .init(tint: .white.withAlphaComponent(0.3))
        }
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))

        self.model = ModelComponent(mesh: mesh, materials: [material])
    }

    private func generateGridImage(size: CGSize, cellCount: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ctx = context.cgContext
            ctx.clear(CGRect(origin: .zero, size: size))

            let cellPixels = size.width / CGFloat(cellCount)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = size.width / 2

            // Fade: fully visible up to 60% of radius, then fade to 0 at edge
            func fadeForDistance(_ dist: CGFloat) -> CGFloat {
                let ratio = dist / maxRadius
                if ratio < 0.6 { return 1.0 }
                // Smooth fade from 60% to 100%
                let t = (ratio - 0.6) / 0.4
                return max(0, 1.0 - t * t)
            }

            // --- Regular grid lines ---
            let lineAlpha: CGFloat = 0.45
            let lineWidth: CGFloat = 1.5

            // Vertical lines
            for i in 0...cellCount {
                let x = CGFloat(i) * cellPixels
                let isCenter = i == cellCount / 2
                if isCenter { continue } // draw center lines separately

                // Draw in segments for distance fade
                let segCount = 32
                let segLen = size.height / CGFloat(segCount)
                for s in 0..<segCount {
                    let y1 = CGFloat(s) * segLen
                    let y2 = y1 + segLen
                    let midY = (y1 + y2) / 2
                    let dist = hypot(x - center.x, midY - center.y)
                    let alpha = lineAlpha * fadeForDistance(dist)
                    guard alpha > 0.01 else { continue }

                    ctx.setStrokeColor(UIColor.white.withAlphaComponent(alpha).cgColor)
                    ctx.setLineWidth(lineWidth)
                    ctx.move(to: CGPoint(x: x, y: y1))
                    ctx.addLine(to: CGPoint(x: x, y: y2))
                    ctx.strokePath()
                }
            }

            // Horizontal lines
            for i in 0...cellCount {
                let y = CGFloat(i) * cellPixels
                let isCenter = i == cellCount / 2
                if isCenter { continue }

                let segCount = 32
                let segLen = size.width / CGFloat(segCount)
                for s in 0..<segCount {
                    let x1 = CGFloat(s) * segLen
                    let x2 = x1 + segLen
                    let midX = (x1 + x2) / 2
                    let dist = hypot(midX - center.x, y - center.y)
                    let alpha = lineAlpha * fadeForDistance(dist)
                    guard alpha > 0.01 else { continue }

                    ctx.setStrokeColor(UIColor.white.withAlphaComponent(alpha).cgColor)
                    ctx.setLineWidth(lineWidth)
                    ctx.move(to: CGPoint(x: x1, y: y))
                    ctx.addLine(to: CGPoint(x: x2, y: y))
                    ctx.strokePath()
                }
            }

            // --- Center axis lines (brighter, thicker) ---
            let centerPos = size.width / 2
            let axisAlpha: CGFloat = 0.8
            let axisWidth: CGFloat = 3.0

            // Vertical center axis
            let segCount = 32
            let segLen = size.height / CGFloat(segCount)
            for s in 0..<segCount {
                let y1 = CGFloat(s) * segLen
                let y2 = y1 + segLen
                let midY = (y1 + y2) / 2
                let dist = abs(midY - center.y)
                let alpha = axisAlpha * fadeForDistance(dist)
                guard alpha > 0.01 else { continue }

                ctx.setStrokeColor(UIColor.white.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(axisWidth)
                ctx.move(to: CGPoint(x: centerPos, y: y1))
                ctx.addLine(to: CGPoint(x: centerPos, y: y2))
                ctx.strokePath()
            }

            // Horizontal center axis
            for s in 0..<segCount {
                let x1 = CGFloat(s) * segLen
                let x2 = x1 + segLen
                let midX = (x1 + x2) / 2
                let dist = abs(midX - center.x)
                let alpha = axisAlpha * fadeForDistance(dist)
                guard alpha > 0.01 else { continue }

                ctx.setStrokeColor(UIColor.white.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(axisWidth)
                ctx.move(to: CGPoint(x: x1, y: centerPos))
                ctx.addLine(to: CGPoint(x: x2, y: centerPos))
                ctx.strokePath()
            }
        }
    }
}
