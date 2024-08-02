//
//  ModelHandler.swift
//  MeshInteraction
//
//  Created by I3T Duke on 7/9/24.
//

import SwiftUI
import Vision

class ModelHandler: ObservableObject {
    //private var detection_request: VNCoreMLRequest!
    private var segmentation_request: VNCoreMLRequest!
    
    @State private var segmentAnything: SegmentAnything
    @State private var textureLoader: TextureLoader
    @State private var maskProcessor: MaskProcessor
    
    lazy var inpainting: LaMa? = {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndGPU
            let model = try LaMa(configuration: config)
            return model
        } catch {
            print(error)
            fatalError("inpainting initialize error")
        }
    }()
    
    init() {
        let device = MTLCreateSystemDefaultDevice()!
        self.segmentAnything = SegmentAnything(device: device)
        self.textureLoader = TextureLoader(device: device)
        self.maskProcessor = MaskProcessor(device: device)
        self.segmentAnything.load()
        self.maskProcessor.load()
    }

    func processImage(_ uiImage: UIImage,
                      point: Point = Point(x: 0, y: 0, label: 1)) async -> UIImage? { // MARK: return with checkedContinuation?
        let imageTexture = try! await self.textureLoader.loadTexture(uiImage: uiImage)
        self.segmentAnything.preprocess(image: imageTexture)
        let masks = self.segmentAnything.predictMask(points: [point])
        let maskRaw = self.textureLoader.unloadTexture(texture: masks.first!)
        let mask = self.textureLoader.convertMask(uiImage: maskRaw)
        
        if let resultImage = await self.inpaint_with_lama(inputImage: uiImage, mask: mask) {
            return resultImage
        } else {
            print("failed to create inpainted CGImage")
            return nil
        }
    }

    func inpaint_with_lama(inputImage: UIImage, mask: UIImage) async -> UIImage? {
        guard let model = inpainting else { fatalError("can't load inpainting model.") }
        
        var input: LaMaInput?
        input = try! LaMaInput(imageWith: inputImage.cgImage!, maskWith: mask.cgImage!)
        
        let out = try! await model.prediction(input: input!)
        
        let pixelBuffer = out.output
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("failed to create inpainted CGImage")
            return nil
        }
        let resultImage = UIImage(cgImage: cgImage) // need to return this somehow
        return resultImage
    }
    
}
