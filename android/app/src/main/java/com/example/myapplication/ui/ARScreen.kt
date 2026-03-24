package com.example.myapplication.ui

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.FileProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.myapplication.ar.ARState
import com.example.myapplication.ar.ARViewModel
import com.example.myapplication.ar.BcfCameraState
import com.example.myapplication.ar.SelectedElement
import com.google.ar.core.Camera
import com.google.ar.core.Config
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ARScreen(viewModel: ARViewModel = viewModel()) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    val arState by viewModel.arState.collectAsState()
    val alignmentPoints by viewModel.alignmentPoints.collectAsState()
    val gridRotation by viewModel.gridRotation.collectAsState()
    val roomScale by viewModel.roomScale.collectAsState()
    val roomRotationY by viewModel.roomRotationY.collectAsState()
    val wallHeight by viewModel.wallHeight.collectAsState()
    val wallThickness by viewModel.wallThickness.collectAsState()
    val selectedElement by viewModel.selectedElement.collectAsState()
    val showFixturePicker by viewModel.showFixturePicker.collectAsState()
    val showDetailsSheet by viewModel.showDetailsSheet.collectAsState()
    val showBcfForm by viewModel.showBcfForm.collectAsState()
    val glbBytes by viewModel.glbBytes.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val errorMessage by viewModel.errorMessage.collectAsState()
    val pendingSnapshotBytes by viewModel.pendingSnapshotBytes.collectAsState()
    val pendingBcfCameraState by viewModel.pendingBcfCameraState.collectAsState()
    val floorPlanPoints by viewModel.floorPlanPoints.collectAsState()
    val loadedIfcModel by viewModel.loadedIfcModel.collectAsState()
    val roomAnchor by viewModel.roomAnchor.collectAsState()
    val roomYOffset by viewModel.roomYOffset.collectAsState()
    val modelAlpha by viewModel.modelAlpha.collectAsState()

    // Track ARSceneView reference
    var arSceneViewRef by remember { mutableStateOf<ARSceneView?>(null) }
    // Room model node
    var roomModelNode by remember { mutableStateOf<ModelNode?>(null) }
    // Ghost fixture node
    var ghostFixtureNode by remember { mutableStateOf<ModelNode?>(null) }
    // Room anchor node
    var roomAnchorNode by remember { mutableStateOf<AnchorNode?>(null) }
    // Holder for model node so LaunchedEffects can update materials without capturing stale state
    val roomModelNodeHolder = remember { object { var node: ModelNode? = null } }
    // Latest ARCore frame holder (plain object to avoid recompose on every frame)
    val latestFrameHolder = remember { object { var frame: com.google.ar.core.Frame? = null } }
    // Main thread handler for PixelCopy
    val mainHandler = remember { Handler(Looper.getMainLooper()) }

    // Preload IFC for floor plan immediately on composition
    LaunchedEffect(Unit) {
        viewModel.loadIfcForFloorPlan(context)
    }

    // Show error messages via snackbar
    LaunchedEffect(errorMessage) {
        errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    // Update material transparency at runtime when modelAlpha changes
    LaunchedEffect(modelAlpha) {
        withContext(Dispatchers.Main) {
            roomModelNodeHolder.node?.modelInstance?.materialInstances?.forEach { mat ->
                mat.setParameter("baseColorFactor", 1f, 1f, 1f, modelAlpha)
            }
        }
    }

    // Load room when transitioning to LOADING state
    LaunchedEffect(arState) {
        if (arState == ARState.LOADING) {
            viewModel.loadRoom(context)
        }
    }

    // When GLB bytes are ready and in PREVIEWING state, load the model
    LaunchedEffect(glbBytes, arState) {
        val bytes = glbBytes
        val sceneView = arSceneViewRef
        if (bytes != null && arState == ARState.PREVIEWING && sceneView != null) {
            withContext(Dispatchers.Main) {
                try {
                    // Apply 50% transparency by rewriting GLB material JSON chunk
                    val transparentBytes = withContext(Dispatchers.Default) {
                        makeGlbTransparent(bytes, alpha = 0.5f)
                    }
                    val modelInstance = sceneView.modelLoader.createModelInstance(
                        ByteBuffer.wrap(transparentBytes)
                    )
                    val node = ModelNode(
                        modelInstance = modelInstance,
                        scaleToUnits = null
                    )
                    node.isVisible = true
                    node.onSingleTapConfirmed = { event ->
                        val frame = latestFrameHolder.frame
                        val anchor = viewModel.roomAnchor.value
                        if (frame != null && anchor != null && viewModel.arState.value == ARState.ROOM_PLACED) {
                            val tapHits = frame.hitTest(event.x, event.y)
                            val tapHit = tapHits.firstOrNull { it.trackable is com.google.ar.core.Plane }
                            if (tapHit != null) {
                                val t = tapHit.hitPose.translation
                                val local = worldToRoomLocal(
                                    t[0], t[1], t[2], anchor,
                                    viewModel.roomScale.value,
                                    viewModel.roomRotationY.value
                                )
                                val elem = viewModel.findNearestElement(local.first, local.third)
                                if (elem != null) viewModel.selectElement(elem)
                                else viewModel.clearSelection()
                            }
                            true
                        } else false
                    }
                    roomModelNode?.let { sceneView.removeChildNode(it) }
                    roomModelNode = node
                    roomModelNodeHolder.node = node
                    sceneView.addChildNode(node)
                } catch (e: Exception) {
                    snackbarHostState.showSnackbar("Failed to load 3D model: ${e.message}")
                }
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // ── AR View ───────────────────────────────────────────────────────────
        AndroidView(
            factory = { ctx ->
                ARSceneView(ctx).apply {
                    arSceneViewRef = this

                    // Configure plane detection
                    configureSession { session, config ->
                        config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                        config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                        config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    }

                    // Frame callback for ghost positioning
                    onSessionUpdated = handler@{ session, frame ->
                        latestFrameHolder.frame = frame
                        val currentState = viewModel.arState.value
                        val camera = frame.camera
                        if (camera.trackingState != TrackingState.TRACKING) return@handler

                        val cameraTranslation = camera.pose.translation
                        val cameraDirection = floatArrayOf(
                            -camera.pose.zAxis[0],
                            -camera.pose.zAxis[1],
                            -camera.pose.zAxis[2]
                        )

                        when (currentState) {
                            ARState.PREVIEWING -> {
                                val precomputedAnchor = viewModel.roomAnchor.value
                                val yOff = viewModel.roomYOffset.value
                                if (precomputedAnchor != null) {
                                    // 2-point alignment computed a position — keep model there
                                    roomModelNode?.apply {
                                        worldPosition = io.github.sceneview.math.Position(
                                            precomputedAnchor.first,
                                            precomputedAnchor.second + yOff,
                                            precomputedAnchor.third
                                        )
                                        worldRotation = io.github.sceneview.math.Rotation(
                                            0f, viewModel.roomRotationY.value, 0f
                                        )
                                        scale = io.github.sceneview.math.Scale(
                                            viewModel.roomScale.value,
                                            viewModel.roomScale.value,
                                            viewModel.roomScale.value
                                        )
                                    }
                                } else {
                                    // No anchor yet — ghost follows camera center
                                    val centerX = width / 2f
                                    val centerY = height / 2f
                                    val hits = frame.hitTest(centerX, centerY)
                                    val hit = hits.firstOrNull {
                                        it.trackable is com.google.ar.core.Plane &&
                                                (it.trackable as com.google.ar.core.Plane).type ==
                                                com.google.ar.core.Plane.Type.HORIZONTAL_UPWARD_FACING
                                    }
                                    hit?.let { h ->
                                        val pose = h.hitPose
                                        roomModelNode?.apply {
                                            worldPosition = io.github.sceneview.math.Position(
                                                pose.translation[0],
                                                pose.translation[1] + yOff,
                                                pose.translation[2]
                                            )
                                            worldRotation = io.github.sceneview.math.Rotation(
                                                0f, viewModel.roomRotationY.value, 0f
                                            )
                                            scale = io.github.sceneview.math.Scale(
                                                viewModel.roomScale.value,
                                                viewModel.roomScale.value,
                                                viewModel.roomScale.value
                                            )
                                        }
                                    }
                                }
                            }

                            ARState.FIXTURE_PREVIEWING -> {
                                val centerX = width / 2f
                                val centerY = height / 2f
                                val hits = frame.hitTest(centerX, centerY)
                                val hit = hits.firstOrNull {
                                    it.trackable is com.google.ar.core.Plane &&
                                            (it.trackable as com.google.ar.core.Plane).type ==
                                            com.google.ar.core.Plane.Type.HORIZONTAL_UPWARD_FACING
                                }
                                hit?.let { h ->
                                    val pose = h.hitPose
                                    ghostFixtureNode?.apply {
                                        worldPosition = io.github.sceneview.math.Position(
                                            pose.translation[0],
                                            pose.translation[1],
                                            pose.translation[2]
                                        )
                                    }
                                }
                            }

                            ARState.WALL_END -> {
                                // Live wall end point update
                                val centerX = width / 2f
                                val centerY = height / 2f
                                val hits = frame.hitTest(centerX, centerY)
                                val hit = hits.firstOrNull {
                                    it.trackable is com.google.ar.core.Plane
                                }
                                hit?.let { h ->
                                    val pose = h.hitPose
                                    viewModel.updateWallEndPoint(
                                        pose.translation[0],
                                        pose.translation[1],
                                        pose.translation[2]
                                    )
                                }
                            }

                            else -> {}
                        }
                    }

                    // Touch listener for hit testing
                    setOnTouchListener { _, event ->
                        if (event.action != MotionEvent.ACTION_UP) return@setOnTouchListener false
                        val currentState = viewModel.arState.value
                        val frame = latestFrameHolder.frame ?: return@setOnTouchListener false
                        val hits = frame.hitTest(event.x, event.y)

                        when (currentState) {
                            ARState.COACHING -> {
                                viewModel.advanceFromCoaching()
                                true
                            }

                            ARState.ALIGNING -> {
                                val hit = hits.firstOrNull {
                                    it.trackable is com.google.ar.core.Plane
                                }
                                hit?.let { h ->
                                    val t = h.hitPose.translation
                                    viewModel.addAlignmentPoint(t[0], t[1], t[2])
                                    if (viewModel.alignmentPoints.value.size >= 2) {
                                        viewModel.advanceFromAligning()
                                    }
                                }
                                true
                            }

                            ARState.CALIBRATING -> {
                                viewModel.confirmCalibration()
                                true
                            }

                            ARState.PREVIEWING -> {
                                val hit = hits.firstOrNull {
                                    it.trackable is com.google.ar.core.Plane &&
                                            (it.trackable as com.google.ar.core.Plane).type ==
                                            com.google.ar.core.Plane.Type.HORIZONTAL_UPWARD_FACING
                                }
                                hit?.let { h ->
                                    val t = h.hitPose.translation
                                    viewModel.confirmPlacement(t[0], t[1] + viewModel.roomYOffset.value, t[2])

                                    // Anchor the room node
                                    val anchor = h.createAnchor()
                                    val anchorNode = AnchorNode(
                                        engine = engine,
                                        anchor = anchor
                                    )
                                    roomModelNode?.let { model ->
                                        removeChildNode(model)
                                        anchorNode.addChildNode(model)
                                    }
                                    roomAnchorNode?.let { removeChildNode(it) }
                                    addChildNode(anchorNode)
                                    roomAnchorNode = anchorNode
                                }
                                true
                            }

                            ARState.WALL_START -> {
                                val hit = hits.firstOrNull {
                                    it.trackable is com.google.ar.core.Plane
                                }
                                hit?.let { h ->
                                    val t = h.hitPose.translation
                                    viewModel.setWallStartPoint(t[0], t[1], t[2])
                                }
                                true
                            }

                            ARState.WALL_END -> {
                                val hit = hits.firstOrNull {
                                    it.trackable is com.google.ar.core.Plane
                                }
                                hit?.let { h ->
                                    val t = h.hitPose.translation
                                    val startPt = viewModel.wallStartPoint.value
                                    if (startPt != null) {
                                        coroutineScope.launch(Dispatchers.IO) {
                                            try {
                                                val element = com.example.myapplication.ffi.IfcBridge.createWallMesh(
                                                    startPt.x, startPt.z,
                                                    t[0], t[2],
                                                    viewModel.wallHeight.value,
                                                    viewModel.wallThickness.value
                                                )
                                                val mesh = element.geometry
                                                if (mesh != null) {
                                                    val dx = t[0] - startPt.x
                                                    val dz = t[2] - startPt.z
                                                    val length = Math.sqrt((dx * dx + dz * dz).toDouble()).toFloat()
                                                    viewModel.confirmWall(
                                                        mesh.positions, mesh.normals,
                                                        mesh.indices.map { it.toInt() },
                                                        startPt.x, startPt.y, startPt.z,
                                                        viewModel.wallHeight.value,
                                                        viewModel.wallThickness.value,
                                                        length
                                                    )
                                                }
                                            } catch (e: Exception) {
                                                withContext(Dispatchers.Main) {
                                                    snackbarHostState.showSnackbar("Wall creation failed: ${e.message}")
                                                }
                                                withContext(Dispatchers.Main) {
                                                    viewModel.cancelWall()
                                                }
                                            }
                                        }
                                    }
                                }
                                true
                            }

                            ARState.ROOM_PLACED -> {
                                // Return false so SceneView dispatches to node onSingleTapConfirmed.
                                // If tap missed all planes, clear any active selection.
                                val hit = hits.firstOrNull { it.trackable is com.google.ar.core.Plane }
                                if (hit == null) viewModel.clearSelection()
                                false
                            }

                            ARState.ELEMENT_MOVING -> {
                                val hit = hits.firstOrNull {
                                    it.trackable is com.google.ar.core.Plane
                                }
                                hit?.let { h ->
                                    val t = h.hitPose.translation
                                    val anchor = viewModel.roomAnchor.value
                                    val ox = if (anchor != null) t[0] - anchor.first else t[0]
                                    val oy = if (anchor != null) t[1] - anchor.second else t[1]
                                    val oz = if (anchor != null) t[2] - anchor.third else t[2]
                                    viewModel.confirmElementMove(ox, oy, oz)
                                }
                                true
                            }

                            ARState.FIXTURE_PREVIEWING -> {
                                val hit = hits.firstOrNull {
                                    it.trackable is com.google.ar.core.Plane &&
                                            (it.trackable as com.google.ar.core.Plane).type ==
                                            com.google.ar.core.Plane.Type.HORIZONTAL_UPWARD_FACING
                                }
                                hit?.let { h ->
                                    val t = h.hitPose.translation
                                    val anchor = viewModel.roomAnchor.value
                                    val rx = if (anchor != null) t[0] - anchor.first else t[0]
                                    val ry = if (anchor != null) t[1] - anchor.second else 0f
                                    val rz = if (anchor != null) t[2] - anchor.third else t[2]
                                    viewModel.placeFixture(rx, ry, rz, viewModel.roomRotationY.value)
                                }
                                true
                            }

                            else -> false
                        }
                    }
                }
            },
            modifier = Modifier.fillMaxSize(),
            update = { sceneView ->
                arSceneViewRef = sceneView
            }
        )

        // ── Floor Plan Overlay ────────────────────────────────────────────────
        if (arState == ARState.FLOOR_PLAN) {
            FloorPlanOverlay(
                ifcModel = loadedIfcModel,
                isLoading = isLoading,
                floorPlanPoints = floorPlanPoints,
                onTap = { x, z -> viewModel.addFloorPlanPoint(x, z) },
                onStartAr = { viewModel.startAr() },
                modifier = Modifier.fillMaxSize()
            )
        }

        // ── Loading indicator ─────────────────────────────────────────────────
        if ((isLoading || arState == ARState.LOADING) && arState != ARState.FLOOR_PLAN) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center),
                color = Color.White
            )
        }

        // ── Guide card ────────────────────────────────────────────────────────
        if (arState != ARState.FLOOR_PLAN && (arState != ARState.ROOM_PLACED || selectedElement == null)) {
            GuideCard(
                state = arState,
                alignmentPointCount = alignmentPoints.size,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 52.dp, start = 16.dp, end = 16.dp)
            )
        }

        // ── Calibration controls ──────────────────────────────────────────────
        if (arState == ARState.CALIBRATING) {
            CalibrationControls(
                rotation = gridRotation,
                onRotationChange = { viewModel.setGridRotation(it) },
                onConfirm = { viewModel.confirmCalibration() }
            )
        }

        // ── Preview controls ──────────────────────────────────────────────────
        if (arState == ARState.PREVIEWING) {
            androidx.compose.foundation.layout.Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth(0.8f)
                    .padding(bottom = 24.dp)
            ) {
                HorizontalSliderBar(
                    value = roomScale,
                    onValueChange = { viewModel.setRoomScale(it) },
                    valueRange = 0.5f..2.0f,
                    label = "Scale: ${"%.2f".format(roomScale)}×",
                    modifier = Modifier.fillMaxWidth()
                )
                HorizontalSliderBar(
                    value = roomYOffset,
                    onValueChange = { viewModel.setRoomYOffset(it) },
                    valueRange = -2f..3f,
                    label = "Height: ${"%.2f".format(roomYOffset)}m",
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    onClick = {
                        val sv = arSceneViewRef ?: return@Button
                        val sess = sv.session ?: return@Button
                        val preAnchor = viewModel.roomAnchor.value
                        val yOff = viewModel.roomYOffset.value
                        val wx: Float
                        val wy: Float
                        val wz: Float
                        if (preAnchor != null) {
                            wx = preAnchor.first
                            wy = preAnchor.second + yOff
                            wz = preAnchor.third
                        } else {
                            val pos = roomModelNode?.worldPosition ?: return@Button
                            wx = pos.x; wy = pos.y; wz = pos.z
                        }
                        viewModel.confirmPlacement(wx, wy, wz)
                        // Create a real ARCore anchor so the model stays locked in
                        // world space even when walking large distances.
                        val arCoreAnchor = sess.createAnchor(
                            com.google.ar.core.Pose.makeTranslation(wx, wy, wz)
                        )
                        val anchorNode = AnchorNode(engine = sv.engine, anchor = arCoreAnchor)
                        roomModelNode?.let { model ->
                            sv.removeChildNode(model)
                            model.position = io.github.sceneview.math.Position(0f, 0f, 0f)
                            anchorNode.addChildNode(model)
                        }
                        roomAnchorNode?.let { sv.removeChildNode(it) }
                        sv.addChildNode(anchorNode)
                        roomAnchorNode = anchorNode
                    },
                    modifier = Modifier.padding(top = 4.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1976D2))
                ) {
                    Text("Place Room", color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }

        // ── Wall adjust controls ──────────────────────────────────────────────
        if (arState == ARState.WALL_ADJUST || arState == ARState.WALL_END) {
            VerticalSlider(
                value = wallHeight,
                onValueChange = { viewModel.setWallHeight(it) },
                valueRange = 0.5f..5.0f,
                label = "H: ${"%.1f".format(wallHeight)}m",
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 8.dp)
            )
            HorizontalSliderBar(
                value = wallThickness,
                onValueChange = { viewModel.setWallThickness(it) },
                valueRange = 0.05f..0.5f,
                label = "T: ${"%.2f".format(wallThickness)}m",
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 80.dp, start = 60.dp, end = 60.dp)
            )
        }

        // ── Transparency slider (ROOM_PLACED) ─────────────────────────────────
        if (arState == ARState.ROOM_PLACED) {
            HorizontalSliderBar(
                value = modelAlpha,
                onValueChange = { viewModel.setModelAlpha(it) },
                valueRange = 0f..1f,
                label = "Opacity: ${"%.0f".format(modelAlpha * 100)}%",
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 80.dp, start = 60.dp, end = 60.dp)
            )
        }

        // ── Fixture picker sidebar ────────────────────────────────────────────
        if (arState == ARState.ROOM_PLACED && showFixturePicker) {
            FixturePicker(
                viewModel = viewModel,
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 0.dp)
            )
        }

        // ── Show fixture picker toggle button when ROOM_PLACED ────────────────
        if (arState == ARState.ROOM_PLACED && !showFixturePicker) {
            Button(
                onClick = { viewModel.toggleFixturePicker() },
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 8.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1976D2).copy(alpha = 0.85f))
            ) {
                Text("+", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
        }

        // ── Export button ─────────────────────────────────────────────────────
        if (arState == ARState.ROOM_PLACED) {
            Button(
                onClick = {
                    coroutineScope.launch {
                        try {
                            val ifcStr = withContext(Dispatchers.IO) { viewModel.exportIfc(context) }
                            saveTextToFile(context, ifcStr, "export.ifc")
                            val bcfFile = withContext(Dispatchers.IO) { viewModel.exportBcf(context) }
                            val uri = FileProvider.getUriForFile(
                                context,
                                "${context.packageName}.fileprovider",
                                bcfFile
                            )
                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "application/octet-stream"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                putExtra(Intent.EXTRA_SUBJECT, "BCF Issue Report")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(Intent.createChooser(shareIntent, "Share BCF file"))
                        } catch (e: Exception) {
                            snackbarHostState.showSnackbar("Export failed: ${e.message}")
                        }
                    }
                },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 52.dp, end = 16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32).copy(alpha = 0.90f))
            ) {
                Text("Export", color = Color.White, fontWeight = FontWeight.Bold)
            }
        }

        // ── Cancel wall / fixture buttons ─────────────────────────────────────
        if (arState == ARState.WALL_START || arState == ARState.WALL_END) {
            Button(
                onClick = { viewModel.cancelWall() },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(bottom = 24.dp, end = 16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFB71C1C).copy(alpha = 0.85f))
            ) {
                Text("Cancel Wall", color = Color.White)
            }
        }

        if (arState == ARState.FIXTURE_PREVIEWING) {
            Button(
                onClick = { viewModel.cancelFixturePlacement() },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(bottom = 24.dp, end = 16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFB71C1C).copy(alpha = 0.85f))
            ) {
                Text("Cancel", color = Color.White)
            }
        }

        // ── Element bubble menu ───────────────────────────────────────────────
        selectedElement?.let { elem ->
            if (arState == ARState.ROOM_PLACED) {
                ElementBubbleMenu(
                    element = elem,
                    viewModel = viewModel,
                    onReport = {
                        coroutineScope.launch {
                            val snapshot = arSceneViewRef?.let { captureArView(it, mainHandler) }
                            val cam = latestFrameHolder.frame?.camera?.let { buildCameraState(it) }
                            viewModel.storePendingBcfContext(snapshot, cam)
                        }
                    },
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(bottom = 120.dp)
                )
            }
        }

        // ── Snackbar ──────────────────────────────────────────────────────────
        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter)
        )
    }

    // ── Bottom sheets ─────────────────────────────────────────────────────────
    if (showDetailsSheet) {
        selectedElement?.let { elem ->
            ElementDetailsSheet(element = elem, viewModel = viewModel)
        }
    }

    if (showBcfForm) {
        val elem = selectedElement
        val cam = pendingBcfCameraState
        BcfFormSheet(
            viewModel = viewModel,
            elementGlobalId = elem?.globalId,
            cameraX = cam?.cameraX ?: 0f,
            cameraY = cam?.cameraY ?: 0f,
            cameraZ = cam?.cameraZ ?: 0f,
            dirX = cam?.dirX ?: 0f,
            dirY = cam?.dirY ?: 0f,
            dirZ = cam?.dirZ ?: -1f,
            fovDegrees = cam?.fovDegrees ?: 60f,
            snapshotBytes = pendingSnapshotBytes
        )
    }
}

