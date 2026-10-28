package com.scatterednotes.core

import com.scatterednotes.ui.projectNamed
import com.scatterednotes.ui.withoutProjectMark
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same cases as the Mac app's MentionsTests. */
class MentionsTests {
    @Test
    fun findsPeopleTagsAndProjectsAtTheStartOfWords() {
        val text = "Call @Ana about +Website (#idea), then #idea again and @ana."
        assertEquals(listOf("Ana"), Mentions.names(Mentions.Kind.PERSON, text))
        assertEquals(listOf("idea"), Mentions.names(Mentions.Kind.TAG, text))
        assertEquals(listOf("Website"), Mentions.names(Mentions.Kind.PROJECT, text))
    }

    @Test
    fun ignoresSymbolsThatAreNotMarks() {
        assertTrue(Mentions.marks("Mail ana@example.com about C# and +91 98450 for #1 ~5 min, x+y").isEmpty())
    }

    @Test
    fun namesKeepDashesDotsAndDigitsButNotATrailingDot() {
        assertEquals(listOf("home-office", "v2.1", "done"), Mentions.names(Mentions.Kind.TAG, "#home-office #v2.1 #done."))
    }

    @Test
    fun noteTagsAndPeopleComeFromItsText() {
        val note = NoteFormat.parse("---\ntags: [\"old\"]\n---\n\nPing @sam #new")
        assertEquals(listOf("old", "new"), note.tags)
        assertEquals(listOf("sam"), note.people)
    }

    @Test
    fun areaNamesBecomeTagNames() {
        assertEquals("home-office", Mentions.tagNameForArea("Home Office"))
        assertEquals("area-2026-goals", Mentions.tagNameForArea("2026 Goals"))
    }

    @Test
    fun captureFilesUnderThePlusProject() {
        val projects = listOf(ProjectArea("Scattered Notes", CategoryType.PROJECT))
        assertEquals("Scattered Notes", projectNamed("fix sync +scatterednotes", projects))
        assertEquals("Garden", projectNamed("plan +garden beds", projects))
        assertNull(projectNamed("ask @ana about #garden", projects))
        assertEquals("plan beds #spring", withoutProjectMark("plan +garden beds #spring"))
    }
}
