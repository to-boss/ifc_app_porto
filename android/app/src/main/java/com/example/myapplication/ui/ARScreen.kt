package com.example.myapplication.ui

import android.content.Context
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
import java.nio.ByteBuffer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.myapplication.ar.ARState
import com.example.myapplication.ar.ARViewModel
import com.example.myapplication.ar.SelectedElement
import com.google.ar.core.Config
import com.google.ar.core.HitResult
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.CoroutineScope
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

    // Track ARSceneView reference
    var arSceneViewRef by remember { mutableStateOf<ARSceneView?>(null) }
    // Room model node
    var roomModelNode by remember { mutableStateOf<ModelNode?>(null) }
    // Ghost fixture node
    var ghostFixtureNode by remember { mutableStateOf<ModelNode?>(null) }
    // Room anchor node
    var roomAnchorNode by remember { mutableStateOf<AnchorNode?>(null) }

    // Show error messages via snackbar
    LaunchedEffect(errorMessage) {
        errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
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
                    val modelInstance = sceneView.modelLoader.createModelInstance(
                        ByteBuffer.wrap(bytes)
                    )
                    val node = ModelNode(
                        modelInstance = modelInstance,
                        scaleToUnits = roomScale
                    )
                    node.isVisible = true
                    roomModelNode?.let { sceneView.removeChildNode(it) }
                    roomModelNode = node
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

                    // Store latest frame for touch listener access
                    var latestFrame: com.google.ar.core.Frame? = null

                    // Configure plane detection
                    configureSession { session, config ->
                        config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                        config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                        config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    }

                    // Frame callback for ghost positioning
                    onSessionUpdated = handler@{ session, frame ->
                        latestFrame = frame
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
                                // Move ghost room to hit plane in front of camera
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
                                            pose.translation[1],
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
                        val frame = latestFrame ?: return@setOnTouchListener false
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
                                    viewModel.confirmPlacement(t[0], t[1], t[2])

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

        // ── Loading indicator ─────────────────────────────────────────────────
        if (isLoading || arState == ARState.LOADING) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center),
                color = Color.White
            )
        }

        // ── Guide card ────────────────────────────────────────────────────────
        if (arState != ARState.ROOM_PLACED || selectedElement == null) {
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
            // Scale slider – left edge, vertical
            VerticalSlider(
                value = roomScale,
                onValueChange = { viewModel.setRoomScale(it) },
                valueRange = 0.5f..2.0f,
                label = "Scale",
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = 8.dp)
            )
            // Rotation slider – horizontal, bottom
            HorizontalSliderBar(
                value = roomRotationY,
                onValueChange = { viewModel.setRoomRotationY(it) },
                valueRange = -180f..180f,
                label = "Rotation: ${"%.0f".format(roomRotationY)}°",
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 80.dp, start = 60.dp, end = 60.dp)
            )
            // Place button
            Button(
                onClick = {
                    val node = roomModelNode
                    if (node != null) {
                        val pos = node.worldPosition
                        viewModel.confirmPlacement(pos.x, pos.y, pos.z)
                    }
                },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 24.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1976D2))
            ) {
                Text("Place Room", color = Color.White, fontWeight = FontWeight.Bold)
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
                            val bcfPath = withContext(Dispatchers.IO) { viewModel.exportBcf(context) }
                            snackbarHostState.showSnackbar("Exported: export.ifc + ${bcfPath.substringAfterLast('/')}")
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
        BcfFormSheet(
            viewModel = viewModel,
            elementGlobalId = elem?.globalId
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
