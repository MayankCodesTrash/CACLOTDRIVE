import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO

// usage: convert <input.obj> <output.usdz>
let args = CommandLine.arguments
guard args.count == 3 else { print("usage"); exit(1) }
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
let asset = MDLAsset(url: input)
asset.loadTextures()
let scene = SCNScene(mdlAsset: asset)
let ok = scene.write(to: output, options: nil, delegate: nil, progressHandler: nil)
print(ok ? "wrote \(output.lastPathComponent)" : "FAILED")
