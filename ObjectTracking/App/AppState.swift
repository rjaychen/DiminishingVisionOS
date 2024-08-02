/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's overall state.
*/

import ARKit
import RealityFoundation
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
    
    private var objectTracking: ObjectTrackingProvider? = nil
    private var imageTracking = ImageTrackingProvider(referenceImages: ReferenceImage.loadReferenceImages(inGroupNamed: "Target"))
    
    public var objectVisualizations: [UUID: ObjectAnchorVisualization] = [:]
    private var imageAnchors: [UUID: Entity] = [:]
    public var uiImagetoInpaint = UIImage(named: "japan_street")!
    public var imageToInpaint: ModelEntity!
    public var deskAnchor: Entity? = nil
    private var worldEntity = Entity()
    private var imagePoints = [SIMD4<Float>]()
    public var xyInImage = SIMD2<Float>(0.0, 0.0)
    
    var objectTrackingStartedRunning = false
    
    var providersStoppedWithError = false
    
    var worldSensingAuthorizationStatus = ARKitSession.AuthorizationStatus.notDetermined
    
    func startTracking(with root: Entity) async {
        let referenceObjects = referenceObjectLoader.enabledReferenceObjects
        
        guard !referenceObjects.isEmpty else {
            fatalError("No reference objects to start tracking")
        }
        
        // Run a new provider every time when entering the immersive space.
        let objectTracking = ObjectTrackingProvider(referenceObjects: referenceObjects)
        do {
            try await arkitSession.run([objectTracking, imageTracking])
        } catch {
            print("Error: \(error)" )
            return
        }
        self.objectTracking = objectTracking
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
        ObjectTrackingProvider.isSupported
    }

    var canEnterImmersiveSpace: Bool {
        allRequiredAuthorizationsAreGranted && allRequiredProvidersAreSupported
    }

    func requestWorldSensingAuthorization() async {
        let authorizationResult = await arkitSession.requestAuthorization(for: [.worldSensing])
        worldSensingAuthorizationStatus = authorizationResult[.worldSensing]!
    }
    
    func queryWorldSensingAuthorization() async {
        let authorizationResult = await arkitSession.queryAuthorization(for: [.worldSensing])
        worldSensingAuthorizationStatus = authorizationResult[.worldSensing]!
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
                let model = referenceObjectLoader.usdzsPerReferenceObjectID[anchor.referenceObject.id]
                let visualization = ObjectAnchorVisualization(for: anchor, withModel: model)
                visualization.entity.applyPortalRecursively(with: worldEntity)
                print("Object Anchor Found: \(anchor.referenceObject.name)")
                self.objectVisualizations[id] = visualization
                root.addChild(visualization.entity)
            case .updated:
                objectVisualizations[id]?.update(with: anchor)
                ///
                if imagePoints.count == 3 {
                    let position = anchor.originFromAnchorTransform.position
                    let u = getTargetValue(point: position, a: imagePoints[0].xyz, b: imagePoints[1].xyz)
                    let v = getTargetValue(point: position, a: imagePoints[0].xyz, b: imagePoints[2].xyz)
                    if 0 <= u && u <= 1 && 0 <= v && v <= 1 {
                        // send to sam to inpaint and update image
                        let x_coord = u * Float(uiImagetoInpaint.size.width)
                        let y_coord = v * Float(uiImagetoInpaint.size.height)
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

    private func updateImageAnchor(with root: Entity, _ anchor: ImageAnchor) {
        /// Create the anchor entity
        if imageAnchors[anchor.id] == nil {
            let anchorWidth = Float(anchor.referenceImage.physicalSize.width),
                anchorHeight = Float(anchor.referenceImage.physicalSize.width),
                scaleFactor = anchor.estimatedScaleFactor
            let image = UIImage(named: "japan_street")!
            let w: Float = 0.22352 * scaleFactor, h: Float = 0.12573 * scaleFactor
            imageToInpaint = ModelEntity(mesh: MeshResource.generatePlane(width: w, height: h))
            let offset: SIMD3<Float> = [(Float(w * 0.5) + anchorWidth * 0.5), (Float(h * 0.5) + anchorHeight * 0.5), 0]
            imagePoints = [SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x: -w * 0.5, y:  h * 0.5, z: 0, w: 0),
                           SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x:  w * 0.5, y:  h * 0.5, z: 0, w: 0),
                           SIMD4<Float>(offset, 1.0) + SIMD4<Float>(x: -w * 0.5, y: -h * 0.5, z: 0, w: 0)]
            imageToInpaint.transform.translation = offset + [0.0, 0.0, 0.01]
            let material: PhysicallyBasedMaterial =  image.loadTextureToMat()!
            imageToInpaint.model?.materials = [material]
            deskAnchor = Entity()
            deskAnchor?.addChild(imageToInpaint)
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
    
    
    func makeXRotationMatrix(angle: Float) -> simd_float4x4 {
        let rows = [
            simd_float4(1,          0,           0, 0),
            simd_float4(0, cos(angle), -sin(angle), 0),
            simd_float4(0, sin(angle),  cos(angle), 0),
            simd_float4(0,          0,           0, 1)
        ]
        return float4x4(rows: rows)
    }
    
    func closestPointonLine(point: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>) -> SIMD3<Float> {
        let ap = point - a
        let ab = b - a
        return a + dot(ap, ab) / dot(ab, ab) * ab
    }
    
    func getTargetValue(point: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>) -> Float{
        let p = closestPointonLine(point: point, a: a, b: b)
        let t = (p - a) / (b - a)
        return t.x
    }
    
}
