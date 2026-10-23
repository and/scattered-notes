import SwiftUI

public struct MarkdownRendererView: View {
    @Binding var content: String
    var onToggleChecklist: ((Int) -> Void)?
    
    public init(content: Binding<String>, onToggleChecklist: ((Int) -> Void)? = nil) {
        self._content = content
        self.onToggleChecklist = onToggleChecklist
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let lines = content.components(separatedBy: .newlines)
                ForEach(0..<lines.count, id: \.self) { index in
                    renderLine(lines[index], lineIndex: index)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private func renderLine(_ line: String, lineIndex: Int) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("# ") {
            Text(trimmed.dropFirst(2))
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 8)
        } else if trimmed.hasPrefix("## ") {
            Text(trimmed.dropFirst(3))
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 6)
        } else if trimmed.hasPrefix("### ") {
            Text(trimmed.dropFirst(4))
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 4)
        } else if isChecklist(trimmed) {
            renderChecklistLine(line, lineIndex: lineIndex)
        } else if trimmed.hasPrefix("> ") {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.wcagBlue)
                    .frame(width: 4)
                Text(trimmed.dropFirst(2))
                    .italic()
                    .foregroundColor(.wcagSecondaryText)
            }
            .padding(.vertical, 2)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.body)
                    .foregroundColor(.wcagBlue)
                Text(trimmed.dropFirst(2))
                    .font(.body)
            }
        } else if trimmed.hasPrefix("```") {
            Text(trimmed)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.wcagSecondaryText)
        } else if !trimmed.isEmpty {
            // Standard line with inline markdown formatting support
            Text(parseInlineMarkdown(trimmed))
                .font(.system(size: 14))
                .lineSpacing(4)
        } else {
            Spacer().frame(height: 6)
        }
    }
    
    private func isChecklist(_ line: String) -> Bool {
        return line.hasPrefix("- [ ]") || line.hasPrefix("- [x]") || line.hasPrefix("- [X]") ||
               line.hasPrefix("* [ ]") || line.hasPrefix("* [x]") || line.hasPrefix("* [X]")
    }
    
    @ViewBuilder
    private func renderChecklistLine(_ line: String, lineIndex: Int) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isChecked = trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") ||
                        trimmed.hasPrefix("* [x]") || trimmed.hasPrefix("* [X]")
        let textIndex = trimmed.index(trimmed.startIndex, offsetBy: 5)
        let taskText = String(trimmed[textIndex...]).trimmingCharacters(in: .whitespaces)
        
        HStack(spacing: 8) {
            Button(action: {
                toggleLineCheck(lineIndex: lineIndex)
            }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .wcagBlue : .wcagSecondaryText)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            
            Text(parseInlineMarkdown(taskText))
                .font(.system(size: 14))
                .strikethrough(isChecked, color: .wcagSecondaryText)
                .foregroundColor(isChecked ? .wcagSecondaryText : .primary)
        }
        .padding(.vertical, 1)
    }
    
    private func toggleLineCheck(lineIndex: Int) {
        var lines = content.components(separatedBy: .newlines)
        guard lineIndex < lines.count else { return }
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
        }
        
        content = lines.joined(separator: "\n")
        onToggleChecklist?(lineIndex)
    }
    
    private func parseInlineMarkdown(_ string: String) -> AttributedString {
        if let attr = try? AttributedString(markdown: string) {
            return attr
        }
        return AttributedString(string)
    }
}
