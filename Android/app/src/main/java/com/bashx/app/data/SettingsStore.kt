package com.bashx.app.data

import kotlinx.serialization.json.Json

object SettingsStore {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun load(): AppSettings {
        val file = Paths.settingsFile
        if (!file.exists()) return AppSettings()
        return runCatching {
            json.decodeFromString<AppSettings>(file.readText())
        }.getOrDefault(AppSettings())
    }

    fun save(settings: AppSettings): Boolean = runCatching {
        Paths.settingsFile.writeText(json.encodeToString(AppSettings.serializer(), settings))
        true
    }.getOrDefault(false)
}
