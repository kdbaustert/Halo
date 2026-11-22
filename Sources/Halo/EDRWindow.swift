import AppKit
import Metal
import QuartzCore

/// A one-point window in the screen's bottom-left corner that shows a pixel brighter than SDR
/// white. While any EDR content is on screen, macOS runs the panel in EDR mode, and that is what
/// lets a gamma table above 1.0 reach it. The corner pixel sits under the panel's rounded corner,
/// so nothing visible is drawn.
@MainActor
final class EDRWindow {
    private let window: NSWindow
    private let metalLayer: CAMetalLayer
    private let commandQueue: MTLCommandQueue
    /// Nil until the first frame is on screen.
    private var drawnBrightness: Float?

    init(screen: NSScreen) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else { throw BoostError.metalUnavailable }
        self.commandQueue = commandQueue

        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        metalLayer.contentsScale = screen.backingScaleFactor

        let frame = NSRect(origin: screen.frame.origin, size: NSSize(width: 1, height: 1))
        window = NSWindow(
            contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Hide Halo, or Hide Others from another app while Settings is open, would otherwise take
        // this window off screen and EDR mode with it.
        window.canHide = false
        // Above fullscreen apps, so EDR mode doesn't drop when one covers the corner.
        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        // Left out of screenshots and screen recordings.
        window.sharingType = .none

        // Layer-hosting view: the layer is assigned before wantsLayer, so AppKit uses it as is.
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.layer = metalLayer
        view.wantsLayer = true
        window.contentView = view
        metalLayer.drawableSize = CGSize(
            width: frame.width * screen.backingScaleFactor,
            height: frame.height * screen.backingScaleFactor)
    }

    /// Called on every reapply, so it does nothing when the pixel is already up. Redrawing it each
    /// time kept about 84 MB of Metal buffers alive, which the driver frees a few seconds after the
    /// last frame, and reordering a window that's already in front logs a line per call.
    func show(brightness: Float) {
        if !window.occlusionState.contains(.visible) { window.orderFrontRegardless() }
        if brightness != drawnBrightness { draw(brightness: brightness) }
    }

    func close() {
        window.close()
    }

    private func draw(brightness: Float) {
        guard let drawable = metalLayer.nextDrawable(),
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }
        let level = Double(brightness)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: level, green: level, blue: level, alpha: 1)
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        drawnBrightness = brightness
    }
}
