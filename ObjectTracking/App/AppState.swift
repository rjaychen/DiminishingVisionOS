/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's overall state.
*/

import ARKit
import RealityFoundation
import RealityKitContent
import UIKit
import simd

@MainActor
@Observable
class AppState {
    var isImmersiveSpaceOpened = false
    
    let referenceObjectLoader = ReferenceObjectLoader()

    func didLeaveImmersiveSpace() {
        // Stop the provider; the provider that just ran in the
        // immersive space is now in a paused state and isn't needed
        // anymore. When a person reenters the immersive space,
        // run a new provider.
        arkitSession.stop()
        isImmersiveSpaceOpened = false
    }

    // MARK: - ARKit state

    private var arkitSession = ARKitSession()
    
    private var worldTracking = WorldTrackingProvider()
    private var objectTracking: ObjectTrackingProvider? = nil
    private var imageTracking = ImageTrackingProvider(referenceImages: ReferenceImage.loadReferenceImages(inGroupNamed: "Target"))
    
    public var objectVisualizations: [UUID: ObjectAnchorVisualization] = [:]
    private var imageAnchors: [UUID: Entity] = [:]
    
    var client = TCPClient(host: "192.168.1.64", port: 8000)
    
    // Inpainting Resources
    public var inpaintingRunning = false
    public var rawImage = UIImage(named: "japan_street")! // MARK: Change this to a simple 1920 x 1080
    public var imageToDisplay: ModelEntity! // entity displayed at runtime
    private var fresnelMaterial: ShaderGraphMaterial! // unused right now
    public var screenShare = Entity()
    var leftCameraOffset: SIMD3<Float> = SIMD3<Float>(0.165, -0.05, -1.0)
    
    // Inpainting Visualization
    public var deskAnchor: Entity? = nil    // The entity seen through the portal
    public var headAnchor: AnchorEntity? = nil
    public var worldEntity = Entity()
    private var imagePoints = [SIMD4<Float>]() // 0 - Top left, 1 - Top Right, 2 - Bottom Left
    private var corners = [Entity]()
    public var xyInImage = SIMD2<Float>(0.0, 0.0)
    
    var objectTrackingStartedRunning = false
    
    var providersStoppedWithError = false
    
    var worldSensingAuthorizationStatus = ARKitSession.AuthorizationStatus.notDetermined
    
    func loadShaderGraphMaterials() async {
        self.fresnelMaterial = try! await ShaderGraphMaterial(named: "/Root/FresnelShader", from: "Fresnel", in: realityKitContentBundle)
        if self.fresnelMaterial != nil {
            try! await self.fresnelMaterial.setParameter(name: "InputColor", value: .textureResource(TextureResource(named: "japan_street")))
        }
    }
    
    nonisolated func startTracking(with root: Entity) async {
        let referenceObjects = await referenceObjectLoader.enabledReferenceObjects

        guard !referenceObjects.isEmpty else {
            fatalError("No reference objects to start tracking")
        }
        
        // Run a new provider every time when entering the immersive space.
        let objectTracking = ObjectTrackingProvider(referenceObjects: referenceObjects)
        do {
            if await imageTracking.state == .stopped {
                await MainActor.run { imageTracking = ImageTrackingProvider(referenceImages: ReferenceImage.loadReferenceImages(inGroupNamed: "Target")) }
            }
            if await worldTracking.state == .stopped {
                await MainActor.run { worldTracking = WorldTrackingProvider() }
            }
            try await arkitSession.run([objectTracking, imageTracking, worldTracking])
        } catch {
            print("Error: \(error)" )
            return
        }
        DispatchQueue.main.async {
            self.objectTracking = objectTracking
        }
        Task {
            await processObjectUpdates(with: root)
        }
        Task {
            await processImageUpdates(with: root)
        }

    }
    
    var allRequiredAuthorizationsAreGranted: Bool {
        worldSensingAuthorizationStatus == .allowed
    }

    var allRequiredProvidersAreSupported: Bool {
        ObjectTrackingProvider.isSupported && ImageTrackingProvider.isSupported && WorldTrackingProvider.isSupported
    }

    var canEnterImmersiveSpace: Bool {
        allRequiredAuthorizationsAreGranted && allRequiredProvidersAreSupported
    }

    nonisolated func requestWorldSensingAuthorization() async {
        let authorizationResult = await arkitSession.requestAuthorization(for: [.worldSensing])
        DispatchQueue.main.async {
            self.worldSensingAuthorizationStatus = authorizationResult[.worldSensing]!
        }
    }
    
