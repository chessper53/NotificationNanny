@preconcurrency import ApplicationServices
import CoreGraphics

/// Thin, side-effect-free conveniences over the C Accessibility API. Keeping these in one place
/// (rather than re-spelling `AXUIElementCopyAttributeValue` everywhere) keeps the repositioner and
/// resolver focused on logic instead of CoreFoundation bridging.
extension AXUIElement {

    /// The element's `kAXSizeAttribute`, or `nil` if unavailable.
    func size() -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXSizeAttribute as CFString, &ref) == .success,
              let v = ref, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        AXValueGetValue(v as! AXValue, .cgSize, &size)
        return size
    }

    /// A point-valued attribute (defaults to `kAXPositionAttribute`), or `nil` if unavailable.
    func point(_ attribute: CFString = kAXPositionAttribute as CFString) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute, &ref) == .success,
              let v = ref, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &point)
        return point
    }

    /// A string-valued attribute, handling both plain `String` and `CFAttributedString` results.
    func stringAttribute(_ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &ref) == .success,
              let v = ref else { return nil }
        if let s = v as? String { return s }
        if CFGetTypeID(v) == CFAttributedStringGetTypeID() {
            return CFAttributedStringGetString((v as! CFAttributedString)) as String
        }
        return nil
    }

    /// The element's children, or an empty array.
    func children() -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return [] }
        return children
    }

    /// Cleaned values of all `AXStaticText` descendants, in tree order, depth-limited.
    func staticTextValues(depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }
        var result: [String] = []
        if stringAttribute(kAXRoleAttribute as String) == (kAXStaticTextRole as String),
           let value = stringAttribute(kAXValueAttribute as String) {
            let cleaned = cleanAXString(value)
            if !cleaned.isEmpty { result.append(cleaned) }
        }
        for child in children() { result.append(contentsOf: child.staticTextValues(depth: depth + 1)) }
        return result
    }
}

/// Strips default-ignorable scalars (e.g. WhatsApp's U+200E) and trims surrounding spaces.
func cleanAXString(_ s: String) -> String {
    s.unicodeScalars
        .filter { !$0.properties.isDefaultIgnorableCodePoint }
        .reduce(into: "") { $0.append(Character($1)) }
        .trimmingCharacters(in: .whitespaces)
}
