package com.scatterednotes.core

import java.time.Instant
import java.util.UUID

enum class CategoryType(val rawValue: String, val displayName: String) {
    INBOX("inbox", "Inbox"),
    PROJECT("project", "Projects"),
    AREA("area", "Areas");

    companion object {
        fun fromRawValue(value: String): CategoryType? = entries.firstOrNull { it.rawValue == value }
    }
}

/** A project or area folder. */
data class ProjectArea(val name: String, val type: CategoryType)

/**
 * A note: a Markdown file with YAML frontmatter, in the format the Mac and Windows apps use.
 * [filePath] is relative to the notes folder, e.g. "Inbox/2026-10-28_Call-the-bank.md".
 */
data class Note(
    val id: UUID = UUID.randomUUID(),
    val title: String = "",
    val content: String = "",
    val categoryType: CategoryType = CategoryType.INBOX,
    val targetName: String? = null,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now(),
    val tags: List<String> = emptyList(),
    val filePath: String? = null,
    val isPinned: Boolean = false,
    /** Frontmatter lines the app does not use, e.g. Obsidian properties, kept as written and saved back unchanged. */
    val extraFrontmatter: String = "",
) {
    /** The ID as the Mac app writes it: an uppercase UUID. */
    val idString: String get() = formatId(id)

    val displayTitle: String
        get() {
            val trimmedTitle = title.trim()
            if (trimmedTitle.isNotEmpty()) return trimmedTitle
            // Fall back to the first non-blank line of the content
            for (line in LineText.split(content)) {
                var trimmed = LineText.trimWhitespace(line.text)
                if (trimmed.startsWith("#")) trimmed = trimmed.trim('#', ' ')
                if (trimmed.isNotEmpty()) return trimmed
            }
            return "Untitled Note"
        }

    val previewExcerpt: String
        get() {
            val heading = displayTitle
            val preview = mutableListOf<String>()
            for (line in LineText.split(content)) {
                val trimmed = LineText.trimWhitespace(line.text)
                // Skip a heading that repeats the title
                if (trimmed.startsWith("#") && trimmed.contains(heading)) continue
                if (trimmed.isEmpty()) continue
                preview.add(trimmed)
                if (preview.size >= 2) break
            }
            return preview.joinToString(" ")
        }

    /** People mentioned as `@name`, in the order they first appear. */
    val people: List<String> get() = Mentions.names(Mentions.Kind.PERSON, content)

    val destinationDisplay: String
        get() = when (categoryType) {
            CategoryType.PROJECT -> targetName ?: "Project"
            CategoryType.AREA -> targetName ?: "Area"
            CategoryType.INBOX -> "Inbox"
        }

    /** Whether saving [other] over this note would change the file. */
    fun hasSameContent(other: Note): Boolean =
        title == other.title && content == other.content && categoryType == other.categoryType &&
            targetName == other.targetName && isPinned == other.isPinned && tags == other.tags

    companion object {
        fun formatId(id: UUID): String = id.toString().uppercase()
    }
}