    nonisolated func queryWorldSensingAuthorization() async {
        let authorizationResult = await arkitSession.queryAuthorization(for: [.worldSensing])
        DispatchQueue.main.async {
            self.worldSensingAuthorizationStatus = authorizationResult[.worldSensing]!
        }
    }
    
    func processObjectUpdates(with root: Entity) async {
        guard let objectTracking else {
            return
        }
        
        // Wait for object anchor updates and maintain a dictionary of visualizations
        // that are attached to those anchors.
        for await anchorUpdate in objectTracking.anchorUpdates {
            let anchor = anchorUpdate.anchor
            let id = anchor.id

            switch anchorUpdate.event {
            case .added:
                print("Object Anchor Found: \(anchor.referenceObject.name)")
                let group = ModelSortGroup(depthPass: nil)
                
                let model = referenceObjectLoader.usdzsPerReferenceObjectID[anchor.referenceObject.id]
                let visualization = ObjectAnchorVisualization(for: anchor, withModel: model)
                visualization.entity.applyPortalRecursively(with: worldEntity)
                let maskSortComponent = ModelSortGroupComponent(group: group, order: 2) // Order of Drawing within portal
                visualization.entity.components.set(maskSortComponent)
                self.objectVisualizations[id] = visualization
                root.addChild(visualization.entity)
                
                imageToDisplay = ModelEntity(mesh: MeshResource.generatePlane(width: 1.92, height: 1.08))
                let context = CIContext()
                let color = CIImage(color: .clear).cropped(to: CGRect(origin: .zero, size: .init(width: 1920, height: 1080)))
                let cgImage = context.createCGImage(color, from: color.extent)!
                let image = UIImage(cgImage: cgImage)
                let imageMaterial: PhysicallyBasedMaterial =  image.loadTextureToMat()! // temporary material for display
                imageToDisplay.model?.materials = [imageMaterial]
                //imageToDisplay.components.set(OpacityComponent(opacity: 0.5))
//                headAnchor = AnchorEntity()
//                headAnchor?.anchoring = AnchoringComponent(.head)
//                imageToDisplay.transform.translation = leftCameraOffset
//                headAnchor?.addChild(imageToDisplay)
                worldEntity.components.set(WorldComponent())
                worldEntity.addChild(imageToDisplay)
                //worldEntity.addChild(headAnchor!)
                root.addChild(worldEntity)
                //root.addChild(imageToDisplay)
                //root.addChild(headAnchor!) // uncomment to visualize
            
            case .updated:
                objectVisualizations[id]?.update(with: anchor)
//                let headTransform = await self.getDeviceTransform()
//                let leftDirection = -headTransform.columns.0.xyz // shift the model slightly to the left to correct
//                objectVisualizations[id]?.entity.transform.translation += leftDirection * 0.1
                let deviceTransform = await self.getDeviceTransform()
                let localTransform = makeTranslationMatrix(d: leftCameraOffset)
                imageToDisplay.transform = Transform(matrix: deviceTransform * localTransform)
                if imagePoints.count == 3 {
                    let position = anchor.originFromAnchorTransform.position
                    
                    let topLeft = (deviceTransform * makeTranslationMatrix(d: imagePoints[0].xyz + leftCameraOffset)).position
                    let topRight = (deviceTransform * makeTranslationMatrix(d: imagePoints[1].xyz + leftCameraOffset)).position
                    let bottomLeft = (deviceTransform * makeTranslationMatrix(d: imagePoints[2].xyz + leftCameraOffset)).position
                    let adjustedTop = SIMD3<Float>(topLeft.x, topLeft.y - 1.0, topLeft.z),
                        adjustedBottom = SIMD3<Float>(bottomLeft.x, bottomLeft.y - 1.0, bottomLeft.z)
                    let u = getTargetValue(point: position, a: topLeft, b: topRight) // imagePoints[0].xyz, b: imagePoints[1].xyz)
                    let v = getTargetValue(point: position, a: adjustedTop, b: adjustedBottom, axis: 1) // imagePoints[0].xyz, b: imagePoints[2].xyz) // Adjusting here for height difference in transforms
                    //print("t", adjustedTop, "b", adjustedBottom, "p", position)
                    //print("t", topLeft,"b", bottomLeft ,"p", position)
                    if 0 <= u && u <= 1 && 0 <= v && v <= 1 {
                        // send to sam to inpaint and update image
                        let x_coord = u * Float(rawImage.size.width)
                        let y_coord = v * Float(rawImage.size.height)
                        xyInImage = [x_coord, y_coord]
                        //print("(u, v): ", u, v)
                    }
                }
                ///
            case .removed:
                objectVisualizations[id]?.entity.removeFromParent()
                objectVisualizations.removeValue(forKey: id)
            }
        }
    }

    // Scenes / Scenarios -----------------------------------------------
    
