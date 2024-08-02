# Diminishing VisionOS
## A demo of diminished reality inpainting on VisionOS using ML models on-device
This repo requires EdgeSAM CoreML models and LaMa CoreML models. Also, to use successfully, modify the Objective-C Bridging header to match the local repo's filepath. 
See [my other repo](https://github.com/rjaychen/EdgeSAMVisionOS) on EdgeSAM porting to visionOS

# Exploring object tracking with ARKit
Find and track real-world objects in visionOS using reference objects trained with Create ML.

The sample app demonstrates how to use a Core ML model (a reference object) to discover and track a specific object in a person’s surroundings in visionOS. This capability allows you to create engaging experiences based on objects in a person's surroundings and lets you attach digital content to these objects. To learn more about the features that this sample implements, see [Exploring object tracking with ARKit](https://developer.apple.com/documentation/visionos/exploring_object_tracking_with_arkit).

> Features in this sample that rely on ARKit only run on device, not in Simulator.
