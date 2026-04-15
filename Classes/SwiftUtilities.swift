import Foundation

// MARK: - Swift Utilities for Gitbox
// This file enables Swift support and provides modern Swift equivalents for legacy Objective-C utilities

@objc class SwiftUtilities: NSObject {
    
    // MARK: - String Helpers
    
    @objc static func uniqueString(_ baseString: String, forStrings strings: [String], appendingFormat format: String = "%d") -> String {
        var index = 0
        var string = baseString
        while strings.contains(string) {
            index += 1
            string = baseString + String(format: format, index)
        }
        return string
    }
    
    @objc static func isEmpty(_ string: String?) -> Bool {
        return string?.isEmpty ?? true
    }
    
    @objc static func capitalizeFirstLetter(_ string: String) -> String {
        guard !string.isEmpty else { return string.capitalized }
        return string.prefix(1).capitalized + string.dropFirst()
    }
    
    @objc static func twoLastPathComponents(_ path: String, separator: String = "/") -> String {
        let components = path.components(separatedBy: "/")
        guard components.count >= 2 else { return path.lastPathComponent }
        return components[components.count - 2] + separator + components.last!
    }
    
    @objc static func md5Hash(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        let hash = data.withUnsafeBytes { bytes in
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    @objc static func trimmedString(_ string: String, toLength limit: Int) -> String {
        guard string.count > limit + 3 else { return string }
        guard limit > 0 else { return "..." }
        
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = String(trimmed.prefix(limit))
        return truncated + "..."
    }
    
    // MARK: - Path Helpers
    
    @objc static func commonPrefix(between path1: String, and path2: String) -> String {
        let standardizedPath1 = path1.standardizingPath
        let standardizedPath2 = path2.standardizingPath
        let components1 = standardizedPath1.components(separatedBy: "/")
        let components2 = standardizedPath2.components(separatedBy: "/")
        
        var commonComponents: [String] = []
        let minCount = min(components1.count, components2.count)
        
        for i in 0..<minCount {
            if components1[i] == components2[i] {
                commonComponents.append(components1[i])
            } else {
                break
            }
        }
        
        return commonComponents.joined(separator: "/")
    }
    
    @objc static func relativePath(from sourcePath: String, to targetPath: String) -> String {
        let standardizedSource = sourcePath.standardizingPath
        let standardizedTarget = targetPath.standardizingPath
        
        var sourceComponents = standardizedSource.components(separatedBy: "/")
        var targetComponents = standardizedTarget.components(separatedBy: "/")
        
        // Remove common prefix
        while !sourceComponents.isEmpty && !targetComponents.isEmpty && sourceComponents.first == targetComponents.first {
            sourceComponents.removeFirst()
            targetComponents.removeFirst()
        }
        
        // Add .. for each remaining source component
        let upComponents = Array(repeating: "..", count: sourceComponents.count)
        let resultComponents = upComponents + targetComponents
        
        return resultComponents.isEmpty ? "." : resultComponents.joined(separator: "/")
    }
}

// MARK: - Swift Extensions

extension String {
    
    var isNotEmpty: Bool {
        return !isEmpty
    }
    
    func appendingEllipsis() -> String {
        if isEmpty { return "..." }
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".") {
            return trimmed + ".."
        }
        return trimmed + "..."
    }
    
    func prettyTrimmed(toLength limit: Int) -> String {
        guard count > limit + 3 else { return self }
        guard limit > 0 else { return "..." }
        
        let words = components(separatedBy: .whitespacesAndNewlines)
        guard words.count > 1 else {
            return SwiftUtilities.trimmedString(self, toLength: limit)
        }
        
        var buffer = ""
        for word in words {
            if buffer.count + word.count + 1 <= limit + 3 {
                buffer += word + " "
            } else {
                break
            }
        }
        
        if buffer.isEmpty {
            return SwiftUtilities.trimmedString(words[0], toLength: limit)
        }
        
        return buffer.appendingEllipsis()
    }
    
    func pathWithSuffix(_ suffix: String) -> String {
        let ext = (self as NSString).pathExtension
        let withoutExt = (self as NSString).deletingPathExtension + suffix
        return ext.isEmpty ? withoutExt : (withoutExt as NSString).appendingPathExtension(ext) ?? withoutExt
    }
}

// MARK: - Import for CommonCrypto
import CommonCrypto