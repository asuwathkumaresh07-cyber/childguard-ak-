package com.familyguard.child

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class ProtectionBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED &&
            intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        if (!ActivityLogDatabase.isProtectionEnabled(context)) return

        AppBlockAccessibilityService.restoreBlockedPackages(context)
        val serviceIntent = Intent(context, ProtectionVpnService::class.java)
            .setAction(ProtectionVpnService.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
