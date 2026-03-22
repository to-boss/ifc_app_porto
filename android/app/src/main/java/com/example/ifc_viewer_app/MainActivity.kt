package com.example.ifc_viewer_app

import android.os.Bundle
import android.view.MotionEvent
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.ar.core.Anchor
import com.google.ar.core.Config
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Float4
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.node.CubeNode
import io.github.sceneview.node.SphereNode

class MainActivity : AppCompatActivity() {

    private lateinit var sceneView: ARSceneView
    private lateinit var instructionsText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        instructionsText = findViewById(R.id.instructions_text)
        sceneView = findViewById(R.id.scene_view)

        // Show detected planes as a grid overlay
        sceneView.planeRenderer.isEnabled = true

        // Configure the ARCore session
        sceneView.configureSession { session, config ->
            config.depthMode = when {
                session.isDepthModeSupported(Config.DepthMode.AUTOMATIC) ->
                    Config.DepthMode.AUTOMATIC
                else -> Config.DepthMode.DISABLED
            }
            config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
            config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
        }

        // Tap on a detected plane to place the 3D model
        sceneView.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                val hitResult = sceneView.hitTestAR(event.x, event.y)
                if (hitResult != null) {
                    placeModel(hitResult.createAnchor())
                }
            }
            // Return false so SceneView's own gesture handling still works
            false
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
