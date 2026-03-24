package com.example.myapplication.ar

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.myapplication.ffi.IfcBridge
import com.example.myapplication.ffi.IfcModel
import com.example.myapplication.ui.BCFExporter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ARViewModel : ViewModel() {

    // ── State machine ─────────────────────────────────────────────────────────

    private val _arState = MutableStateFlow(ARState.FLOOR_PLAN)
    val arState: StateFlow<ARState> = _arState.asStateFlow()

    // ── Floor plan ────────────────────────────────────────────────────────────

    private val _floorPlanPoints = MutableStateFlow<List<FloorPlanPoint>>(emptyList())
    val floorPlanPoints: StateFlow<List<FloorPlanPoint>> = _floorPlanPoints.asStateFlow()

    // ── Alignment ─────────────────────────────────────────────────────────────

    private val _alignmentPoints = MutableStateFlow<List<AlignmentPoint>>(emptyList())
    val alignmentPoints: StateFlow<List<AlignmentPoint>> = _alignmentPoints.asStateFlow()

    // ── Calibration ───────────────────────────────────────────────────────────

    private val _gridRotation = MutableStateFlow(0f)
    val gridRotation: StateFlow<Float> = _gridRotation.asStateFlow()

    // ── Room preview ──────────────────────────────────────────────────────────

    private val _roomScale = MutableStateFlow(1.0f)
    val roomScale: StateFlow<Float> = _roomScale.asStateFlow()

    private val _roomRotationY = MutableStateFlow(0f)
    val roomRotationY: StateFlow<Float> = _roomRotationY.asStateFlow()

    // ── Wall parameters ───────────────────────────────────────────────────────

    private val _wallHeight = MutableStateFlow(2.4f)
    val wallHeight: StateFlow<Float> = _wallHeight.asStateFlow()

    private val _wallThickness = MutableStateFlow(0.15f)
    val wallThickness: StateFlow<Float> = _wallThickness.asStateFlow()

    // ── Selection ─────────────────────────────────────────────────────────────

    private val _selectedElement = MutableStateFlow<SelectedElement?>(null)
    val selectedElement: StateFlow<SelectedElement?> = _selectedElement.asStateFlow()

    // ── UI sheet toggles ──────────────────────────────────────────────────────

    private val _showFixturePicker = MutableStateFlow(false)
    val showFixturePicker: StateFlow<Boolean> = _showFixturePicker.asStateFlow()

    private val _showDetailsSheet = MutableStateFlow(false)
    val showDetailsSheet: StateFlow<Boolean> = _showDetailsSheet.asStateFlow()

    private val _showBcfForm = MutableStateFlow(false)
    val showBcfForm: StateFlow<Boolean> = _showBcfForm.asStateFlow()

    // ── BCF ───────────────────────────────────────────────────────────────────

    private val _bcfIssues = MutableStateFlow<List<BcfIssue>>(emptyList())
    val bcfIssues: StateFlow<List<BcfIssue>> = _bcfIssues.asStateFlow()

    private val _pendingSnapshotBytes = MutableStateFlow<ByteArray?>(null)
    val pendingSnapshotBytes: StateFlow<ByteArray?> = _pendingSnapshotBytes.asStateFlow()

    private val _pendingBcfCameraState = MutableStateFlow<BcfCameraState?>(null)
    val pendingBcfCameraState: StateFlow<BcfCameraState?> = _pendingBcfCameraState.asStateFlow()

    // ── Element mutations ─────────────────────────────────────────────────────

    private val _deletedElementIds = MutableStateFlow<List<Long>>(emptyList())
    val deletedElementIds: StateFlow<List<Long>> = _deletedElementIds.asStateFlow()

    private val _movedElements = MutableStateFlow<Map<Long, Triple<Float, Float, Float>>>(emptyMap())
    val movedElements: StateFlow<Map<Long, Triple<Float, Float, Float>>> = _movedElements.asStateFlow()

    // ── Room data ─────────────────────────────────────────────────────────────

    private var loadedGlbBytes: ByteArray? = null
    var loadedIfcBytes: ByteArray? = null
        private set

    private val _loadedIfcModel = MutableStateFlow<IfcModel?>(null)
    val loadedIfcModel: StateFlow<IfcModel?> = _loadedIfcModel.asStateFlow()

    private val _glbBytes = MutableStateFlow<ByteArray?>(null)
    val glbBytes: StateFlow<ByteArray?> = _glbBytes.asStateFlow()

    // ── Fixtures ──────────────────────────────────────────────────────────────

    private val _placedFixtures = MutableStateFlow<List<PlacedFixture>>(emptyList())
    val placedFixtures: StateFlow<List<PlacedFixture>> = _placedFixtures.asStateFlow()

    private val _placedWalls = MutableStateFlow<List<PlacedWall>>(emptyList())
    val placedWalls: StateFlow<List<PlacedWall>> = _placedWalls.asStateFlow()

    private val _currentFixtureName = MutableStateFlow<String?>(null)
    val currentFixtureName: StateFlow<String?> = _currentFixtureName.asStateFlow()

    private val _currentFixtureAsset = MutableStateFlow<String?>(null)
    val currentFixtureAsset: StateFlow<String?> = _currentFixtureAsset.asStateFlow()

    // ── Room anchor ───────────────────────────────────────────────────────────

    private val _roomAnchor = MutableStateFlow<Triple<Float, Float, Float>?>(null)
    val roomAnchor: StateFlow<Triple<Float, Float, Float>?> = _roomAnchor.asStateFlow()

    // ── Vertical offset (height adjustment before placement) ──────────────────

    private val _roomYOffset = MutableStateFlow(0f)
    val roomYOffset: StateFlow<Float> = _roomYOffset.asStateFlow()

    // ── Model transparency (adjustable after placement) ───────────────────────

    private val _modelAlpha = MutableStateFlow(0.5f)
    val modelAlpha: StateFlow<Float> = _modelAlpha.asStateFlow()

    // ── Error state ───────────────────────────────────────────────────────────

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    // ── Loading state ─────────────────────────────────────────────────────────

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    // ── Live wall preview ─────────────────────────────────────────────────────

    private val _wallStartPoint = MutableStateFlow<AlignmentPoint?>(null)
    val wallStartPoint: StateFlow<AlignmentPoint?> = _wallStartPoint.asStateFlow()

    private val _wallEndPoint = MutableStateFlow<AlignmentPoint?>(null)
    val wallEndPoint: StateFlow<AlignmentPoint?> = _wallEndPoint.asStateFlow()

    // =========================================================================
    // State machine transitions
    // =========================================================================

    // ── Floor plan ────────────────────────────────────────────────────────────

    fun loadIfcForFloorPlan(context: Context) {
        viewModelScope.launch(Dispatchers.IO) {
            if (_loadedIfcModel.value != null) return@launch  // already loaded
            _isLoading.value = true
            try {
                val bytes = context.assets.open("BaseRoom-v2.ifc").readBytes()
                loadedIfcBytes = bytes
                _loadedIfcModel.value = IfcBridge.parseIfc(bytes)
            } catch (e: Exception) {
                _errorMessage.value = "Failed to load floor plan: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun addFloorPlanPoint(localX: Float, localZ: Float) {
        val current = _floorPlanPoints.value
        if (current.size >= 2) {
            // Replace first point with new tap (cycle through)
            _floorPlanPoints.value = listOf(FloorPlanPoint(localX, localZ))
        } else {
            _floorPlanPoints.value = current + FloorPlanPoint(localX, localZ)
        }
    }

    fun clearFloorPlanPoints() {
        _floorPlanPoints.value = emptyList()
    }

    fun startAr() {
        _arState.value = ARState.COACHING
    }

    // ── Alignment ─────────────────────────────────────────────────────────────

    fun advanceFromCoaching() {
        if (_arState.value == ARState.COACHING) {
            _arState.value = ARState.ALIGNING
            _alignmentPoints.value = emptyList()
        }
    }

    fun setGlbBytes(bytes: ByteArray) {
        _glbBytes.value = bytes
    }

    fun setArState(state: ARState) {
        _arState.value = state
    }

    fun computeRoomTransformFromPoints(
        fp1: FloorPlanPoint, fp2: FloorPlanPoint,
        ar1: AlignmentPoint, ar2: AlignmentPoint
    ) {
        val angleFp = Math.atan2((fp2.localZ - fp1.localZ).toDouble(), (fp2.localX - fp1.localX).toDouble())
        val angleAr = Math.atan2((ar2.z - ar1.z).toDouble(), (ar2.x - ar1.x).toDouble())
        val delta = angleAr - angleFp
        val cosD = Math.cos(delta).toFloat()
        val sinD = Math.sin(delta).toFloat()

        val fpDx = fp2.localX - fp1.localX
        val fpDz = fp2.localZ - fp1.localZ
        val arDx = ar2.x - ar1.x
        val arDz = ar2.z - ar1.z
        val fpDist = Math.sqrt((fpDx * fpDx + fpDz * fpDz).toDouble()).toFloat()
        val arDist = Math.sqrt((arDx * arDx + arDz * arDz).toDouble()).toFloat()
        val scale = if (fpDist > 0.01f) (arDist / fpDist) else 1.0f

        val rotFp1x = (fp1.localX * cosD - fp1.localZ * sinD) * scale
        val rotFp1z = (fp1.localX * sinD + fp1.localZ * cosD) * scale

        _roomAnchor.value = Triple(ar1.x - rotFp1x, ar1.y, ar1.z - rotFp1z)
        _roomRotationY.value = Math.toDegrees(delta).toFloat()
        _roomScale.value = scale.coerceIn(0.3f, 3.0f)
    }

    fun addAlignmentPoint(x: Float, y: Float, z: Float) {
        if (_arState.value != ARState.ALIGNING) return
        val current = _alignmentPoints.value.toMutableList()
        if (current.size >= 2) return
        current.add(AlignmentPoint(x, y, z))
        _alignmentPoints.value = current
    }

    fun advanceFromAligning() {
        if (_arState.value != ARState.ALIGNING) return
        if (_alignmentPoints.value.size < 2) return

        val p1 = _alignmentPoints.value[0]
        val p2 = _alignmentPoints.value[1]
        val dx = p2.x - p1.x
        val dz = p2.z - p1.z
        _gridRotation.value = Math.toDegrees(Math.atan2(dz.toDouble(), dx.toDouble())).toFloat()

        val fps = _floorPlanPoints.value
        if (fps.size >= 2) {
            computeRoomTransformFromPoints(fps[0], fps[1], p1, p2)
            _arState.value = ARState.LOADING   // skip CALIBRATING
        } else {
            _arState.value = ARState.CALIBRATING  // fallback: manual calibration
        }
    }

    fun setGridRotation(angle: Float) {
        _gridRotation.value = angle
    }

    fun confirmCalibration() {
        if (_arState.value == ARState.CALIBRATING) {
            _arState.value = ARState.LOADING
        }
    }

    fun loadRoom(context: Context) {
        viewModelScope.launch {
            _isLoading.value = true
            _arState.value = ARState.LOADING
            try {
                val ifcBytes = withContext(Dispatchers.IO) {
                    context.assets.open("BaseRoom-v2.ifc").readBytes()
                }
                loadedIfcBytes = ifcBytes

                val glbBytes = withContext(Dispatchers.IO) {
                    IfcBridge.parseAndExportGlb(ifcBytes)
                }
                loadedGlbBytes = glbBytes
                _glbBytes.value = glbBytes

                val model = _loadedIfcModel.value ?: withContext(Dispatchers.IO) {
                    IfcBridge.parseIfc(ifcBytes)
                }
                _loadedIfcModel.value = model

                _arState.value = ARState.PREVIEWING
            } catch (e: Exception) {
                android.util.Log.e("ARViewModel", "loadRoom failed", e)
                _errorMessage.value = "Failed to load room: ${e::class.simpleName}: ${e.message}"
                _arState.value = ARState.CALIBRATING
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun setRoomScale(scale: Float) {
        _roomScale.value = scale.coerceIn(0.5f, 2.0f)
    }

    fun setRoomRotationY(rotY: Float) {
        _roomRotationY.value = rotY
    }

    fun setRoomYOffset(offset: Float) {
        _roomYOffset.value = offset.coerceIn(-2f, 3f)
    }

    fun setModelAlpha(alpha: Float) {
        _modelAlpha.value = alpha.coerceIn(0f, 1f)
    }

    fun confirmPlacement(anchorX: Float, anchorY: Float, anchorZ: Float) {
        if (_arState.value == ARState.PREVIEWING) {
            _roomAnchor.value = Triple(anchorX, anchorY, anchorZ)
            _arState.value = ARState.ROOM_PLACED
            _showFixturePicker.value = true
        }
    }

    // ── Wall drawing ──────────────────────────────────────────────────────────

    fun startWall() {
        _wallStartPoint.value = null
        _wallEndPoint.value = null
        _arState.value = ARState.WALL_START
        _showFixturePicker.value = false
    }

    fun setWallStartPoint(x: Float, y: Float, z: Float) {
        if (_arState.value == ARState.WALL_START) {
            _wallStartPoint.value = AlignmentPoint(x, y, z)
            _arState.value = ARState.WALL_END
        }
    }

    fun updateWallEndPoint(x: Float, y: Float, z: Float) {
        if (_arState.value == ARState.WALL_END) {
            _wallEndPoint.value = AlignmentPoint(x, y, z)
        }
    }

    fun setWallHeight(height: Float) {
        _wallHeight.value = height.coerceIn(0.5f, 5.0f)
    }

    fun setWallThickness(thickness: Float) {
        _wallThickness.value = thickness.coerceIn(0.05f, 0.5f)
    }

    fun confirmWall(
        positions: List<Float>,
        normals: List<Float>,
        indices: List<Int>,
        relX: Float,
        relY: Float,
        relZ: Float,
        height: Float,
        thickness: Float,
        length: Float
    ) {
        val wall = PlacedWall(positions, normals, indices, relX, relY, relZ, height, thickness, length)
        _placedWalls.value = _placedWalls.value + wall
        _wallStartPoint.value = null
        _wallEndPoint.value = null
        _arState.value = ARState.ROOM_PLACED
        _showFixturePicker.value = true
    }

    fun cancelWall() {
        _wallStartPoint.value = null
        _wallEndPoint.value = null
        _arState.value = ARState.ROOM_PLACED
        _showFixturePicker.value = true
    }

    // ── Fixture placement ─────────────────────────────────────────────────────

    fun selectFixture(name: String, ifcAsset: String) {
        if (name == "Wall") {
            startWall()
            return
        }
        _currentFixtureName.value = name
        _currentFixtureAsset.value = ifcAsset
        _arState.value = ARState.FIXTURE_PREVIEWING
        _showFixturePicker.value = false
    }

    fun placeFixture(relX: Float, relY: Float, relZ: Float, rotY: Float) {
        val name = _currentFixtureName.value ?: return
        val asset = _currentFixtureAsset.value ?: return
        val fixture = PlacedFixture(name, asset, relX, relY, relZ, rotY)
        _placedFixtures.value = _placedFixtures.value + fixture
        _currentFixtureName.value = null
        _currentFixtureAsset.value = null
        _arState.value = ARState.ROOM_PLACED
        _showFixturePicker.value = true
    }

    fun cancelFixturePlacement() {
        _currentFixtureName.value = null
        _currentFixtureAsset.value = null
        _arState.value = ARState.ROOM_PLACED
        _showFixturePicker.value = true
    }

    // ── Element selection and actions ─────────────────────────────────────────

    fun selectElement(element: SelectedElement) {
        _selectedElement.value = element
    }

    fun clearSelection() {
        _selectedElement.value = null
    }

    fun showDetails() {
        _showDetailsSheet.value = true
    }

    fun dismissDetails() {
        _showDetailsSheet.value = false
    }

    fun showBcfForm() {
        _showBcfForm.value = true
    }

    fun dismissBcfForm() {
        _showBcfForm.value = false
        _pendingSnapshotBytes.value = null
        _pendingBcfCameraState.value = null
    }

    fun storePendingBcfContext(snapshot: ByteArray?, cam: BcfCameraState?) {
        _pendingSnapshotBytes.value = snapshot
        _pendingBcfCameraState.value = cam
        _showBcfForm.value = true
    }

    fun deleteElement(id: Long) {
        _deletedElementIds.value = _deletedElementIds.value + id
        _selectedElement.value = null
    }

    fun startMoveElement(element: SelectedElement) {
        _selectedElement.value = element
        _arState.value = ARState.ELEMENT_MOVING
    }

    fun confirmElementMove(offsetX: Float, offsetY: Float, offsetZ: Float) {
        val element = _selectedElement.value ?: return
        val current = _movedElements.value.toMutableMap()
        current[element.ifcId] = Triple(offsetX, offsetY, offsetZ)
        _movedElements.value = current
        _selectedElement.value = null
        _arState.value = ARState.ROOM_PLACED
    }

    fun cancelElementMove() {
        _arState.value = ARState.ROOM_PLACED
    }

    // ── BCF ───────────────────────────────────────────────────────────────────

    fun addBcfIssue(issue: BcfIssue) {
        _bcfIssues.value = _bcfIssues.value + issue
        _showBcfForm.value = false
    }

    // ── Fixture picker ────────────────────────────────────────────────────────

    fun toggleFixturePicker() {
        _showFixturePicker.value = !_showFixturePicker.value
    }

    fun dismissFixturePicker() {
        _showFixturePicker.value = false
    }

    // ── Export ────────────────────────────────────────────────────────────────

    fun exportIfc(context: Context): String {
        val ifcBytes = loadedIfcBytes ?: throw IllegalStateException("No IFC loaded")

        val fixtures = _placedFixtures.value.map { fixture ->
            val assetBytes = context.assets.open(fixture.ifcAsset).readBytes()
            uniffi.ifc_ar_core.FixtureExportInput(assetBytes, fixture.relX, fixture.relY, fixture.relZ, fixture.rotY)
        }

        val walls = _placedWalls.value.map { wall ->
            uniffi.ifc_ar_core.WallExportInput(
                wall.positions, wall.normals, wall.indices.map { it.toUInt() },
                wall.relX, wall.relY, wall.relZ,
                wall.height, wall.thickness, wall.length
            )
        }

        val moved = _movedElements.value.map { (id, offset) ->
            uniffi.ifc_ar_core.ElementMoveInput(id.toULong(), offset.first, offset.second, offset.third)
        }

        return uniffi.ifc_ar_core.exportCombinedIfcWithWalls(
            ifcBytes, fixtures, walls, _deletedElementIds.value.map { it.toULong() }, moved
        )
    }

    fun exportBcf(context: Context): java.io.File {
        return BCFExporter.exportBcf(context, _bcfIssues.value)
    }

    fun findNearestElement(localX: Float, localZ: Float, threshold: Float = 1.0f): SelectedElement? {
        val model = _loadedIfcModel.value ?: return null
        var bestDist = Float.MAX_VALUE
        var bestElement: SelectedElement? = null

        for (elem in model.elements) {
            val positions = elem.geometry?.positions ?: continue
            if (positions.size < 3) continue

            // geometry.positions are already in centered Y-up GLB space (same transform as rendered GLB)
            val count = positions.size / 3
            var sumX = 0f
            var sumZ = 0f
            for (i in 0 until count) {
                sumX += positions[i * 3]
                sumZ += positions[i * 3 + 2]
            }
            val cx = sumX / count
            val cz = sumZ / count

            val dx = cx - localX
            val dz = cz - localZ
            val dist = kotlin.math.sqrt((dx * dx + dz * dz).toDouble()).toFloat()

            if (dist < threshold && dist < bestDist) {
                bestDist = dist
                bestElement = SelectedElement(
                    entityId = elem.id.toString(),
                    ifcId = elem.id.toLong(),
                    name = elem.name ?: "",
                    ifcType = elem.ifcType,
                    globalId = elem.globalId,
                    properties = elem.properties,
                    quantities = elem.quantities
                )
            }
        }
        return bestElement
    }

    fun clearError() {
        _errorMessage.value = null
    }
}
