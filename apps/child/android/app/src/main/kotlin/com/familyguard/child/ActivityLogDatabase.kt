package com.familyguard.child

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

class ActivityLogDatabase(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE domain_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id TEXT NOT NULL UNIQUE,
                domain TEXT NOT NULL,
                action TEXT NOT NULL,
                occurred_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE app_usage_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id TEXT NOT NULL UNIQUE,
                package_name TEXT NOT NULL,
                app_label TEXT NOT NULL,
                started_at INTEGER NOT NULL,
                ended_at INTEGER NOT NULL,
                duration_seconds INTEGER NOT NULL
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun recordDomain(domain: String, action: String, occurredAt: Long): String {
        val eventId = java.util.UUID.randomUUID().toString()
        writableDatabase.insertOrThrow(
            "domain_events",
            null,
            ContentValues().apply {
                put("event_id", eventId)
                put("domain", domain)
                put("action", action)
                put("occurred_at", occurredAt)
            },
        )
        return eventId
    }

    fun recordUsage(
        packageName: String,
        appLabel: String,
        startedAt: Long,
        endedAt: Long,
        durationSeconds: Int,
    ): String {
        val eventId = java.util.UUID.randomUUID().toString()
        writableDatabase.insertOrThrow(
            "app_usage_events",
            null,
            ContentValues().apply {
                put("event_id", eventId)
                put("package_name", packageName)
                put("app_label", appLabel)
                put("started_at", startedAt)
                put("ended_at", endedAt)
                put("duration_seconds", durationSeconds)
            },
        )
        return eventId
    }

    fun pendingDomains(): List<Map<String, Any>> =
        readableDatabase.rawQuery(
            """
            SELECT id, event_id, domain, action, occurred_at
            FROM domain_events ORDER BY id LIMIT 200
            """.trimIndent(),
            null,
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(
                        mapOf(
                            "id" to cursor.getLong(0),
                            "eventId" to cursor.getString(1),
                            "domain" to cursor.getString(2),
                            "action" to cursor.getString(3),
                            "occurredAt" to cursor.getLong(4),
                        ),
                    )
                }
            }
        }

    fun pendingUsage(): List<Map<String, Any>> =
        readableDatabase.rawQuery(
            """
            SELECT id, event_id, package_name, app_label, started_at, ended_at, duration_seconds
            FROM app_usage_events ORDER BY id LIMIT 200
            """.trimIndent(),
            null,
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    add(
                        mapOf(
                            "id" to cursor.getLong(0),
                            "eventId" to cursor.getString(1),
                            "packageName" to cursor.getString(2),
                            "appLabel" to cursor.getString(3),
                            "startedAt" to cursor.getLong(4),
                            "endedAt" to cursor.getLong(5),
                            "durationSeconds" to cursor.getInt(6),
                        ),
                    )
                }
            }
        }

    fun acknowledge(table: String, ids: List<Long>) {
        val allowedTable = when (table) {
            "domain_events", "app_usage_events" -> table
            else -> throw IllegalArgumentException("Unsupported activity table")
        }
        if (ids.isEmpty()) return
        writableDatabase.beginTransaction()
        try {
            ids.forEach { id ->
                writableDatabase.delete(allowedTable, "id = ?", arrayOf(id.toString()))
            }
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
    }

    companion object {
        private const val DATABASE_NAME = "family_guard_activity.db"
        private const val DATABASE_VERSION = 1
        private const val PREFS_NAME = "family_guard_protection"
        private const val VPN_ENABLED = "vpn_enabled"
        private const val BLOCKED_DOMAINS = "blocked_domains"
        private const val BLOCKED_APPS = "blocked_apps"
        private const val DAILY_APP_LIMITS = "daily_app_limits"

        fun saveProtectionState(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(VPN_ENABLED, enabled)
                .apply()
        }

        fun isProtectionEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(VPN_ENABLED, false)

        fun saveBlockedDomains(context: Context, domains: Collection<String>) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(BLOCKED_DOMAINS, domains.toSet())
                .apply()
        }

        fun loadBlockedDomains(context: Context): Set<String> =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getStringSet(BLOCKED_DOMAINS, emptySet())
                ?.toSet()
                ?: emptySet()

        fun saveBlockedApps(context: Context, packages: Collection<String>) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(BLOCKED_APPS, packages.toSet())
                .apply()
        }

        fun loadBlockedApps(context: Context): Set<String> =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getStringSet(BLOCKED_APPS, emptySet())
                ?.toSet()
                ?: emptySet()

        fun saveDailyAppLimits(context: Context, limits: Map<String, Int>) {
            val json = JSONObject()
            limits.forEach { (packageName, seconds) -> json.put(packageName, seconds) }
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(DAILY_APP_LIMITS, json.toString())
                .apply()
        }

        fun loadDailyAppLimits(context: Context): Map<String, Int> {
            val encoded = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(DAILY_APP_LIMITS, null)
                ?: return emptyMap()
            return try {
                val json = JSONObject(encoded)
                buildMap {
                    val keys = json.keys()
                    while (keys.hasNext()) {
                        val packageName = keys.next()
                        put(packageName, json.getInt(packageName))
                    }
                }
            } catch (_: Exception) {
                emptyMap()
            }
        }
    }
}
