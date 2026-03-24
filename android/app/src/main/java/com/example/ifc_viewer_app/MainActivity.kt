package com.example.ifc_viewer_app

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.node.CubeNode
import io.github.sceneview.node.SphereNode

class MainActivity : AppCompatActivity() {

    private lateinit var sceneView: ARSceneView
    private lateinit var instructionsText: TextView
    private var modelPlaced = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        instructionsText = findViewById(R.id.instructions_text)
        sceneView = findViewById(R.id.scene_view)

        sceneView.planeRenderer.isEnabled = true

        sceneView.configureSession { session, config ->
            config.depthMode = when {
                session.isDepthModeSupported(Config.DepthMode.AUTOMATIC) ->
                    Config.DepthMode.AUTOMATIC
                else -> Config.DepthMode.DISABLED
            }
            config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
            config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
        }

        // Automatically place the model on the first detected horizontal plane
        sceneView.onSessionUpdated = { session: Session, _: Frame ->
            if (!modelPlaced) {
                val plane = session.getAllTrackables(Plane::class.java)
                    .firstOrNull { p ->
                        p.trackingState == TrackingState.TRACKING &&
                        p.type == Plane.Type.HORIZONTAL_UPWARD_FACING
                    }
                if (plane != null) {
                    modelPlaced = true
                    val anchor = plane.createAnchor(plane.centerPose)
                    runOnUiThread { placeModel(anchor) }
                }
            }
        }
    }

    /**
     * Places an IFC-inspired test structure at the given AR anchor:
     *  - Grey flat slab  → floor/base element  (30cm × 5cm × 30cm)
     *  - Blue column      → structural element  (8cm × 25cm × 8cm)
     *  - Orange sphere    → top reference marker (4cm radius)
     */
    private fun placeModel(anchor: Anchor) {
        val slab = CubeNode(
            engine = sceneView.engine,
            size = Float3(0.30f, 0.05f, 0.30f),
            center = Float3(0f),
            materialInstance = sceneView.materialLoader.createColorInstance(
                color = Float4(0.55f, 0.55f, 0.55f, 1.0f)
            )
        ).apply { position = Float3(0f, 0.025f, 0f) }

        val column = CubeNode(
            engine = sceneView.engine,
            size = Float3(0.08f, 0.25f, 0.08f),
            center = Float3(0f),
            materialInstance = sceneView.materialLoader.createColorInstance(
                color = Float4(0.20f, 0.55f, 1.0f, 1.0f)
            )
        ).apply { position = Float3(0f, 0.175f, 0f) }

        val marker = SphereNode(
            engine = sceneView.engine,
            radius = 0.04f,
            center = Float3(0f),
            stacks = 24,
            slices = 24,
            materialInstance = sceneView.materialLoader.createColorInstance(
                color = Float4(1.0f, 0.50f, 0.0f, 1.0f)
            )
        ).apply { position = Float3(0f, 0.325f, 0f) }

        val anchorNode = AnchorNode(
            engine = sceneView.engine,
            anchor = anchor
        ).apply {
            addChildNode(slab)
            addChildNode(column)
            addChildNode(marker)
        }

        sceneView.addChildNode(anchorNode)
        instructionsText.text = "Model placed! Walk around to inspect it."
    }
}