@Composable
private fun BoxScope.VerticalSlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    valueRange: ClosedFloatingPointRange<Float>,
    label: String,
    modifier: Modifier
) {
    androidx.compose.foundation.layout.Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.5f), androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
            .padding(6.dp)
            .width(44.dp)
    ) {
        Text(text = label, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Medium)
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = valueRange,
            modifier = Modifier
                .graphicsLayer {
                    rotationZ = -90f
                }
                .width(140.dp),
            colors = SliderDefaults.colors(
                thumbColor = Color(0xFF1976D2),
                activeTrackColor = Color(0xFF1976D2)
            )
        )
    }
}

@Composable
private fun HorizontalSliderBar(
    value: Float,
    onValueChange: (Float) -> Unit,
    valueRange: ClosedFloatingPointRange<Float>,
    label: String,
    modifier: Modifier
) {
    androidx.compose.foundation.layout.Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.5f), androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .fillMaxWidth()
    ) {
        Text(text = label, color = Color.White, fontSize = 12.sp)
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = valueRange,
            colors = SliderDefaults.colors(
                thumbColor = Color(0xFF1976D2),
                activeTrackColor = Color(0xFF1976D2)
            )
        )
    }
}

@Composable
private fun BoxScope.CalibrationControls(
    rotation: Float,
    onRotationChange: (Float) -> Unit,
    onConfirm: () -> Unit
) {
    androidx.compose.foundation.layout.Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .align(Alignment.BottomCenter)
            .padding(bottom = 32.dp, start = 32.dp, end = 32.dp)
            .background(Color.Black.copy(alpha = 0.6f), androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
            .padding(16.dp)
            .fillMaxWidth()
    ) {
        Text(
            text = "Grid Rotation: ${"%.1f".format(rotation)}°",
            color = Color.White,
            fontSize = 14.sp
        )
        Slider(
            value = rotation,
            onValueChange = onRotationChange,
            valueRange = -180f..180f,
            colors = SliderDefaults.colors(
                thumbColor = Color(0xFF1976D2),
                activeTrackColor = Color(0xFF1976D2)
            )
        )
        Button(
            onClick = onConfirm,
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1976D2))
        ) {
            Text("Confirm Alignment", color = Color.White, fontWeight = FontWeight.Bold)
        }
    }
}

