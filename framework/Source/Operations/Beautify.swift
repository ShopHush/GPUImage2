//
//  Beautify.swift
//  GPUImage_macOS
//
//  Created by Brophy on 6/27/18.
//  Copyright © 2018 Sunset Lake Software LLC. All rights reserved.
//


public class Beautify: OperationGroup {
    private let bilateralFilter = BilateralBlur()
    private let cannyEdgeFilter = CannyEdgeDetection()
    private let combinationFilter = ImageCombinationFilter()
    private let hsbFilter = OperationGroup()
    
    public var intensity: Float = 0.5 {
        didSet {
            self.combinationFilter.intensity = intensity
        }
    }
    
    override public init() {
        super.init()
        
        bilateralFilter.distanceNormalizationFactor = 4.0
        
        hsbFilter.configureGroup { (input, output) in
            let saturationFilter = SaturationAdjustment()
            let brightnessFilter = BrightnessAdjustment()

            saturationFilter.saturation = 1.1

            brightnessFilter.brightness = 0.1

            input --> brightnessFilter --> saturationFilter --> output
        }
        
//        let colorFilter = ColorMatrixFilter()
//
//        colorFilter.colorMatrix = Matrix4x4(rowMajorValues:[1.0, 0.0, 0.0, 0.0,
//                                                            0.0, 1.0, 0.0, 0.0,
//                                                            0.0, 0.0, 1.0, 0.0,
//                                                            0.0, 0.0, 0.0, 1.0])
        
        self.configureGroup { (input, output) in
            input --> self.bilateralFilter
            input --> self.cannyEdgeFilter
            bilateralFilter --> combinationFilter
            cannyEdgeFilter --> combinationFilter
            input --> combinationFilter
            combinationFilter --> hsbFilter --> output
//            input --> self.bilateralFilter --> cannyEdgeFilter --> combinationFilter --> hsbFilter --> output
        }
//
//
//        self.configureGroup { (input, output) in
//            input --> combinationFilter --> hsbFilter --> output
//                      bilateralFilter --> combinationFilter
//                      cannyEdgeFilter --> combinationFilter
//
////            input --> bilateralFilter --> combinationFilter
////            input --> cannyEdgeFilter --> combinationFilter
////            input --> combinationFilter
//
////            combinationFilter --> hsbFilter --> output
////            input --> output
////            input --> bilateralFilter --> output // combinationFilter// --> output
////            input --> cannyEdgeFilter --> output // combinationFilter// --> output
////            input --> hsbFilter --> combinationFilter// --> output
////            combinationFilter --> output
//
//        }
        
    }
}
