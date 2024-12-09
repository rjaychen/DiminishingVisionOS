import SwiftUI
import RealityKit

@Observable
@MainActor
class StreamAppState {
    var texture: TextureResource? = nil
    let contentEntity = Entity()
    var client = TCPClient(host: "192.168.1.75", port: 8000) // MARK: Modify IP here...
    var planeEntity: ModelEntity?
    
    func addCube() {
        for entity in contentEntity.children {
            contentEntity.removeChild(entity) }
        let boxResource = MeshResource.generateBox(size: 0.4)
        let mat = UnlitMaterial(texture: texture!)
        let cube = ModelEntity(mesh: boxResource, materials: [mat])
        cube.transform.translation = [0, 1.6, -1]
        cube.transform.rotation = simd_quatf(angle: .pi / 4, axis: [1, 1, 0])
        contentEntity.addChild(cube)
    }
    
    func addPlane() {
        for entity in contentEntity.children {
            contentEntity.removeChild(entity)
        }
        let planeResource = MeshResource.generatePlane(width: 1.92, height: 1.08)
        let mat = UnlitMaterial(texture: texture!)
        let plane = ModelEntity(mesh: planeResource, materials: [mat])
        plane.transform.translation = [0, 1.6, -1]
        plane.name = "Plane"
        planeEntity = plane
        contentEntity.addChild(plane)
    }
    
    func setupContentEntity() -> Entity {
        return contentEntity
    }
}