private fun saveTextToFile(context: Context, content: String, filename: String) {
    val file = java.io.File(context.cacheDir, filename)
    file.writeText(content)
}

private fun worldToRoomLocal(
    wx: Float, wy: Float, wz: Float,
    anchor: Triple<Float, Float, Float>,
    scale: Float,
    rotYDeg: Float
): Triple<Float, Float, Float> {
    val tx = (wx - anchor.first) / scale
    val tz = (wz - anchor.third) / scale
    val rad = Math.toRadians(-rotYDeg.toDouble())
    val cos = Math.cos(rad).toFloat()
    val sin = Math.sin(rad).toFloat()
    return Triple(cos * tx - sin * tz, (wy - anchor.second) / scale, sin * tx + cos * tz)
}

private fun buildCameraState(camera: Camera): BcfCameraState {
    val pos = camera.pose.translation
    val zAxis = camera.pose.zAxis
    val dirX = -zAxis[0]
    val dirY = -zAxis[1]
    val dirZ = -zAxis[2]
    val fov = try {
        val intrinsics = camera.textureIntrinsics
        val fy = intrinsics.focalLength[1]
        val halfH = intrinsics.imageDimensions[1] / 2f
        Math.toDegrees(2.0 * Math.atan((halfH / fy).toDouble())).toFloat()
    } catch (e: Exception) {
        60f
    }
    return BcfCameraState(pos[0], pos[1], pos[2], dirX, dirY, dirZ, fov)
}

