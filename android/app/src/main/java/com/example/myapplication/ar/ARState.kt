package com.example.myapplication.ar

import com.example.myapplication.ffi.IfcProperty
import com.example.myapplication.ffi.IfcQuantity

enum class ARState {
    COACHING,
    ALIGNING,
    CALIBRATING,
    LOADING,
    PREVIEWING,
    ROOM_PLACED,
    WALL_START,
    WALL_END,
    WALL_ADJUST,
    ELEMENT_MOVING,
    FIXTURE_PREVIEWING
}

data class AlignmentPoint(val x: Float, val y: Float, val z: Float)

data class PlacedFixture(
    val name: String,
    val ifcAsset: String,
    val relX: Float,
    val relY: Float,
    val relZ: Float,
    val rotY: Float
)

data class PlacedWall(
    val positions: List<Float>,
    val normals: List<Float>,
    val indices: List<Int>,
    val relX: Float,
    val relY: Float,
    val relZ: Float,
    val height: Float,
    val thickness: Float,
    val length: Float
)

data class BcfIssue(
    val id: String,
    val title: String,
    val description: String,
    val priority: String,
    val status: String,
    val assignee: String,
    val cameraX: Float,
    val cameraY: Float,
    val cameraZ: Float,
    val dirX: Float,
    val dirY: Float,
    val dirZ: Float,
    val fovDegrees: Float,
    val elementGlobalId: String?,
    val snapshotBytes: ByteArray?
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is BcfIssue) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}

data class SelectedElement(
    val entityId: String,
    val ifcId: Long,
    val name: String,
    val ifcType: String,
    val globalId: String?,
    val properties: List<IfcProperty>,
    val quantities: List<IfcQuantity>
)
