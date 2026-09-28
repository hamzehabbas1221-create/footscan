import SwiftUI
import SceneKit

struct PointCloudView: UIViewRepresentable {
    let points: [SoulPoint]
    var interactive = false
    var dark = true
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(); view.backgroundColor = dark ? UIColor(white:0.055,alpha:1) : UIColor(white:0.95,alpha:1)
        view.scene = SCNScene(); view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30; view.autoenablesDefaultLighting = false
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera(); camera.camera?.zNear = 0.005; camera.camera?.zFar = 5; camera.camera?.fieldOfView = 58
        view.scene?.rootNode.addChildNode(camera); view.pointOfView = camera
        let cloud = SCNNode(); cloud.name = "cloud"; view.scene?.rootNode.addChildNode(cloud)
        view.allowsCameraControl = interactive
        view.defaultCameraController.interactionMode = .orbitTurntable
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        guard let node = view.scene?.rootNode.childNode(withName:"cloud",recursively:false) else { return }
        view.allowsCameraControl = interactive
        guard !points.isEmpty else { node.geometry = nil; return }
        // Render no more than 40,000 points. Export retains the complete point cloud.
        let step=max(1,points.count/40000)
        // The raw camera buffer is landscape. Rotate only the portrait display;
        // exported points and calibration retain their original camera basis.
        let vertices=stride(from:0,to:points.count,by:step).map { SCNVector3(-points[$0].y,points[$0].x,points[$0].z) }
        let source=SCNGeometrySource(vertices:vertices)
        let indices=(0..<vertices.count).map(UInt32.init)
        let bytes=indices.withUnsafeBytes { Data($0) }
        let element=SCNGeometryElement(data:bytes,primitiveType:.point,primitiveCount:vertices.count,bytesPerIndex:4)
        element.pointSize=interactive ? 2.1 : 2.8; element.minimumPointScreenSpaceRadius=1; element.maximumPointScreenSpaceRadius=4
        let geometry=SCNGeometry(sources:[source],elements:[element]); let material=SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents=dark ? UIColor(white:0.91,alpha:1) : UIColor.black; geometry.materials=[material]; node.geometry=geometry
        if interactive {
            // Keep the user's orbit when SwiftUI updates unrelated labels.
            if !context.coordinator.fitted {
                context.coordinator.fitted=true
                let xs=points.map { -$0.y },ys=points.map(\.x),zs=points.map(\.z)
                let center=SCNVector3((xs.min()!+xs.max()!)/2,(ys.min()!+ys.max()!)/2,(zs.min()!+zs.max()!)/2)
                let span=max(xs.max()!-xs.min()!,max(ys.max()!-ys.min()!,zs.max()!-zs.min()!))
                view.pointOfView?.position=SCNVector3(center.x,center.y,center.z+max(0.30,span*1.9)); view.defaultCameraController.target=center
            }
        } else { view.pointOfView?.position=SCNVector3Zero }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var fitted=false }
}
