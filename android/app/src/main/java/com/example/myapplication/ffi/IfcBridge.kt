package com.example.myapplication.ffi

// ── Re-export generated UniFFI data types ────────────────────────────────────
typealias IfcArError = uniffi.ifc_ar_core.IfcArException
typealias ElementColor = uniffi.ifc_ar_core.ElementColor
typealias MeshData = uniffi.ifc_ar_core.MeshData
typealias IfcProperty = uniffi.ifc_ar_core.IfcProperty
typealias IfcQuantity = uniffi.ifc_ar_core.IfcQuantity
typealias IfcMaterialLayer = uniffi.ifc_ar_core.IfcMaterialLayer
typealias IfcMaterialInfo = uniffi.ifc_ar_core.IfcMaterialInfo
typealias IfcTypeInfo = uniffi.ifc_ar_core.IfcTypeInfo
typealias IfcClassificationInfo = uniffi.ifc_ar_core.IfcClassificationInfo
typealias IfcElement = uniffi.ifc_ar_core.IfcElement
typealias SpatialNode = uniffi.ifc_ar_core.SpatialNode
typealias SpatialTree = uniffi.ifc_ar_core.SpatialTree
typealias ModelBounds = uniffi.ifc_ar_core.ModelBounds
typealias IfcModel = uniffi.ifc_ar_core.IfcModel

// ── Thin wrapper around generated UniFFI functions ───────────────────────────

object IfcBridge {
    fun parseAndExportGlb(data: ByteArray): ByteArray =
        uniffi.ifc_ar_core.parseAndExportGlb(data)

    fun parseIfc(data: ByteArray): IfcModel =
        uniffi.ifc_ar_core.parseIfc(data)

    fun createWallMesh(
        startX: Float, startZ: Float,
        endX: Float, endZ: Float,
        height: Float, thickness: Float
    ): IfcElement = uniffi.ifc_ar_core.createWallMesh(startX, startZ, endX, endZ, height, thickness)
}
