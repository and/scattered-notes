package com.scatterednotes.core

import org.json.JSONObject

/**
 * A GitHub release, as far as the updater needs it. Mirrors the Mac app's `Release`: the Android
 * download is the asset named `ScatteredNotes-<version>-android.apk`, and the notes leave out the
 * download table, which only matters on the website.
 */
data class Release(val tag: String, val version: List<Int>, val notes: String, val apkUrl: String) {
    /** Whether this release should be offered to an app running [installed], unless the user skipped it. */
    fun isUpdate(installed: String, skipped: String?): Boolean {
        val current = parseVersion(installed) ?: return false
        if (compare(version, current) <= 0) return false
        return skipped?.let(::parseVersion)?.let { compare(it, version) != 0 } ?: true
    }

    companion object {
        /** The release in GitHub's `releases/latest` JSON, or null for drafts, pre-releases and releases without an APK. */
        fun parse(json: String): Release? {
            val root = JSONObject(json)
            if (root.optBoolean("draft") || root.optBoolean("prerelease")) return null
            val tag = root.optString("tag_name")
            val version = parseVersion(tag) ?: return null
            val assets = root.optJSONArray("assets") ?: return null
            val apk = (0 until assets.length()).map { assets.getJSONObject(it) }
                .firstOrNull { it.optString("name").lowercase().endsWith("-android.apk") } ?: return null
            val notes = root.optString("body").replace("\r\n", "\n").lines()
                .filterNot { it.trim().startsWith("|") }
                .joinToString("\n").trim()
            return Release(tag, version, notes, apk.getString("browser_download_url"))
        }

        /** "v1.2.3" or "1.2.3" as [1, 2, 3]; null when it isn't a version number. */
        fun parseVersion(text: String): List<Int>? {
            val parts = text.trim().removePrefix("v").split(".")
            return parts.map { it.toIntOrNull() ?: return null }.takeIf { it.isNotEmpty() }
        }

        fun compare(a: List<Int>, b: List<Int>): Int {
            for (i in 0 until maxOf(a.size, b.size)) {
                val diff = a.getOrElse(i) { 0 } - b.getOrElse(i) { 0 }
                if (diff != 0) return diff
            }
            return 0
        }
    }
}
