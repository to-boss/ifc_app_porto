import SwiftUI

struct FloorPlanView: View {
    let floorPlan: FloorPlan
    @Binding var selectedEdgeIndex: Int?
    @Binding var arrowAngle: Float  // radians, user-controlled via dial
    @Binding var canvasRotation: Float  // radians, controlled via slider
    let onConfirm: () -> Void

    private let padding: CGFloat = 40
    private let dialRadius: CGFloat = 50

    var body: some View {
        VStack(spacing: 12) {
            Text("Select a wall edge")
                .font(.headline)
                .foregroundStyle(.white)

            GeometryReader { geo in
                let transform = computeTransform(size: geo.size)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                Canvas { context, size in
                    // Draw all edges
                    for (index, edge) in floorPlan.edges.enumerated() {
                        let p1 = mapPoint(x: edge.x1, z: edge.z1, transform: transform)
                        let p2 = mapPoint(x: edge.x2, z: edge.z2, transform: transform)

                        var path = Path()
                        path.move(to: p1)
                        path.addLine(to: p2)

                        let isSelected = selectedEdgeIndex == index
                        let isWall = edge.ifcType.uppercased().contains("WALL")
                        let color: Color = isSelected ? .cyan : (isWall ? .white : .gray.opacity(0.4))
                        context.stroke(path, with: .color(color), lineWidth: isSelected ? 4 : (isWall ? 2 : 1))
                    }

                    // Draw direction arrow on selected edge (ORANGE, not cyan)
                    if let idx = selectedEdgeIndex, idx < floorPlan.edges.count {
                        let edge = floorPlan.edges[idx]
                        let mid = mapPoint(
                            x: (edge.x1 + edge.x2) / 2,
                            z: (edge.z1 + edge.z2) / 2,
                            transform: transform
                        )

                        // Dial circle
                        let dialRect = CGRect(
                            x: mid.x - dialRadius,
                            y: mid.y - dialRadius,
                            width: dialRadius * 2,
                            height: dialRadius * 2
                        )
                        context.stroke(Path(ellipseIn: dialRect), with: .color(.orange.opacity(0.3)), lineWidth: 1.5)

                        // Arrow from center outward
                        let angle = CGFloat(arrowAngle)
                        let arrowEnd = CGPoint(
                            x: mid.x + cos(angle) * dialRadius,
                            y: mid.y + sin(angle) * dialRadius
                        )

                        // Arrow line
                        var arrowPath = Path()
                        arrowPath.move(to: mid)
                        arrowPath.addLine(to: arrowEnd)
                        context.stroke(arrowPath, with: .color(.orange), lineWidth: 3)

                        // Arrowhead
                        let headLen: CGFloat = 12
                        let headAngle: CGFloat = 0.4
                        let left = CGPoint(
                            x: arrowEnd.x - headLen * cos(angle - headAngle),
                            y: arrowEnd.y - headLen * sin(angle - headAngle)
                        )
                        let right = CGPoint(
                            x: arrowEnd.x - headLen * cos(angle + headAngle),
                            y: arrowEnd.y - headLen * sin(angle + headAngle)
                        )
                        var headPath = Path()
                        headPath.move(to: arrowEnd)
                        headPath.addLine(to: left)
                        headPath.move(to: arrowEnd)
                        headPath.addLine(to: right)
                        context.stroke(headPath, with: .color(.orange), lineWidth: 3)

                        // Handle dot
                        let dotRect = CGRect(x: arrowEnd.x - 8, y: arrowEnd.y - 8, width: 16, height: 16)
                        context.fill(Path(ellipseIn: dotRect), with: .color(.orange))
                    }
                }
                .rotationEffect(Angle(radians: Double(canvasRotation)))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // SwiftUI gesture coords are in local (unrotated) space — no inverse needed
                            handleInteraction(at: value.location, in: geo.size, transform: transform, isDrag: true)
                        }
                        .onEnded { value in
                            let displacement = hypot(
                                value.location.x - value.startLocation.x,
                                value.location.y - value.startLocation.y
                            )
                            if displacement < 10 {
                                handleInteraction(at: value.location, in: geo.size, transform: transform, isDrag: false)
                            }
                        }
                )
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))

            // Rotation slider
            HStack(spacing: 8) {
                Image(systemName: "rotate.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Slider(value: $canvasRotation, in: 0...(2 * .pi))
                Text(String(format: "%.0f°", canvasRotation * 180 / .pi))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 40)
            }

            // Edge label
            if let idx = selectedEdgeIndex, idx < floorPlan.edges.count {
                let edge = floorPlan.edges[idx]
                Text(edge.name ?? edge.ifcType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Confirm button
            if selectedEdgeIndex != nil {
                Button(action: onConfirm) {
                    Label("Confirm Edge", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.green.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Coordinate Mapping

    private var aspectRatio: CGFloat {
        let w = CGFloat(floorPlan.maxX - floorPlan.minX)
        let h = CGFloat(floorPlan.maxZ - floorPlan.minZ)
        guard w > 0.001 && h > 0.001 else { return 1 }
        return w / h
    }

    private struct Transform {
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    private func computeTransform(size: CGSize) -> Transform {
        let modelW = CGFloat(floorPlan.maxX - floorPlan.minX)
        let modelH = CGFloat(floorPlan.maxZ - floorPlan.minZ)
        guard modelW > 0.001 && modelH > 0.001 else {
            return Transform(scale: 1, offsetX: size.width / 2, offsetY: size.height / 2)
        }

        let scaleX = (size.width - padding * 2) / modelW
        let scaleY = (size.height - padding * 2) / modelH
        let scale = min(scaleX, scaleY)

        let offsetX = (size.width - modelW * scale) / 2
        let offsetY = (size.height - modelH * scale) / 2

        return Transform(scale: scale, offsetX: offsetX, offsetY: offsetY)
    }

    private func mapPoint(x: Float, z: Float, transform: Transform) -> CGPoint {
        CGPoint(
            x: transform.offsetX + CGFloat(x - floorPlan.minX) * transform.scale,
            y: transform.offsetY + CGFloat(z - floorPlan.minZ) * transform.scale
        )
    }

    /// Inverse-rotate a screen point back to canvas coordinates (undo the rotationEffect).
    private func inverseRotatePoint(_ point: CGPoint, center: CGPoint) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let angle = -Double(canvasRotation)
        let cosA = cos(angle)
        let sinA = sin(angle)
        return CGPoint(
            x: center.x + CGFloat(cosA) * dx - CGFloat(sinA) * dy,
            y: center.y + CGFloat(sinA) * dx + CGFloat(cosA) * dy
        )
    }

    // MARK: - Interaction

    private func handleInteraction(at location: CGPoint, in size: CGSize, transform: Transform, isDrag: Bool) {
        // If we already have a selection, check if dragging the dial handle
        if let idx = selectedEdgeIndex, idx < floorPlan.edges.count {
            let edge = floorPlan.edges[idx]
            let mid = mapPoint(
                x: (edge.x1 + edge.x2) / 2,
                z: (edge.z1 + edge.z2) / 2,
                transform: transform
            )

            let dx = location.x - mid.x
            let dy = location.y - mid.y
            let dist = sqrt(dx * dx + dy * dy)

            // If within or near the dial, rotate the arrow
            if dist < dialRadius * 2.0 && isDrag {
                arrowAngle = Float(atan2(dy, dx))
                return
            }
        }

        // Otherwise, select closest edge (only on tap end, not drag)
        if !isDrag {
            selectedEdgeIndex = findClosestEdge(at: location, transform: transform)

            // Set default arrow perpendicular to selected edge
            if let idx = selectedEdgeIndex, idx < floorPlan.edges.count {
                let edge = floorPlan.edges[idx]
                let edgeAngle = atan2(edge.z2 - edge.z1, edge.x2 - edge.x1)
                arrowAngle = edgeAngle + .pi / 2
            }
        }
    }

    private func findClosestEdge(at point: CGPoint, transform: Transform) -> Int? {
        var bestIndex: Int?
        var bestDist: CGFloat = 30

        for (index, edge) in floorPlan.edges.enumerated() {
            let isWall = edge.ifcType.uppercased().contains("WALL")
            if !isWall { continue }

            let p1 = mapPoint(x: edge.x1, z: edge.z1, transform: transform)
            let p2 = mapPoint(x: edge.x2, z: edge.z2, transform: transform)
            let dist = pointToSegmentDistance(point: point, a: p1, b: p2)

            if dist < bestDist {
                bestDist = dist
                bestIndex = index
            }
        }

        return bestIndex
    }

    private func pointToSegmentDistance(point: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0.001 else {
            return hypot(point.x - a.x, point.y - a.y)
        }

        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}
