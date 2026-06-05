import ApplicationServices
import CoreGraphics

// MARK: - CGS private symbols (linked via @_silgen_name)

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSSetWindowTransform")
@discardableResult
private func CGSSetWindowTransform(_ connection: Int32, _ windowID: CGWindowID, _ transform: CGAffineTransform) -> Int32

@_silgen_name("CGSSetWindowAlpha")
@discardableResult
private func CGSSetWindowAlpha(_ connection: Int32, _ windowID: CGWindowID, _ alpha: Float) -> Int32

// MARK: - SkyLight runtime symbols (loaded via dlopen to avoid linker errors)

private let _skyLight: UnsafeMutableRawPointer? = dlopen(
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY
)

private func slsMainConnectionID() -> Int32 {
    guard let fn = _skyLight.flatMap({ dlsym($0, "SLSMainConnectionID") }) else { return 0 }
    return unsafeBitCast(fn, to: (@convention(c) () -> Int32).self)()
}

private func slsSetWindowTransform(_ conn: Int32, _ wid: CGWindowID, _ t: CGAffineTransform) -> Int32 {
    guard let fn = _skyLight.flatMap({ dlsym($0, "SLSSetWindowTransform") }) else { return -1 }
    return unsafeBitCast(fn, to: (@convention(c) (Int32, CGWindowID, CGAffineTransform) -> Int32).self)(conn, wid, t)
}

private func slsSetWindowAlpha(_ conn: Int32, _ wid: CGWindowID, _ alpha: Float) -> Int32 {
    guard let fn = _skyLight.flatMap({ dlsym($0, "SLSSetWindowAlpha") }) else { return -1 }
    return unsafeBitCast(fn, to: (@convention(c) (Int32, CGWindowID, Float) -> Int32).self)(conn, wid, alpha)
}

// MARK: - Clean Swift interface

enum PrivateWindowAPI {
    /// Extracts the CGWindowID from an AXUIElement. Returns nil if the element has no associated window.
    static func windowID(for element: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    /// Applies a 2D affine transform to the window at the compositor level.
    /// Tries CGS first, then SkyLight. Returns true if either succeeded.
    @discardableResult
    static func setTransform(_ transform: CGAffineTransform, on windowID: CGWindowID) -> Bool {
        let cgsConn = CGSMainConnectionID()
        let slsConn = slsMainConnectionID()
        let r1 = CGSSetWindowTransform(cgsConn, windowID, transform)
        let r2 = slsSetWindowTransform(slsConn, windowID, transform)
        return r1 == 0 || r2 == 0
    }

    /// Resets a window's transform to identity at the compositor level.
    @discardableResult
    static func resetTransform(on windowID: CGWindowID) -> Bool {
        setTransform(.identity, on: windowID)
    }

    /// Sets the alpha (opacity) of a window at the compositor level.
    /// Tries CGS first, then SkyLight. Returns true if either succeeded.
    @discardableResult
    static func setAlpha(_ alpha: Float, on windowID: CGWindowID) -> Bool {
        let cgsConn = CGSMainConnectionID()
        let slsConn = slsMainConnectionID()
        let r1 = CGSSetWindowAlpha(cgsConn, windowID, alpha)
        let r2 = slsSetWindowAlpha(slsConn, windowID, alpha)
        return r1 == 0 || r2 == 0
    }
}
