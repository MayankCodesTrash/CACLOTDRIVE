import SwiftUI
import SceneKit

/// Lets the UI grab a picture of the current 3D view for sharing.
@MainActor
@Observable
final class Car3DController {
    @ObservationIgnored weak var view: SCNView?

    func snapshot() -> UIImage? { view?.snapshot() }
}

/// Interactive 3D car. Drag to orbit, pinch to zoom.
struct CarSceneView: UIViewRepresentable {
    let spec: CarSpec
    var interactive = true
    var spinning = true
    var controller: Car3DController?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = interactive
        view.isUserInteractionEnabled = interactive
        view.isAccessibilityElement = true
        view.accessibilityLabel = "3D model of your car. Drag to rotate."
        controller?.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.signature != spec.signature {
            context.coordinator.signature = spec.signature
            view.scene = CarSceneBuilder.makeScene(for: spec)
        }
        view.allowsCameraControl = interactive
        controller?.view = view
        setSpin(spinning, in: view)
    }

    private func setSpin(_ on: Bool, in view: SCNView) {
        guard let car = view.scene?.rootNode.childNode(withName: "car", recursively: false) else { return }
        if on {
            if car.action(forKey: "spin") == nil {
                car.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)), forKey: "spin")
            }
        } else {
            car.removeAction(forKey: "spin")
        }
    }

    final class Coordinator {
        var signature = ""
    }
}
