import Foundation
import UIKit
import RealityKit
import os

private let logger = Logger(subsystem: "com.ifcar.viewer", category: "IFCLoader")

enum IFCLoaderError: Error, LocalizedError {
    case bundleFileNotFound(String)
    case noGeometry
    case parseFailed(String)
    case meshGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundleFileNotFound(let name): return "Bundle file not found: \(name)"
        case .noGeometry: return "No geometry found in IFC file"
        case .parseFailed(let msg): return "IFC parse failed: \(msg)"
        case .meshGenerationFailed(let msg): return "Mesh generation failed: \(msg)"
        }
    }
}

/// Validated element ready for mesh conversion on MainActor.
struct ValidatedElement: Sendable {
    let id: UInt64
    let ifcType: String
    let name: String?
    let positions: [Float]
    let normals: [Float]
    let indices: [UInt32]
    let color: (r: Float, g: Float, b: Float, a: Float)
    let properties: [IfcProperty]
}

/// Lightweight info for displaying element details after tap.
struct ElementInfo {
    let id: UInt64
    let ifcType: String
    let name: String?
    let properties: [IfcProperty]
    let anchor: AnchorEntity
}

enum IFCLoader {
    @MainActor static var onLog: ((String) -> Void)?

    private static func log(_ msg: String) {
        logger.info("\(msg)")
        Task { @MainActor in onLog?(msg) }
    }

    /// Phase 1: Parse IFC on background thread, validate geometry, return raw data.
    static func parseAndValidate(named filename: String) async throws -> [ValidatedElement] {
        log("Phase 1: Loading \(filename)")

        guard let url = Bundle.main.url(forResource: filename, withExtension: "ifc") else {
            log("ERROR: file not found: \(filename).ifc")
            throw IFCLoaderError.bundleFileNotFound(filename)
        }

        let ifcData = try Data(contentsOf: url)
        log("Read \(ifcData.count) bytes")

        // Parse on background thread
        log("Parsing IFC (background)...")
        let model: IfcModel
        do {
            model = try await Task.detached(priority: .userInitiated) {
                try parseIfc(data: ifcData)
            }.value
        } catch {
            log("parseIfc FAILED: \(error)")
            throw IFCLoaderError.parseFailed("\(error)")
        }

        log("Parsed: \(model.elements.count) elements")

        // Validate on background thread
        var validated: [ValidatedElement] = []

        for element in model.elements {
            guard let geometry = element.geometry else { continue }
            let vertCount = geometry.positions.count / 3

            if geometry.positions.isEmpty || geometry.indices.isEmpty { continue }

            let maxIndex = geometry.indices.max() ?? 0
            if maxIndex >= UInt32(vertCount) {
                log("Skip #\(element.id): bad index \(maxIndex) >= \(vertCount)")
                continue
            }
            if geometry.positions.count != geometry.normals.count {
                log("Skip #\(element.id): pos/norm mismatch")
                continue
            }
            let hasInvalid = geometry.positions.contains { $0.isNaN || $0.isInfinite }
                || geometry.normals.contains { $0.isNaN || $0.isInfinite }
            if hasInvalid {
                log("Skip #\(element.id): NaN/Inf")
                continue
            }

            let triCount = geometry.indices.count / 3
            log("Valid #\(element.id) \(element.ifcType): \(vertCount)v \(triCount)t")

            validated.append(ValidatedElement(
                id: element.id,
                ifcType: element.ifcType,
                name: element.name,
                positions: geometry.positions,
                normals: geometry.normals,
                indices: geometry.indices,
                color: (element.color.r, element.color.g, element.color.b, element.color.a),
                properties: element.properties
            ))
        }

        log("Phase 1 done: \(validated.count) valid elements")
        if validated.isEmpty {
            throw IFCLoaderError.noGeometry
        }
        return validated
    }

    /// Phase 2: Build RealityKit meshes on MainActor.
    /// Returns the root entity and a metadata map (element id → ValidatedElement).
    @MainActor
    static func buildEntities(from elements: [ValidatedElement]) throws -> (Entity, [UInt64: ValidatedElement]) {
        let logFn = onLog
        func log(_ msg: String) {
            logger.info("\(msg)")
            logFn?(msg)
        }

        log("Phase 2: Building \(elements.count) meshes (main thread)")
        let root = Entity()
        var metadata: [UInt64: ValidatedElement] = [:]

        for elem in elements {
            log("Mesh #\(elem.id) \(elem.ifcType)...")
            do {
                let mesh = try convertToMesh(
                    positions: elem.positions,
                    normals: elem.normals,
                    indices: elem.indices
                )

                var material = PhysicallyBasedMaterial()
                material.baseColor.tint = UIColor(
                    red: CGFloat(elem.color.r),
                    green: CGFloat(elem.color.g),
                    blue: CGFloat(elem.color.b),
                    alpha: CGFloat(elem.color.a)
                )
                material.metallic = .init(floatLiteral: 0.0)
                material.roughness = .init(floatLiteral: 0.8)

                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.name = "ifc_\(elem.id)"

                // Add collision for tap detection
                let shape = ShapeResource.generateConvex(from: mesh)
                entity.collision = CollisionComponent(shapes: [shape])

                root.addChild(entity)
                metadata[elem.id] = elem
                log("OK #\(elem.id)")
            } catch {
                log("FAIL #\(elem.id): \(error)")
            }
        }

        log("Phase 2 done: \(root.children.count) meshes built")
        return (root, metadata)
    }

    // MARK: - Ghost Effect

    @MainActor
    static func collectMaterials(from entity: Entity) -> [(ModelEntity, [Material])] {
        var result: [(ModelEntity, [Material])] = []
        for child in entity.children {
            if let model = child as? ModelEntity, let materials = model.model?.materials {
                result.append((model, materials))
            }
            result.append(contentsOf: collectMaterials(from: child))
        }
        return result
    }

    @MainActor
    static func applyGhostEffect(to entity: Entity) {
        for child in entity.children {
            if let model = child as? ModelEntity {
                model.model?.materials = model.model?.materials.map { _ in
                    var ghost = PhysicallyBasedMaterial()
                    ghost.baseColor = .init(tint: UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0))
                    ghost.blending = .transparent(opacity: .init(floatLiteral: 0.65))
                    ghost.metallic = .init(floatLiteral: 0.1)
                    ghost.roughness = .init(floatLiteral: 0.5)
                    return ghost as Material
                } ?? []
            }
            applyGhostEffect(to: child)
        }
    }

    @MainActor
    static func restoreMaterials(_ originals: [(ModelEntity, [Material])]) {
        for (model, materials) in originals {
            model.model?.materials = materials
        }
    }

    /// Convert raw arrays to MeshResource. Must run on @MainActor.
    @MainActor
    private static func convertToMesh(
        positions: [Float],
        normals: [Float],
        indices: [UInt32]
    ) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "ifc-mesh")

        let vertexCount = positions.count / 3
        var pos = [SIMD3<Float>]()
        pos.reserveCapacity(vertexCount)
        for i in 0..<vertexCount {
            let base = i * 3
            pos.append(SIMD3(positions[base], positions[base + 1], positions[base + 2]))
        }

        var norm = [SIMD3<Float>]()
        norm.reserveCapacity(vertexCount)
        for i in 0..<vertexCount {
            let base = i * 3
            norm.append(SIMD3(normals[base], normals[base + 1], normals[base + 2]))
        }

        descriptor.positions = MeshBuffers.Positions(pos)
        descriptor.normals = MeshBuffers.Normals(norm)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }
}
