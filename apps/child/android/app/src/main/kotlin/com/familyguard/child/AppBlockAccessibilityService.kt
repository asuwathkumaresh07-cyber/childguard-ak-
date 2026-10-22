package com.familyguard.child

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.view.accessibility.AccessibilityEvent
import java.util.Calendar
import java.util.concurrent.ConcurrentHashMap

class AppBlockAccessibilityService : AccessibilityService() {
    private val activityDatabase by lazy { ActivityLogDatabase(applicationContext) }
    private val handler = Handler(Looper.getMainLooper())
    private val dailyLimitCache = mutableMapOf<String, Pair<Long, Boolean>>()
    private var foregroundPackage: String? = null
    private var foregroundStartedAt: Long = 0L
    private val usageCheckpoint = object : Runnable {
        override fun run() {
            val currentPackage = foregroundPackage
            flushForegroundUsage()
            if (currentPackage != null) {
                foregroundPackage = currentPackage
                foregroundStartedAt = System.currentTimeMillis()
            }
            if (isEnabled) handler.postDelayed(this, USAGE_CHECKPOINT_MS)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) return
        val pkg = event.packageName?.toString() ?: return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            pkg != foregroundPackage
        ) {
            flushForegroundUsage()
            if (pkg != packageName && isTrackablePackage(pkg)) {
                reportForegroundPackage(pkg)
            }
        }
        if (pkg == packageName) return
        if (!blockedPackages.contains(pkg) && !isOverDailyLimit(pkg)) {
            if (foregroundPackage == null && isTrackablePackage(pkg)) {
                foregroundPackage = pkg
                foregroundStartedAt = System.currentTimeMillis()
            }
            return
        }

        // Send user to home screen when a blocked app opens
        performGlobalAction(GLOBAL_ACTION_HOME)
        val intent = Intent(this, BlockedAppActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(BlockedAppActivity.EXTRA_PACKAGE, pkg)
        startActivity(intent)
    }

    override fun onInterrupt() {
        flushForegroundUsage()
    }

    companion object {
        private const val USAGE_CHECKPOINT_MS = 60_000L
        private const val LIMIT_CHECK_CACHE_MS = 5_000L
        val blockedPackages: MutableSet<String> = ConcurrentHashMap.newKeySet()
        val dailyLimitsSeconds: MutableMap<String, Int> = ConcurrentHashMap()

        @Volatile
        var isEnabled: Boolean = false

        fun restoreBlockedPackages(context: android.content.Context) {
            blockedPackages.clear()
            blockedPackages.addAll(ActivityLogDatabase.loadBlockedApps(context))
            updateDailyLimits(context, ActivityLogDatabase.loadDailyAppLimits(context))
        }

        fun updateDailyLimits(context: Context, limits: Map<String, Int>) {
            dailyLimitsSeconds.clear()
            dailyLimitsSeconds.putAll(limits)
            ActivityLogDatabase.saveDailyAppLimits(context, limits)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        restoreBlockedPackages(this)
        isEnabled = true
        handler.postDelayed(usageCheckpoint, USAGE_CHECKPOINT_MS)
    }

    override fun onDestroy() {
        handler.removeCallbacks(usageCheckpoint)
        flushForegroundUsage()
        isEnabled = false
        super.onDestroy()
    }

    private fun isTrackablePackage(pkg: String): Boolean {
        if (pkg == packageName) return false
        return try {
            val app = packageManager.getApplicationInfo(pkg, 0)
            app.flags and ApplicationInfo.FLAG_SYSTEM == 0
        } catch (_: Exception) {
            false
        }
    }

    private fun isOverDailyLimit(pkg: String): Boolean {
        val limitSeconds = dailyLimitsSeconds[pkg] ?: return false
        val now = System.currentTimeMillis()
        dailyLimitCache[pkg]?.let { (checkedAt, exceeded) ->
            if (now - checkedAt < LIMIT_CHECK_CACHE_MS) return exceeded
        }
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val permission = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )
        if (permission != AppOpsManager.MODE_ALLOWED) return false

        val startOfDay = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val usageManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val secondsUsed = try {
            usageManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startOfDay,
                now,
            ).asSequence()
                .filter { it.packageName == pkg }
                .sumOf { it.totalTimeInForeground } / 1000L
        } catch (_: Exception) {
            return false
        }
        val exceeded = secondsUsed >= limitSeconds
        dailyLimitCache[pkg] = now to exceeded
        return exceeded
    }

    private fun flushForegroundUsage() {
        val pkg = foregroundPackage ?: return
        val startedAt = foregroundStartedAt
        val endedAt = System.currentTimeMillis()
        val durationSeconds = ((endedAt - startedAt) / 1000L).toInt()
        foregroundPackage = null
        foregroundStartedAt = 0L
        if (durationSeconds <= 0) return

        val label = try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(pkg, 0),
            ).toString()
        } catch (_: Exception) {
            pkg
        }
        try {
            activityDatabase.recordUsage(
                pkg,
                label,
                startedAt,
                endedAt,
                durationSeconds,
            )
            ProtectionVpnService.usageSink?.invoke(
                mapOf(
                    "packageName" to pkg,
                    "appLabel" to label,
                    "startedAt" to startedAt,
                    "endedAt" to endedAt,
                    "durationSeconds" to durationSeconds,
                ),
            )
        } catch (e: Exception) {
            android.util.Log.e(
                "FamilyGuardAccessibility",
                "Could not persist app usage for $pkg",
                e,
            )
        }
    }

    private fun reportForegroundPackage(pkg: String) {
        val label = try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(pkg, 0),
            ).toString()
        } catch (_: Exception) {
            pkg
        }
        val now = System.currentTimeMillis()
        ProtectionVpnService.usageSink?.invoke(
            mapOf(
                "packageName" to pkg,
                "appLabel" to label,
                "startedAt" to now,
                "endedAt" to now,
                "durationSeconds" to 0,
            ),
        )
    }
}
