import Foundation

enum KQIOSDiagnostics {
  private static let appGroupId = "group.com.kunqiong.remotelink"
  private static let directoryName = "kq-diagnostics"
  private static let usbDirectoryName = "KQDiagnostics"
  private static let maxFileBytes = 2 * 1024 * 1024
  private static let maxUSBMirrorBytes = 24 * 1024 * 1024
  private static let maxUSBMirrorSourceBytes = 2 * 1024 * 1024
  private static let retainedArchives = 4
  private static let maxMessageLength = 8_000
  private static let queue = DispatchQueue(label: "com.kunqiong.remotelink.diagnostics")
  private static let sessionId = UUID().uuidString.lowercased()
  private static var component = "unknown"
  private static let timestampFormatter = ISO8601DateFormatter()

  static func configure(component: String) {
    queue.sync {
      self.component = sanitizedFileComponent(component)
      write(level: "info", category: "lifecycle", message: "diagnostics configured")
    }
  }

  static func log(
    _ level: String = "info",
    category: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    queue.async {
      write(level: level, category: category, message: message, metadata: metadata)
    }
  }

  static func flush() {
    queue.sync {}
  }

  static func flushAndSynchronizeForUSBAccess() {
    queue.sync {
      synchronizeForUSBAccess()
    }
  }

  private static func write(
    level: String,
    category: String,
    message: String,
    metadata: [String: String] = [:]
  ) {
    guard let directory = try? diagnosticsDirectoryURL() else { return }
    let current = directory.appendingPathComponent("\(component).jsonl")
    rotateIfNeeded(current, in: directory)

    var event: [String: Any] = [
      "timestamp": timestampFormatter.string(from: Date()),
      "uptimeSeconds": ProcessInfo.processInfo.systemUptime,
      "level": level,
      "component": component,
      "category": sanitized(category),
      "message": sanitized(message),
      "sessionId": sessionId,
      "bundleVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
      "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
      "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
    if !metadata.isEmpty {
      event["metadata"] = metadata.mapValues { sanitized($0) }
    }
    guard JSONSerialization.isValidJSONObject(event),
          let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else {
      return
    }
    append(data + Data([0x0A]), to: current)
  }

  private static func diagnosticsDirectoryURL() throws -> URL {
    let base: URL
    if let shared = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) {
      base = shared
    } else if let caches = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first {
      base = caches
    } else {
      throw NSError(domain: "KQIOSDiagnostics", code: 1)
    }
    let directory = base.appendingPathComponent(directoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func rotateIfNeeded(_ current: URL, in directory: URL) {
    let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    guard size >= maxFileBytes else { return }
    let archiveName = "\(component)-\(Int(Date().timeIntervalSince1970 * 1000)).jsonl"
    let archive = directory.appendingPathComponent(archiveName)
    try? FileManager.default.moveItem(at: current, to: archive)

    let archives = ((try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? [])
      .filter { $0.lastPathComponent.hasPrefix("\(component)-") }
      .sorted {
        let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return left > right
      }
    for archive in archives.dropFirst(retainedArchives) {
      try? FileManager.default.removeItem(at: archive)
    }
  }

  private static func diagnosticSources() -> [URL] {
    var sources: [URL] = []
    if let diagnostics = try? diagnosticsDirectoryURL(),
       let files = try? FileManager.default.contentsOfDirectory(
         at: diagnostics,
         includingPropertiesForKeys: [.isRegularFileKey],
         options: [.skipsHiddenFiles]
       ) {
      sources.append(contentsOf: files.filter { $0.pathExtension == "jsonl" })
    }
    if let shared = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) {
      let status = shared.appendingPathComponent("kq-broadcast-status.json")
      if FileManager.default.fileExists(atPath: status.path) {
        sources.append(status)
      }
      let logs = shared.appendingPathComponent("log", isDirectory: true)
      if let enumerator = FileManager.default.enumerator(
        at: logs,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      ) {
        for case let url as URL in enumerator {
          if url.pathExtension == "log" || url.lastPathComponent.contains("rustdesk") {
            sources.append(url)
          }
        }
      }
    }
    return sources.sorted {
      let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate) ?? .distantPast
      let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate) ?? .distantPast
      return left > right
    }
  }

