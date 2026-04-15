import Foundation

// MARK: - Swift FileManager Extensions (Modern replacements for NSFileManager+OAFileManagerHelpers)

@objc extension FileManager {
    
    // MARK: - Path Operations
    
    @objc func pathExists(atPath path: String) -> Bool {
        return fileExists(atPath: path)
    }
    
    @objc func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
    
    @objc func fileExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }
    
    @objc func createDirectoryIfNeeded(atPath path: String) -> Bool {
        guard !directoryExists(atPath: path) else { return true }
        
        do {
            try createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            print("Failed to create directory at \(path): \(error)")
            return false
        }
    }
    
    @objc func safelyRemoveItem(atPath path: String) -> Bool {
        guard pathExists(atPath: path) else { return true }
        
        do {
            try removeItem(atPath: path)
            return true
        } catch {
            print("Failed to remove item at \(path): \(error)")
            return false
        }
    }
    
    @objc func safelyCopyItem(from sourcePath: String, to destinationPath: String) -> Bool {
        guard pathExists(atPath: sourcePath) else {
            print("Source path does not exist: \(sourcePath)")
            return false
        }
        
        // Remove destination if it exists
        if pathExists(atPath: destinationPath) {
            guard safelyRemoveItem(atPath: destinationPath) else {
                print("Failed to remove existing destination: \(destinationPath)")
                return false
            }
        }
        
        do {
            try copyItem(atPath: sourcePath, toPath: destinationPath)
            return true
        } catch {
            print("Failed to copy item from \(sourcePath) to \(destinationPath): \(error)")
            return false
        }
    }
    
    @objc func safelyMoveItem(from sourcePath: String, to destinationPath: String) -> Bool {
        guard pathExists(atPath: sourcePath) else {
            print("Source path does not exist: \(sourcePath)")
            return false
        }
        
        // Remove destination if it exists
        if pathExists(atPath: destinationPath) {
            guard safelyRemoveItem(atPath: destinationPath) else {
                print("Failed to remove existing destination: \(destinationPath)")
                return false
            }
        }
        
        do {
            try moveItem(atPath: sourcePath, toPath: destinationPath)
            return true
        } catch {
            print("Failed to move item from \(sourcePath) to \(destinationPath): \(error)")
            return false
        }
    }
    
    // MARK: - File Content Operations
    
    @objc func stringContents(ofFileAtPath path: String) -> String? {
        guard fileExists(atPath: path) else { return nil }
        
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            print("Failed to read string contents from \(path): \(error)")
            return nil
        }
    }
    
    @objc func dataContents(ofFileAtPath path: String) -> Data? {
        guard fileExists(atPath: path) else { return nil }
        
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            print("Failed to read data contents from \(path): \(error)")
            return nil
        }
    }
    
    @objc func writeString(_ string: String, toFileAtPath path: String) -> Bool {
        do {
            try string.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("Failed to write string to \(path): \(error)")
            return false
        }
    }
    
    @objc func writeData(_ data: Data, toFileAtPath path: String) -> Bool {
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            print("Failed to write data to \(path): \(error)")
            return false
        }
    }
    
    // MARK: - File Size and Attributes
    
    @objc func sizeOfFile(atPath path: String) -> Int64 {
        guard fileExists(atPath: path) else { return 0 }
        
        do {
            let attributes = try attributesOfItem(atPath: path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            print("Failed to get file size for \(path): \(error)")
            return 0
        }
    }
    
    @objc func modificationDate(ofFileAtPath path: String) -> Date? {
        guard pathExists(atPath: path) else { return nil }
        
        do {
            let attributes = try attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            print("Failed to get modification date for \(path): \(error)")
            return nil
        }
    }
    
    @objc func isReadableFile(atPath path: String) -> Bool {
        return isReadableFile(atPath: path)
    }
    
    @objc func isWritableFile(atPath path: String) -> Bool {
        return isWritableFile(atPath: path)
    }
    
    @objc func isExecutableFile(atPath path: String) -> Bool {
        return isExecutableFile(atPath: path)
    }
    
    // MARK: - Directory Contents
    
    @objc func contentsOfDirectory(atPath path: String) -> [String]? {
        guard directoryExists(atPath: path) else { return nil }
        
        do {
            return try contentsOfDirectory(atPath: path)
        } catch {
            print("Failed to get directory contents for \(path): \(error)")
            return nil
        }
    }
    
    @objc func subpaths(atPath path: String) -> [String]? {
        guard directoryExists(atPath: path) else { return nil }
        
        return subpaths(atPath: path)
    }
    
    // MARK: - Temporary Files
    
    @objc func temporaryFilePath(withExtension ext: String? = nil) -> String {
        let tempDir = NSTemporaryDirectory()
        let fileName = UUID().uuidString
        let fullFileName = ext != nil ? "\(fileName).\(ext!)" : fileName
        return (tempDir as NSString).appendingPathComponent(fullFileName)
    }
    
    @objc func temporaryDirectoryPath() -> String {
        let tempDir = NSTemporaryDirectory()
        let dirName = UUID().uuidString
        let fullPath = (tempDir as NSString).appendingPathComponent(dirName)
        
        if createDirectoryIfNeeded(atPath: fullPath) {
            return fullPath
        } else {
            return tempDir
        }
    }
}

// MARK: - Swift FileManager Helper Class

@objc class SwiftFileManagerHelpers: NSObject {
    
    @objc static let shared = SwiftFileManagerHelpers()
    
    @objc static func pathExists(_ path: String) -> Bool {
        return FileManager.default.pathExists(atPath: path)
    }
    
    @objc static func directoryExists(_ path: String) -> Bool {
        return FileManager.default.directoryExists(atPath: path)
    }
    
    @objc static func fileExists(_ path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }
    
    @objc static func createDirectoryIfNeeded(_ path: String) -> Bool {
        return FileManager.default.createDirectoryIfNeeded(atPath: path)
    }
    
    @objc static func safelyRemoveItem(_ path: String) -> Bool {
        return FileManager.default.safelyRemoveItem(atPath: path)
    }
    
    @objc static func safelyCopyItem(from sourcePath: String, to destinationPath: String) -> Bool {
        return FileManager.default.safelyCopyItem(from: sourcePath, to: destinationPath)
    }
    
    @objc static func safelyMoveItem(from sourcePath: String, to destinationPath: String) -> Bool {
        return FileManager.default.safelyMoveItem(from: sourcePath, to: destinationPath)
    }
    
    @objc static func stringContents(ofFile path: String) -> String? {
        return FileManager.default.stringContents(ofFileAtPath: path)
    }
    
    @objc static func writeString(_ string: String, toFile path: String) -> Bool {
        return FileManager.default.writeString(string, toFileAtPath: path)
    }
    
    @objc static func sizeOfFile(_ path: String) -> Int64 {
        return FileManager.default.sizeOfFile(atPath: path)
    }
    
    @objc static func temporaryFilePath(withExtension ext: String? = nil) -> String {
        return FileManager.default.temporaryFilePath(withExtension: ext)
    }
    
    @objc static func temporaryDirectoryPath() -> String {
        return FileManager.default.temporaryDirectoryPath()
    }
}