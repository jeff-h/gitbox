import Foundation
import CommonCrypto

// MARK: - Swift String Extensions (Modern replacements for NSString+OAStringHelpers)

@objc extension NSString {
    
    // MARK: - Unique String Generation
    
    @objc func uniqueString(forStrings strings: [String], appendingFormat format: String = "%d") -> String {
        return SwiftStringHelpers.uniqueString(self as String, forStrings: strings, appendingFormat: format)
    }
    
    @objc func uniqueString(forStrings strings: [String]) -> String {
        return uniqueString(forStrings: strings, appendingFormat: "%d")
    }
    
    // MARK: - String Validation
    
    @objc var isEmptyString: Bool {
        return self.length <= 0
    }
    
    // MARK: - String Formatting
    
    @objc var stringWithFirstLetterCapitalized: String {
        guard self.length > 0 else { return self.capitalized }
        if self.length <= 1 { return self.capitalized }
        
        let firstLetter = self.substring(to: 1).capitalized
        let restLetters = self.substring(from: 1)
        return firstLetter + restLetters
    }
    
    @objc var twoLastPathComponentsWithSlash: String {
        let components = self.pathComponents
        guard components.count >= 2 else { return self.lastPathComponent }
        
        let parentComponent = (self as NSString).deletingLastPathComponent.lastPathComponent
        return "\(parentComponent)/\(self.lastPathComponent)"
    }
    
    @objc var twoLastPathComponentsWithDash: String {
        let components = self.pathComponents
        guard components.count >= 2 else { return self.lastPathComponent }
        
        let parentComponent = (self as NSString).deletingLastPathComponent.lastPathComponent
        return "\(self.lastPathComponent) — \(parentComponent)"
    }
    
    // MARK: - Path Operations
    
    @objc func commonPrefix(withPath path: String) -> String {
        return SwiftStringHelpers.commonPrefix(between: self as String, and: path)
    }
    
    @objc func relativePath(toDirectoryPath baseDirPath: String?) -> String {
        guard let baseDirPath = baseDirPath else { return self as String }
        return SwiftStringHelpers.relativePath(from: baseDirPath, to: self as String)
    }
    
    @objc func path(withSuffix suffix: String) -> String {
        return (self as String).pathWithSuffix(suffix)
    }
    
    // MARK: - String Hashing
    
    @objc var md5hexdigest: String {
        return SwiftStringHelpers.md5Hash(self as String)
    }
    
    // MARK: - String Truncation
    
    @objc var stringByAppendingEllipsis: String {
        return (self as String).appendingEllipsis()
    }
    
    @objc func trimmedString(toLength limit: Int) -> String {
        return SwiftStringHelpers.trimmedString(self as String, toLength: limit)
    }
    
    @objc func prettyTrimmedString(toLength limit: Int) -> String {
        return (self as String).prettyTrimmed(toLength: limit)
    }
    
    // MARK: - URL Encoding (Fixed version)
    
    @objc func stringByAddingPercentEscapesForURLPath() -> String {
        // This is the FIXED version that doesn't break file paths
        return (self as String).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? (self as String)
    }
    
    @objc func stringByAddingPercentEscapesForURLQuery() -> String {
        // This is for URL query parameters where / should be encoded
        return (self as String).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? (self as String)
    }
}

// MARK: - Swift String Extensions

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
            return SwiftStringHelpers.trimmedString(self, toLength: limit)
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
            return SwiftStringHelpers.trimmedString(words[0], toLength: limit)
        }
        
        return buffer.appendingEllipsis()
    }
    
    func pathWithSuffix(_ suffix: String) -> String {
        let ext = (self as NSString).pathExtension
        let withoutExt = (self as NSString).deletingPathExtension + suffix
        return ext.isEmpty ? withoutExt : (withoutExt as NSString).appendingPathExtension(ext) ?? withoutExt
    }
}

// MARK: - Swift Helper Class

@objc class SwiftStringHelpers: NSObject {
    
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
        guard components.count >= 2 else { return (path as NSString).lastPathComponent }
        return components[components.count - 2] + separator + components.last!
    }
    
    @objc static func md5Hash(_ string: String) -> String {
        let data = string.data(using: .utf8)!
        let hash = data.withUnsafeBytes { bytes -> [UInt8] in
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
    
    @objc static func commonPrefix(between path1: String, and path2: String) -> String {
        let standardizedPath1 = (path1 as NSString).standardizingPath
        let standardizedPath2 = (path2 as NSString).standardizingPath
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
        let standardizedSource = (sourcePath as NSString).standardizingPath
        let standardizedTarget = (targetPath as NSString).standardizingPath
        
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

// MARK: - NSMutableString Extensions

@objc extension NSMutableString {
    
    @objc func replaceOccurrences(of target: String, with replacement: String) {
        self.replaceOccurrences(of: target, 
                              with: replacement, 
                              options: [], 
                              range: NSMakeRange(0, self.length))
    }
}