  private static func synchronizeForUSBAccess() {
    guard let documents = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first else {
      return
    }
    let destination = documents.appendingPathComponent(usbDirectoryName, isDirectory: true)
    guard (try? FileManager.default.createDirectory(
      at: destination,
      withIntermediateDirectories: true
    )) != nil else {
      return
    }

    var copied = Set<String>()
    var writtenBytes = 0
    for source in diagnosticSources() {
      let remainingBytes = maxUSBMirrorBytes - writtenBytes
      guard remainingBytes > 0 else { break }
      let maximumBytes = min(maxUSBMirrorSourceBytes, remainingBytes)
      let content = sanitizedDiagnosticContent(from: source, maximumBytes: maximumBytes)
      guard let data = content.data(using: .utf8) else { continue }
      let fileName = usbFileName(for: source)
      let target = destination.appendingPathComponent(fileName)
      try? data.write(to: target, options: .atomic)
      copied.insert(fileName)
      writtenBytes += data.count
    }

    let readmeName = "README.txt"
    let readme = [
      "KQ iOS diagnostic logs",
      "Automatically mirrored for USB file sharing.",
      "Sensitive values are redacted before files are copied here.",
      "Updated: \(timestampFormatter.string(from: Date()))",
    ].joined(separator: "\n") + "\n"
    try? readme.data(using: .utf8)?.write(
      to: destination.appendingPathComponent(readmeName),
      options: .atomic
    )
    copied.insert(readmeName)

    if let files = try? FileManager.default.contentsOfDirectory(
      at: destination,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) {
      for file in files where !copied.contains(file.lastPathComponent) {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  private static func usbFileName(for source: URL) -> String {
    let parent = sanitizedFileComponent(source.deletingLastPathComponent().lastPathComponent)
    let stem = sanitizedFileComponent(source.deletingPathExtension().lastPathComponent)
    let extensionName = source.pathExtension
    let base = "\(parent)-\(stem)"
    return extensionName.isEmpty ? base : "\(base).\(extensionName)"
  }

  private static func sanitizedDiagnosticContent(from source: URL, maximumBytes: Int) -> String {
    guard let data = try? Data(contentsOf: source, options: [.mappedIfSafe]) else {
      return "<unable to read diagnostic file>"
    }
    let tail = data.count > maximumBytes ? data.suffix(maximumBytes) : data[...]
    let text = String(data: tail, encoding: .utf8) ?? "<non-UTF8 diagnostic data>"
    return sanitized(text, maximumLength: text.count)
  }

  private static func append(_ data: Data, to url: URL) {
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { handle.closeFile() }
    handle.seekToEndOfFile()
    handle.write(data)
  }

  private static func sanitizedFileComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
      .map(String.init)
      .joined()
  }

  private static func sanitized(_ value: String, maximumLength: Int = maxMessageLength) -> String {
    var result = String(value.prefix(maximumLength))
    let patterns = [
      "(?i)(password|passwd|token|secret|authorization|cookie|salt|hash|private[_-]?key|api[_-]?key)(\\s*[=:]\\s*)([^\\s,;}&]+)",
      "(?i)bearer\\s+[A-Za-z0-9._~+/-]+",
      "(?i)[?&](token|code|state|password|key)=([^&\\s]+)",
      "\\b[A-Fa-f0-9]{32,}\\b",
      "\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b",
    ]
    for pattern in patterns {
      guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(result.startIndex..., in: result)
      let replacement = pattern.hasPrefix("(?i)(password") ? "$1$2<redacted>" : "<redacted>"
      result = expression.stringByReplacingMatches(
        in: result,
        options: [],
        range: range,
        withTemplate: replacement
      )
    }
    return result
  }
}
