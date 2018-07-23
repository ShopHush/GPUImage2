//
//  ImageBufferIntercepter.swift
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
    public var completedPixelBufferRenderingCallback: ((ImageBufferIntercepter) -> ())?
    
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
    
    private let pixelBufferPool: CVPixelBufferPool
    
    private let processingQueue: DispatchQueue = DispatchQueue(label: "ImageBufferIntercepter", qos: DispatchQoS.utility)
    
    public init(pixelBufferPool: CVPixelBufferPool, size: Size) {
        if sharedImageProcessingContext.supportsTextureCaches() {
            self.colorSwizzlingShader = sharedImageProcessingContext.passthroughShader
        } else {
            self.colorSwizzlingShader = crashOnShaderCompileFailure("MovieOutput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(1), fragmentShader:ColorSwizzlingFragmentShader)}
        }
        self.size = size
        self.pixelBufferPool = pixelBufferPool
    }
    
    deinit {
    }
    
    public func newFramebufferAvailable(_ framebuffer:Framebuffer, fromSourceIndex:UInt) {
        processFramebuffer(framebuffer)
    }
    
    public func startRecording() {
        startTime = nil
        sharedImageProcessingContext.runOperationSynchronously{
            self.isRecording = true
            
            CVPixelBufferPoolCreatePixelBuffer(nil, self.pixelBufferPool, &self.pixelBuffer)
            
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
            let status = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, self.pixelBuffer!, nil, GLenum(GL_TEXTURE_2D), GL_RGBA, bufferSize.width, bufferSize.height, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), 0, &cachedTextureRef)
            
            guard status == kCVReturnSuccess else {
                print("ERROR CREATING OpenGLESTexture! Error code: \(status)")
                self.isRecording = false
                return
            }
            let cachedTexture = CVOpenGLESTextureGetName(cachedTextureRef!)
            
            self.renderFramebuffer = try! Framebuffer(context:sharedImageProcessingContext, orientation:.landscapeRight, size:bufferSize, textureOnly:false, overriddenTexture: cachedTexture)
        }
    }
    
    public func stopRecording(withCompletionHandler completionHandler: (() -> Void)?) {
        sharedImageProcessingContext.runOperationSynchronously{
            self.isRecording = false
            sharedImageProcessingContext.runOperationAsynchronously {
                self.completedPixelBufferRenderingCallback?(self)
                completionHandler?()
            }
        }
    }
    
    func renderIntoPixelBuffer(_ pixelBuffer:CVPixelBuffer, framebuffer:Framebuffer) {
        if !sharedImageProcessingContext.supportsTextureCaches() {
            self.renderFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:framebuffer.orientation, size:GLSize(self.size))
            self.renderFramebuffer.lock()
        }
        
        self.renderFramebuffer.activateFramebufferForRendering()
        clearFramebufferWithColor(Color.black)
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        renderQuadWithShader(self.colorSwizzlingShader, uniformSettings:ShaderUniformSettings(), vertexBufferObject:sharedImageProcessingContext.standardImageVBO, inputTextures:[framebuffer.texturePropertiesForOutputRotation(.noRotation)])
        
        if sharedImageProcessingContext.supportsTextureCaches() {
            glFinish()
        } else {
            glReadPixels(0, 0, self.renderFramebuffer.size.width, self.renderFramebuffer.size.height, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddress(pixelBuffer))
            self.renderFramebuffer.unlock()
        }
    }
    
    
    private func processFramebuffer(_ framebuffer: Framebuffer) {
        guard self.isRecording else {
            framebuffer.unlock()
            return
        }
        
        sharedImageProcessingContext.runOperationAsynchronously {
            defer {
                framebuffer.unlock()
            }
            
            
            // Ignore still images and other non-video updates (do I still need this?)
            guard let frameTime = framebuffer.timingStyle.timestamp?.asCMTime else { return }
            // If two consecutive times with the same value are added to the movie, it aborts recording, so I bail on that case
            guard (frameTime != self.previousFrameTime) else { return }

            self.previousFrameTime = frameTime
            
            if (self.startTime == nil) {
                self.startTime = frameTime
            }
            
            if !sharedImageProcessingContext.supportsTextureCaches() {
                let pixelBufferStatus = CVPixelBufferPoolCreatePixelBuffer(nil, self.pixelBufferPool, &self.pixelBuffer)
                guard ((self.pixelBuffer != nil) && (pixelBufferStatus == kCVReturnSuccess)) else { return }
            }
            
            self.renderIntoPixelBuffer(self.pixelBuffer!, framebuffer:framebuffer)
            
            self.pixelBufferAvailableCallback?(self.pixelBuffer!, frameTime)
            
            CVPixelBufferUnlockBaseAddress(self.pixelBuffer!, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
            if !sharedImageProcessingContext.supportsTextureCaches() {
                self.pixelBuffer = nil
            }
        }
    }
}
