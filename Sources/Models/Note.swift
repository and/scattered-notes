import Foundation

public struct Note: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public var categoryType: CategoryType
    public var targetName: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String]
    public var filePath: URL?
    public var isPinned: Bool
    
    public init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        categoryType: CategoryType = .inbox,
        targetName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        filePath: URL? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.categoryType = categoryType
        self.targetName = targetName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.filePath = filePath
        self.isPinned = isPinned
    }
    
    public var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback to first line of content
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# " ))
            }
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "Untitled Note"
    }
    
    public var previewExcerpt: String {
        let lines = content.components(separatedBy: .newlines)
        var previewLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip heading if it matches the title
            if trimmed.hasPrefix("#") && trimmed.contains(displayTitle) {
                continue
            }
            if !trimmed.isEmpty {
                previewLines.append(trimmed)
                if previewLines.count >= 2 { break }
            }
        }
        return previewLines.joined(separator: " ")
    }
    
    public var destinationDisplay: String {
        switch categoryType {
        case .inbox:
            return "Inbox"
        case .project:
            return targetName ?? "Project"
        case .area:
            return targetName ?? "Area"
        }
    }
    
    // Checklists progress helper
    public var checklistStats: (completed: Int, total: Int)? {
        let lines = content.components(separatedBy: .newlines)
        var total = 0
        var completed = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]") {
                total += 1
            } else if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") ||
                      trimmed.hasPrefix("* [x]") || trimmed.hasPrefix("* [X]") {
                total += 1
                completed += 1
            }
        }
        return total > 0 ? (completed, total) : nil
    }
}

// MARK: - Checklist Toggling
extension Note {
    /// Flips the checklist box on `lineIndex` of `content`; other lines are left untouched.
    public static func togglingChecklistLine(_ lineIndex: Int, in content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        guard lineIndex < lines.count else { return content }
        let line = lines[lineIndex]
        
        if line.contains("- [ ]") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [ ]", with: "- [x]")
        } else if line.contains("- [x]") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [x]", with: "- [ ]")
        } else if line.contains("- [X]") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [X]", with: "- [ ]")
        } else if line.contains("* [ ]") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [ ]", with: "* [x]")
        } else if line.contains("* [x]") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [x]", with: "* [ ]")
        } else if line.contains("* [X]") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [X]", with: "* [ ]")
        } else if let done = completingPlainLine(line) {
            lines[lineIndex] = done
        }
        return lines.joined(separator: "\n")
    }
}

extension Note {
    /// Turns a plain line such as "call the bank tomorrow" into the checked item "- [x] call the bank tomorrow",
    /// keeping its indentation and replacing an existing bullet. Returns nil for blank lines and headings.
    private static func completingPlainLine(_ line: String) -> String? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        var body = String(line.dropFirst(indent.count))
        guard !body.trimmingCharacters(in: .whitespaces).isEmpty, !body.hasPrefix("#") else { return nil }
        for bullet in ["- ", "* ", "+ "] where body.hasPrefix(bullet) {
            body = String(body.dropFirst(bullet.count))
            break
        }
        return "\(indent)- [x] \(body)"
    }
}

// MARK: - Markdown & YAML Serialization
extension Note {
    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private nonisolated(unsafe) static let fallbackIsoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    public func serializeToMarkdown() -> String {
        var fm = "---\n"
        fm += "id: \(id.uuidString)\n"
        fm += "title: \"\(Self.escapeYAML(title))\"\n"
        fm += "type: \(categoryType.rawValue)\n"
        if let target = targetName, !target.isEmpty {
            fm += "target: \"\(Self.escapeYAML(target))\"\n"
        }
        fm += "created_at: \(Self.isoFormatter.string(from: createdAt))\n"
        fm += "updated_at: \(Self.isoFormatter.string(from: updatedAt))\n"
        if isPinned {
            fm += "pinned: true\n"
        }
        if !tags.isEmpty {
            let tagsJoined = tags.map { "\"\($0)\"" }.joined(separator: ", ")
            fm += "tags: [\(tagsJoined)]\n"
        }
        fm += "---\n\n"
        return fm + content
    }
    
    /// Splits `---` delimited frontmatter from the body without altering the body. The closing
    /// delimiter must be a line of its own, so "---" inside a title or the body is never mistaken for it.
    /// Returns nil when the text has no complete frontmatter block.
    static func splitFrontmatter(_ raw: String) -> (yaml: String, body: String)? {
        guard raw.hasPrefix("---") else { return nil }
        var cursor = raw.startIndex
        func nextLine() -> (text: Substring, next: String.Index)? {
            guard cursor < raw.endIndex else { return nil }
            if let newline = raw[cursor...].firstIndex(of: "\n") {
                return (raw[cursor..<newline], raw.index(after: newline))
            }
            return (raw[cursor...], raw.endIndex)
        }
        func isDelimiter(_ line: Substring) -> Bool {
            line.trimmingCharacters(in: .whitespaces) == "---"
        }
        
        guard let opening = nextLine(), isDelimiter(opening.text) else { return nil }
        cursor = opening.next
        let yamlStart = cursor
        while let line = nextLine() {
            if isDelimiter(line.text) {
                let yaml = String(raw[yamlStart..<cursor])
                var body = raw[line.next...]
                // serializeToMarkdown writes one blank line between the frontmatter and the body
                if body.hasPrefix("\r\n") { body = body.dropFirst(2) }
                else if body.hasPrefix("\n") { body = body.dropFirst() }
                return (yaml, String(body))
            }
            cursor = line.next
        }
        return nil
    }
    
