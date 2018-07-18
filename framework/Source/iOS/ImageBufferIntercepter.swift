//
//  SampleBufferOutput.swift
//  GPUImage2
//
//  Created by Brophy on 7/17/18.
//

import UIKit
import OpenGLES
import CoreVideo
import CoreMedia
import AVFoundation

public class ImageBufferIntercepter: ImageConsumer {

    public var pixelBufferAvailableCallback:((CVPixelBuffer, CMTime) -> ())?
    
    var storedFramebuffer:Framebuffer?
    
    let size:Size
    let colorSwizzlingShader:ShaderProgram
    
    var pixelBuffer:CVPixelBuffer? = nil
    var renderFramebuffer:Framebuffer!
    
    private var startTime:CMTime?
    private var previousFrameTime = kCMTimeNegativeInfinity
    
    public let sources = SourceContainer()
    public let maximumInputs:UInt = 1
    var isRecording: Bool = false
    
    private let assetWriterPixelBufferInput:AVAssetWriterInputPixelBufferAdaptor
    
    public init(assetWriterPixelBufferInput:AVAssetWriterInputPixelBufferAdaptor, size: Size) {
        if sharedImageProcessingContext.supportsTextureCaches() {
            self.colorSwizzlingShader = sharedImageProcessingContext.passthroughShader
        } else {
            self.colorSwizzlingShader = crashOnShaderCompileFailure("MovieOutput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(1), fragmentShader:ColorSwizzlingFragmentShader)}
        }
        self.size = size
        self.assetWriterPixelBufferInput = assetWriterPixelBufferInput
    }
    
    deinit {
    }
    
    public func newFramebufferAvailable(_ framebuffer:Framebuffer, fromSourceIndex:UInt) {
        defer {
            framebuffer.unlock()
        }
        guard self.isRecording else {
            return
        }
        
        // Ignore still images and other non-video updates (do I still need this?)
        guard let frameTime = framebuffer.timingStyle.timestamp?.asCMTime else { return }
        // If two consecutive times with the same value are added to the movie, it aborts recording, so I bail on that case
        guard (frameTime != previousFrameTime) else { return }
        
        if (startTime == nil) {
            startTime = frameTime
        }
        
        if !sharedImageProcessingContext.supportsTextureCaches() {
            let pixelBufferStatus = CVPixelBufferPoolCreatePixelBuffer(nil, assetWriterPixelBufferInput.pixelBufferPool!, &pixelBuffer)
            guard ((pixelBuffer != nil) && (pixelBufferStatus == kCVReturnSuccess)) else { return }
        }
        
        renderIntoPixelBuffer(pixelBuffer!, framebuffer:framebuffer)

        pixelBufferAvailableCallback?(pixelBuffer!, frameTime)
        
//        if (!assetWriterPixelBufferInput.append(pixelBuffer!, withPresentationTime:frameTime)) {
//            debugPrint("Problem appending pixel buffer at time: \(frameTime)")
//        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        if !sharedImageProcessingContext.supportsTextureCaches() {
            pixelBuffer = nil
        }
    }
    
    public func startRecording() {
        startTime = nil
        sharedImageProcessingContext.runOperationSynchronously{
            self.isRecording = true
            
            CVPixelBufferPoolCreatePixelBuffer(nil, self.assetWriterPixelBufferInput.pixelBufferPool!, &self.pixelBuffer)
            
            /* AVAssetWriter will use BT.601 conversion matrix for RGB to YCbCr conversion
             * regardless of the kCVImageBufferYCbCrMatrixKey value.
             * Tagging the resulting video file as BT.601, is the best option right now.
             * Creating a proper BT.709 video is not possible at the moment.
             */
            CVBufferSetAttachment(self.pixelBuffer!, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(self.pixelBuffer!, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, .shouldPropagate)
            CVBufferSetAttachment(self.pixelBuffer!, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
            
            let bufferSize = GLSize(self.size)
            var cachedTextureRef:CVOpenGLESTexture? = nil
            let _ = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, self.pixelBuffer!, nil, GLenum(GL_TEXTURE_2D), GL_RGBA, bufferSize.width, bufferSize.height, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), 0, &cachedTextureRef)
            let cachedTexture = CVOpenGLESTextureGetName(cachedTextureRef!)
            
            self.renderFramebuffer = try! Framebuffer(context:sharedImageProcessingContext, orientation:.landscapeRight, size:bufferSize, textureOnly:false, overriddenTexture: cachedTexture)
        }
    }
    
    public func stopRecording() {
        sharedImageProcessingContext.runOperationSynchronously{
            self.isRecording = false
        }
    }
    
    func renderIntoPixelBuffer(_ pixelBuffer:CVPixelBuffer, framebuffer:Framebuffer) {
        if !sharedImageProcessingContext.supportsTextureCaches() {
            renderFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:framebuffer.orientation, size:GLSize(self.size))
            renderFramebuffer.lock()
        }
        
        renderFramebuffer.activateFramebufferForRendering()
        clearFramebufferWithColor(Color.black)
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        renderQuadWithShader(colorSwizzlingShader, uniformSettings:ShaderUniformSettings(), vertexBufferObject:sharedImageProcessingContext.standardImageVBO, inputTextures:[framebuffer.texturePropertiesForOutputRotation(.noRotation)])
        
        if sharedImageProcessingContext.supportsTextureCaches() {
            glFinish()
        } else {
            glReadPixels(0, 0, renderFramebuffer.size.width, renderFramebuffer.size.height, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddress(pixelBuffer))
            renderFramebuffer.unlock()
        }
    }
    
}
