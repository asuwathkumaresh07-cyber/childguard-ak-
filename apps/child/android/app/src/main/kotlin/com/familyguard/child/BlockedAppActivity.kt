package com.familyguard.child

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

class BlockedAppActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pkg = intent.getStringExtra(EXTRA_PACKAGE) ?: "App"
        val tv = TextView(this).apply {
            text = "Blocked by Family Guard\n\n$pkg"
            textSize = 18f
            setPadding(48, 120, 48, 48)
        }
        setContentView(tv)
    }

    companion object {
        const val EXTRA_PACKAGE = "package"
    }
}