    private func defaultScene(with root: Entity, _ anchor: ImageAnchor) {
        let w: Float = 1.92, h: Float = 1.08
        let offset: SIMD3<Float> = [0, 0, 0]
        imagePoints = [SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x: -w * 0.5, y:  h * 0.5, z: 0, w: 0),
                       SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x:  w * 0.5, y:  h * 0.5, z: 0, w: 0),
                       SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x: -w * 0.5, y: -h * 0.5, z: 0, w: 0)]
        if !self.inpaintingRunning {
            let image = UIImage(cgImage: self.client.receivedImage!)
            let imageMaterial: PhysicallyBasedMaterial =  image.loadTextureToMat()!
            imageToDisplay.model?.materials = [imageMaterial]
        }
        //print("Image Anchor Found: \(anchor.referenceImage.name!)")
    }
    
    private func dogSquare(with root: Entity, _ anchor: ImageAnchor){
        let anchorWidth = Float(anchor.referenceImage.physicalSize.width),
            anchorHeight = Float(anchor.referenceImage.physicalSize.width),
            scaleFactor = anchor.estimatedScaleFactor
        let image = UIImage(named: "japan_street")! // MARK: Change this to the image you want as background
        // Create Image Entity
        let w: Float = 0.22352 * scaleFactor, h: Float = 0.12573 * scaleFactor
        //let w: Float = 0.96 * scaleFactor, h: Float = 0.54 * scaleFactor
        imageToDisplay = ModelEntity(mesh: MeshResource.generatePlane(width: w, height: h))
        let offset: SIMD3<Float> = [(Float(w * 0.5) + anchorWidth * 0.5), (Float(h * 0.5) + anchorHeight * 0.5), 0]
        //let offset: SIMD3<Float> = [Float(w*0.5) - 0.27, Float(h*0.5) - (0.1 + anchorHeight * 0.5), 0]
        imagePoints = [SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x: -w * 0.5, y:  h * 0.5, z: 0, w: 0),
                       SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x:  w * 0.5, y:  h * 0.5, z: 0, w: 0),
                       SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x: -w * 0.5, y: -h * 0.5, z: 0, w: 0)]
        imageToDisplay.transform.translation = offset + [0.0, 0.0, 0.01]
        let imageMaterial: PhysicallyBasedMaterial =  image.loadTextureToMat()!
        imageToDisplay.model?.materials = [imageMaterial]
        deskAnchor = Entity()
        deskAnchor?.addChild(imageToDisplay)
        
        // Create White Background
        let background = ModelEntity(mesh: MeshResource.generatePlane(width: 1, height: 1),
                                     materials: [SimpleMaterial(color: .white, isMetallic: false)])
        background.transform.translation = offset
        deskAnchor?.addChild(background)
        
        imageAnchors[anchor.id] = deskAnchor
        //root.addChild(deskAnchor!) //MARK: Uncomment to display image at runtime
        worldEntity.components.set(WorldComponent())
        worldEntity.addChild(deskAnchor!)
        imageAnchors[anchor.id]?.transform = Transform(matrix: anchor.originFromAnchorTransform
                                                       * makeXRotationMatrix(angle: -.pi/2)) // rotate the points onto the side
        for i in 0..<imagePoints.count {
            imagePoints[i] = imageAnchors[anchor.id]!.transform.matrix * imagePoints[i] // actual position of the points
        }
        root.addChild(worldEntity)
        print("Image Anchor Found: \(anchor.referenceImage.name!)")

    }
    
    private func catSquare(with root: Entity, _ anchor: ImageAnchor) {
        let anchorWidth = Float(anchor.referenceImage.physicalSize.width),
            anchorHeight = Float(anchor.referenceImage.physicalSize.width),
            scaleFactor = anchor.estimatedScaleFactor
        let image = UIImage(named: "woodtable2")! // MARK: Change this to the image you want as background
        rawImage = UIImage(named: "japan_street")! // MARK: Change UIimage inpaint each time you select a different background
        // Create Image Entity
        //let w: Float = 0.22352 * scaleFactor, h: Float = 0.12573 * scaleFactor
        let w: Float = 0.96 * scaleFactor, h: Float = 0.54 * scaleFactor
        imageToDisplay = ModelEntity(mesh: MeshResource.generatePlane(width: w, height: h))
        //let offset: SIMD3<Float> = [(Float(w * 0.5) + anchorWidth * 0.5), (Float(h * 0.5) + anchorHeight * 0.5), 0]
        let offset: SIMD3<Float> = [Float(w*0.5) - 0.27, Float(h*0.5) - (0.1 + anchorHeight * 0.5), 0]
        imagePoints = [SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x: -w * 0.5, y:  h * 0.5, z: 0, w: 0),
                       SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x:  w * 0.5, y:  h * 0.5, z: 0, w: 0),
                       SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x: -w * 0.5, y: -h * 0.5, z: 0, w: 0)]
        imageToDisplay.transform.translation = offset + [0.0, 0.0, 0.01]
        let imageMaterial: PhysicallyBasedMaterial =  image.loadTextureToMat()!
        imageToDisplay.model?.materials = [imageMaterial]
        deskAnchor = Entity()
        deskAnchor?.addChild(imageToDisplay)
        
        // Create White Background
        let background = ModelEntity(mesh: MeshResource.generatePlane(width: 1, height: 1),
                                     materials: [SimpleMaterial(color: .white, isMetallic: false)])
        background.transform.translation = offset
        deskAnchor?.addChild(background)
        
        imageAnchors[anchor.id] = deskAnchor
        //root.addChild(deskAnchor!) //MARK: Uncomment to display image at runtime
        worldEntity.components.set(WorldComponent())
        worldEntity.addChild(deskAnchor!)
        imageAnchors[anchor.id]?.transform = Transform(matrix: anchor.originFromAnchorTransform
                                                       * makeXRotationMatrix(angle: -.pi/2))
        for i in 0..<imagePoints.count {
            imagePoints[i] = imageAnchors[anchor.id]!.transform.matrix * imagePoints[i]
        }
        root.addChild(worldEntity)
        print("Image Anchor Found: \(anchor.referenceImage.name!)")

    }
    
    private func updateImageAnchor(with root: Entity, _ anchor: ImageAnchor) {
        /// Create the anchor entity
        if imageAnchors[anchor.id] == nil {
            if anchor.referenceImage.name == "dogsquare" {
                defaultScene(with: root, anchor)
                //dogSquare(with: root, anchor)
            }
            if anchor.referenceImage.name == "catsquare" {
                defaultScene(with: root, anchor)
                //catSquare(with: root, anchor)
            }
        }
    }
    
    
    func processImageUpdates(with root: Entity) async {
        for await update in imageTracking.anchorUpdates {
            updateImageAnchor(with: root, update.anchor)
        }
    }
    
    func monitorSessionEvents() async {
        for await event in arkitSession.events {
            switch event {
            case .dataProviderStateChanged(let providers, let newState, let error):
                switch newState {
                case .initialized:
                    break
                case .running:
                    guard objectTrackingStartedRunning == false, let objectTracking else { continue }
                    for provider in providers where provider === objectTracking {
                        objectTrackingStartedRunning = true
                        break
                    }
                case .paused:
                    break
                case .stopped:
                    guard objectTrackingStartedRunning == true, let objectTracking else { continue }
                    for provider in providers where provider === objectTracking {
                        objectTrackingStartedRunning = false
                        break
                    }
                    if let error {
                        print("An error occurred: \(error)")
                        providersStoppedWithError = true
                    }
                @unknown default:
                    break
                }
            case .authorizationChanged(let type, let status):
                print("Authorization type \(type) changed to \(status)")
                if type == .worldSensing {
                    worldSensingAuthorizationStatus = status
                }
            default:
                print("An unknown event occurred \(event)")
            }
        }
    }
    
    /// Utilities
    
    func getDeviceTransform() async -> simd_float4x4 {
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
            else { return .init() }
            return deviceAnchor.originFromAnchorTransform
    }
    
    func makeXRotationMatrix(angle: Float) -> simd_float4x4 {
        let rows = [
            simd_float4(1,          0,           0, 0),
            simd_float4(0, cos(angle), -sin(angle), 0),
            simd_float4(0, sin(angle),  cos(angle), 0),
            simd_float4(0,          0,           0, 1)
        ]
        return float4x4(rows: rows)
    }
    
    func makeTranslationMatrix(d: SIMD3<Float>) -> simd_float4x4 {
        let rows = [
            simd_float4(1, 0, 0, d.x),
            simd_float4(0, 1, 0, d.y),
            simd_float4(0, 0, 1, d.z),
            simd_float4(0, 0, 0,   1)
        ]
        return float4x4(rows: rows)
    }
    
    func closestPointonLine(point: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>) -> SIMD3<Float> {
        let ap = point - a
        let ab = b - a
        return a + dot(ap, ab) / dot(ab, ab) * ab
    }
    
    func getTargetValue(point: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>, axis: Int = 0) -> Float{
        let p = closestPointonLine(point: point, a: a, b: b)
        let t = (p - a) / (b - a)
        if axis == 0 {
            return t.x
        }
        if axis == 1 {
            return t.y
        }
        return t.z
    }
    
}
