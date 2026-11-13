@preconcurrency import ApplicationServices
import CoreGraphics

/// Shared Accessibility reads and CoreFoundation bridging.
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

    /// A point attribute, defaulting to position, or nil if unavailable.
    func point(_ attribute: CFString = kAXPositionAttribute as CFString) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute, &ref) == .success,
              let v = ref, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &point)
        return point
    }

    /// Reads a string attribute, accepting plain and attributed strings.
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

    /// A banner UUID stable for its lifetime from macOS 26 onward.
    var identifier: String? { stringAttribute(kAXIdentifierAttribute as String) }

    /// Performs an action matching a localized name on its Name line; returns false if none
    /// matches.
    @discardableResult
    func performCustomAction(namedAnyOf names: Set<String>) -> Bool {
        var ref: CFArray?
        guard AXUIElementCopyActionNames(self, &ref) == .success,
              let actions = ref as? [String],
              let action = actions.first(where: { names.contains(customActionName($0)) })
        else { return false }
        return AXUIElementPerformAction(self, action as CFString) == .success
    }

    /// The element's children, or an empty array.
    func children() -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return [] }
        return children
    }

    /// Cleaned static text descendants in tree order, with bounded depth.
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

    /// Reads labelled title, subtitle, and body children; descriptions merge subtitle and body.
    func identifiedTextValues() -> [String: String] {
        var result: [String: String] = [:]
        for child in children()
        where child.stringAttribute(kAXRoleAttribute as String) == (kAXStaticTextRole as String) {
            guard let id = child.stringAttribute(kAXIdentifierAttribute as String),
                  let value = child.stringAttribute(kAXValueAttribute as String) else { continue }
            let cleaned = cleanAXString(value)
            if !cleaned.isEmpty { result[id] = cleaned }
        }
        return result
    }
}

/// Strips invisible formatting scalars such as U+200E, then trims whitespace.
func cleanAXString(_ s: String) -> String {
    s.unicodeScalars
        .filter { !$0.properties.isDefaultIgnorableCodePoint }
        .reduce(into: "") { $0.append(Character($1)) }
        .trimmingCharacters(in: .whitespaces)
}

/// Extracts the Name line of a custom action, or returns a standard action unchanged.
func customActionName(_ action: String) -> String {
    guard action.hasPrefix("Name:") else { return action }
    return String(action.dropFirst(5).prefix { $0 != "\n" })
}
