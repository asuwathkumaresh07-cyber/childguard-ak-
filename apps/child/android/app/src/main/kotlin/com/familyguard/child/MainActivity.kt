package com.familyguard.child

import android.Manifest
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.familyguard.child/protection"
    private val domainChannelName = "com.familyguard.child/domain_events"
    private val usageChannelName = "com.familyguard.child/usage_events"

    private var domainSink: EventChannel.EventSink? = null
    private var usageSink: EventChannel.EventSink? = null
    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null
    private lateinit var activityDatabase: ActivityLogDatabase
    private lateinit var usageMonitor: UsageMonitor

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        activityDatabase = ActivityLogDatabase(applicationContext)
        usageMonitor = UsageMonitor(applicationContext)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, domainChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    domainSink = events
                    ProtectionVpnService.domainSink = { domain, action ->
                        runOnUiThread {
                            domainSink?.success(
                                mapOf("domain" to domain, "action" to action),
                            )
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    domainSink = null
                    ProtectionVpnService.domainSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, usageChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    usageSink = events
                    ProtectionVpnService.usageSink = { map ->
                        runOnUiThread { usageSink?.success(map) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    usageSink = null
                    ProtectionVpnService.usageSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            pendingNotificationResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_NOTIFICATIONS,
                            )
                        } else {
                            result.success(true)
                        }
                    }
                    "prepareVpn" -> {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            pendingVpnResult = result
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, REQ_VPN)
                        } else {
                            result.success(true)
                        }
                    }
                    "startVpn" -> {
                        val domains = call.argument<List<String>>("blockedDomains") ?: emptyList()
                        ActivityLogDatabase.saveBlockedDomains(this, domains)
                        val intent = Intent(this, ProtectionVpnService::class.java)
                            .setAction(ProtectionVpnService.ACTION_START)
                            .putStringArrayListExtra(
                                ProtectionVpnService.EXTRA_DOMAINS,
                                ArrayList(domains),
                            )
                        startForegroundService(intent)
                        result.success(null)
                    }
                    "stopVpn" -> {
                        val intent = Intent(this, ProtectionVpnService::class.java)
                            .setAction(ProtectionVpnService.ACTION_STOP)
                        startService(intent)
                        result.success(null)
                    }
                    "updateBlockList" -> {
                        val domains = call.argument<List<String>>("blockedDomains") ?: emptyList()
                        ProtectionVpnService.blockedDomains.clear()
                        domains.forEach {
                            ProtectionVpnService.blockedDomains.add(
                                ProtectionVpnService.normalize(it),
                            )
                        }
                        ActivityLogDatabase.saveBlockedDomains(this, domains)
                        if (ProtectionVpnService.isRunning) {
                            val intent = Intent(this, ProtectionVpnService::class.java)
                                .setAction(ProtectionVpnService.ACTION_UPDATE)
                                .putStringArrayListExtra(
                                    ProtectionVpnService.EXTRA_DOMAINS,
                                    ArrayList(domains),
                                )
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "updateBlockedApps" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        AppBlockAccessibilityService.blockedPackages.clear()
                        AppBlockAccessibilityService.blockedPackages.addAll(packages)
                        ActivityLogDatabase.saveBlockedApps(this, packages)
                        result.success(null)
                    }
                    "updateDailyAppLimits" -> {
                        val limits = call.argument<Map<String, Number>>("limits")
                            ?.mapValues { it.value.toInt().coerceAtLeast(1) }
                            ?: emptyMap()
                        AppBlockAccessibilityService.updateDailyLimits(
                            this,
                            limits,
                        )
                        result.success(null)
                    }
                    "isVpnRunning" -> result.success(ProtectionVpnService.isRunning)
                    "hasUsagePermission" -> result.success(usageMonitor.hasPermission())
                    "openUsageAccessSettings" -> {
                        usageMonitor.openSettings()
                        result.success(null)
                    }
                    "openAppDetailsSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.fromParts("package", packageName, null)),
                        )
                        result.success(null)
                    }
                    "getPendingDomainEvents" ->
                        result.success(activityDatabase.pendingDomains())
                    "getPendingUsageEvents" ->
                        result.success(activityDatabase.pendingUsage())
                    "acknowledgeDomainEvents" -> {
                        val ids = call.argument<List<Number>>("ids")
                            ?.map { it.toLong() }
                            ?: emptyList()
                        activityDatabase.acknowledge("domain_events", ids)
                        result.success(null)
                    }
                    "acknowledgeUsageEvents" -> {
                        val ids = call.argument<List<Number>>("ids")
                            ?.map { it.toLong() }
                            ?: emptyList()
                        activityDatabase.acknowledge("app_usage_events", ids)
                        result.success(null)
                    }
                    "hasAccessibilityPermission" ->
                        result.success(isAccessibilityEnabled())
                    "openAccessibilitySettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val am = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabled = am.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_ALL_MASK,
        )
        val expected = "$packageName/.AppBlockAccessibilityService"
        return enabled.any { info ->
            val id = info.resolveInfo.serviceInfo.let { "${it.packageName}/${it.name}" }
            id.contains("AppBlockAccessibilityService") || id == expected
        } || AppBlockAccessibilityService.isEnabled
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN) {
            pendingVpnResult?.success(resultCode == RESULT_OK)
            pendingVpnResult = null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIFICATIONS) {
            pendingNotificationResult?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            pendingNotificationResult = null
        }
    }

    companion object {
        private const val REQ_VPN = 1001
        private const val REQ_NOTIFICATIONS = 1002
    }
}