/**
 * Rewrites the GLB JSON chunk so every material uses alphaMode=BLEND with the given alpha.
 * GLB layout: 12-byte header | 8-byte JSON chunk header + JSON data | BIN chunk
 */
private fun makeGlbTransparent(glbBytes: ByteArray, alpha: Float = 0.5f): ByteArray {
    try {
        if (glbBytes.size < 20) return glbBytes
        val buf = java.nio.ByteBuffer.wrap(glbBytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        if (buf.getInt(0) != 0x46546C67) return glbBytes  // not GLB magic

        val jsonChunkLength = buf.getInt(12)
        if (20 + jsonChunkLength > glbBytes.size) return glbBytes

        val jsonString = String(glbBytes, 20, jsonChunkLength, Charsets.UTF_8).trimEnd()
        val gltf = org.json.JSONObject(jsonString)
        val materials = gltf.optJSONArray("materials") ?: return glbBytes

        for (i in 0 until materials.length()) {
            val mat = materials.getJSONObject(i)
            mat.put("alphaMode", "BLEND")
            mat.remove("alphaCutoff")
            val pbr = mat.optJSONObject("pbrMetallicRoughness") ?: org.json.JSONObject().also {
                mat.put("pbrMetallicRoughness", it)
            }
            val bf = pbr.optJSONArray("baseColorFactor")
            val r = bf?.optDouble(0) ?: 1.0
            val g = bf?.optDouble(1) ?: 1.0
            val b = bf?.optDouble(2) ?: 1.0
            pbr.put("baseColorFactor", org.json.JSONArray(doubleArrayOf(r, g, b, alpha.toDouble())))
        }

        val newJson = gltf.toString().toByteArray(Charsets.UTF_8)
        val paddedLen = (newJson.size + 3) and 3.inv()
        val padding = paddedLen - newJson.size
        val binStart = 20 + jsonChunkLength
        val binBytes = if (binStart < glbBytes.size) glbBytes.copyOfRange(binStart, glbBytes.size) else ByteArray(0)
        val newTotal = 12 + 8 + paddedLen + binBytes.size

        val out = java.io.ByteArrayOutputStream(newTotal)
        out.write(glbBytes, 0, 8)                         // magic + version
        out.write(intToLittleEndian(newTotal))             // new total length
        out.write(intToLittleEndian(paddedLen))            // JSON chunk length
        out.write(intToLittleEndian(0x4E4F534A))           // "JSON" chunk type
        out.write(newJson)
        repeat(padding) { out.write(0x20) }               // pad with spaces
        if (binBytes.isNotEmpty()) out.write(binBytes)
        return out.toByteArray()
    } catch (e: Exception) {
        android.util.Log.w("GLB", "makeGlbTransparent failed: ${e.message}")
        return glbBytes
    }
}

private fun intToLittleEndian(v: Int) = byteArrayOf(
    (v and 0xFF).toByte(),
    ((v shr 8) and 0xFF).toByte(),
    ((v shr 16) and 0xFF).toByte(),
    ((v shr 24) and 0xFF).toByte()
)

private suspend fun captureArView(arSceneView: ARSceneView, handler: Handler): ByteArray? =
    withContext(Dispatchers.Main) {
        val w = arSceneView.width.coerceAtLeast(1)
        val h = arSceneView.height.coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val deferred = CompletableDeferred<Boolean>()
            android.view.PixelCopy.request(arSceneView, bitmap, { result ->
                deferred.complete(result == android.view.PixelCopy.SUCCESS)
            }, handler)
            if (!deferred.await()) return@withContext null
        } else {
            val canvas = Canvas(bitmap)
            arSceneView.draw(canvas)
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 70, stream)
        stream.toByteArray()
    }
