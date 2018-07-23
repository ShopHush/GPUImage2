//
//  ImageCombinationFilter.swift
//  GPUImage_macOS
//
//  Created by Brophy on 6/27/18.
//  Copyright © 2018 Sunset Lake Software LLC. All rights reserved.
//

public class ImageCombinationFilter: BasicOperation {
    public var intensity: Float = 0.5 {
        didSet {
            uniformSettings["smoothDegree"] = intensity
        }
    }
    
    public init() {
        let initialShader = crashOnShaderCompileFailure("Beautify"){try sharedImageProcessingContext.programForVertexShader(
            ThreeInputVertexShader,
            fragmentShader:BeautifyFragmentShader)
        }
        super.init(shader: initialShader, numberOfInputs: 3)
        
        ({intensity = 0.5})()
    }
}
