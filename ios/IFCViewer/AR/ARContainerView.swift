import SwiftUI
import ARKit
import RealityKit

struct ARContainerView: UIViewRepresentable {
    let arManager: ARSessionManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)

        arView.session.delegate = context.coordinator

        // Coaching overlay — guides user to scan the floor
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.delegate = context.coordinator
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
        ])

        // Tap gesture for placing columns
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        // Rotation gesture for manual grid alignment (during calibration)
        let rotationGesture = UIRotationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRotation(_:))
        )
        arView.addGestureRecognizer(rotationGesture)

        Task { @MainActor in
            arManager.arView = arView
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(arManager: arManager)
    }

    class Coordinator: NSObject, ARSessionDelegate, ARCoachingOverlayViewDelegate {
        let arManager: ARSessionManager

        init(arManager: ARSessionManager) {
            self.arManager = arManager
        }

        // MARK: - ARCoachingOverlayViewDelegate

        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            Task { @MainActor in
                arManager.coachingDidFinish()
            }
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                Task { @MainActor in
                    arManager.handlePlaneAnchorAdded(planeAnchor)
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let planeAnchor = anchor as? ARPlaneAnchor else { continue }
                Task { @MainActor in
                    arManager.handlePlaneAnchorUpdated(planeAnchor)
                }
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = recognizer.view as? ARView else { return }
            let point = recognizer.location(in: arView)
            Task { @MainActor in
                arManager.handleTap(at: point)
            }
        }

        @objc func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            let delta = Float(recognizer.rotation)
            recognizer.rotation = 0
            Task { @MainActor in
                arManager.adjustRotation(by: -delta)
            }
        }
    }
}