    static func escapeYAML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
    
    static func unescapeYAML(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\", let escaped = iterator.next() else {
                result.append(ch)
                continue
            }
            switch escaped {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "\"", "\\": result.append(escaped)
            default:
                // Not an escape we wrote: keep as is, e.g. files edited by hand
                result.append(ch)
                result.append(escaped)
            }
        }
        return result
    }
    
    public static func parse(from rawContent: String, fileURL: URL? = nil) -> Note {
        var id = UUID()
        var title = ""
        var categoryType = CategoryType.inbox
        var targetName: String? = nil
        var createdAt = Date()
        var updatedAt = Date()
        var tags: [String] = []
        var isPinned = false
        var markdownBody = rawContent
        
        if let (yaml, body) = Self.splitFrontmatter(rawContent) {
            markdownBody = body
            
            // Split on "\n" only: titles may hold other Unicode line separators that `.newlines` would cut at
            let lines = yaml.components(separatedBy: "\n")
            for line in lines {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2 else { continue }
                let key = parts[0]
                var val = parts[1]
                if val.hasPrefix("\"") && val.hasSuffix("\"") && val.count >= 2 {
                    val = Self.unescapeYAML(String(val.dropFirst().dropLast()))
                }
                
                switch key {
                case "id":
                    if let parsedUUID = UUID(uuidString: val) { id = parsedUUID }
                case "title":
                    title = val
                case "type":
                    if let type = CategoryType(rawValue: val) { categoryType = type }
                case "target":
                    targetName = val
                case "pinned":
                    isPinned = (val.lowercased() == "true")
                case "created_at":
                    if let date = isoFormatter.date(from: val) ?? fallbackIsoFormatter.date(from: val) {
                        createdAt = date
                    }
                case "updated_at":
                    if let date = isoFormatter.date(from: val) ?? fallbackIsoFormatter.date(from: val) {
                        updatedAt = date
                    }
                case "tags":
                    let cleaned = val.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    tags = cleaned.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                          .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    }.filter { !$0.isEmpty }
                default:
                    break
                }
            }
        }
        
        // If fileURL is provided and dates weren't in frontmatter, infer from file attributes
        if let url = fileURL {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                if let modDate = attrs[.modificationDate] as? Date, updatedAt == createdAt {
                    updatedAt = modDate
                }
                if let creatDate = attrs[.creationDate] as? Date, createdAt == updatedAt {
                    createdAt = creatDate
                }
            }
        }
        
        var note = Note(
            id: id,
            title: title,
            content: markdownBody,
            categoryType: categoryType,
            targetName: targetName,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: tags,
            filePath: fileURL,
            isPinned: isPinned
        )
        
        // Ensure note title is populated if blank
        if note.title.isEmpty {
            note.title = note.displayTitle
        }
        
        return note
    }
}

// MARK: - Inline Project Tag Cleansing
extension Note {
    /// Removes inline project tags (e.g. `@project`, `+project`, `p:project`, `[[project]]`)
    /// from the note content so the body text remains clean and concise.
    public static func removeProjectTag(from text: String, targetName: String?) -> String {
        guard let target = targetName?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty else {
            return text
        }
        
        let escapedRaw = NSRegularExpression.escapedPattern(for: target)
        let noSpace = target.replacingOccurrences(of: " ", with: "")
        let escapedNoSpace = NSRegularExpression.escapedPattern(for: noSpace)
        let noPunct = target
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        let escapedNoPunct = NSRegularExpression.escapedPattern(for: noPunct)
        
        var targetPatterns = [escapedRaw, escapedNoSpace, escapedNoPunct]
        targetPatterns = Array(Set(targetPatterns))
        let targetRegexPart = targetPatterns.joined(separator: "|")
        
        var lines = text.components(separatedBy: .newlines)
        
        guard let p1 = try? NSRegularExpression(pattern: "^(?:@|\\+|p:)(?:" + targetRegexPart + ")(?::\\s*|\\s+)", options: .caseInsensitive),
              let p2 = try? NSRegularExpression(pattern: "\\s+(?:@|\\+|p:)(?:" + targetRegexPart + ")([.,;:])(?=\\s|$)", options: .caseInsensitive),
              let p3 = try? NSRegularExpression(pattern: "\\s+(?:@|\\+|p:)(?:" + targetRegexPart + ")(?=[.,;:]?(\\s|$))", options: .caseInsensitive),
              let p4 = try? NSRegularExpression(pattern: "^(?:@|\\+|p:)(?:" + targetRegexPart + ")[.,;:]?$", options: .caseInsensitive),
              let pWiki = try? NSRegularExpression(pattern: "\\[\\[(?:" + targetRegexPart + ")\\]\\]", options: .caseInsensitive) else {
            return text
        }
        
        for i in 0..<lines.count {
            var line = lines[i]
            line = pWiki.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
            line = p4.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
            line = p1.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
            line = p2.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "$1")
            line = p3.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
            line = line.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            lines[i] = line.trimmingCharacters(in: .whitespaces)
        }
        
        while lines.first?.isEmpty == true && lines.count > 1 {
            lines.removeFirst()
        }
        while lines.last?.isEmpty == true && lines.count > 1 {
            lines.removeLast()
        }
        
        return lines.joined(separator: "\n")
    }
}
