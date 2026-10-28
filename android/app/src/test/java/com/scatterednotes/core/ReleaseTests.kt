package com.scatterednotes.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReleaseTests {
    private fun json(tag: String, apk: Boolean = true, prerelease: Boolean = false) = """
        {"tag_name": "$tag", "draft": false, "prerelease": $prerelease,
         "body": "| Computer | Download |\r\n|---|---|\r\n\r\n### Android\r\n- Faster search",
         "assets": [
           {"name": "ScatteredNotes-1.1.5-mac.zip", "browser_download_url": "https://example.com/mac.zip"}
           ${if (apk) """, {"name": "ScatteredNotes-1.1.5-android.apk", "browser_download_url": "https://example.com/app.apk"}""" else ""}
         ]}
    """

    @Test
    fun readsTheAndroidDownloadAndDropsTheDownloadTable() {
        val release = Release.parse(json("v1.1.5"))!!
        assertEquals(listOf(1, 1, 5), release.version)
        assertEquals("https://example.com/app.apk", release.apkUrl)
        assertEquals("### Android\n- Faster search", release.notes)
    }

    @Test
    fun ignoresReleasesWithoutAnApkAndPreReleases() {
        assertNull(Release.parse(json("v1.1.5", apk = false)))
        assertNull(Release.parse(json("v1.1.5", prerelease = true)))
        assertNull(Release.parse(json("nightly")))
    }

    @Test
    fun offersOnlyNewerVersionsThatWereNotSkipped() {
        val release = Release.parse(json("v1.1.5"))!!
        assertTrue(release.isUpdate("1.1.4", skipped = null))
        assertTrue(release.isUpdate("1.1", skipped = "1.1.4"))
        assertFalse(release.isUpdate("1.1.5", skipped = null))
        assertFalse(release.isUpdate("1.2.0", skipped = null))
        assertFalse(release.isUpdate("1.1.4", skipped = "v1.1.5"))
    }
}
