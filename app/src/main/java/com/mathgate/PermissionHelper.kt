package com.mathgate

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils

object PermissionHelper {
    const val LEARN_URL = "https://www.mathacademy.com/learn"

    fun hasAccessibilityPermission(context: Context): Boolean {
        val expected = ComponentName(context, MathGateAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (ComponentName.unflattenFromString(splitter.next()) == expected) return true
        }
        return false
    }

    fun openAccessibilitySettings(activity: Activity) {
        val component = ComponentName(activity, MathGateAccessibilityService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            runCatching {
                activity.startActivity(
                    Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS").apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        data = Uri.parse("package:${component.flattenToString()}")
                    },
                )
                return
            }
        }
        runCatching {
            activity.startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    val args = Bundle().apply { putString(":settings:fragment_args_key", component.flattenToString()) }
                    putExtra(":settings:show_fragment_args", args)
                    putExtra(":settings:fragment_args_key", component.flattenToString())
                },
            )
            return
        }
        activity.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun requestIgnoreBatteryOptimizations(activity: Activity) {
        try {
            activity.startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${activity.packageName}")),
            )
        } catch (e: ActivityNotFoundException) {
            activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    /** Package that would open an https link, or null if unresolvable / only the system chooser. */
    fun defaultBrowserPackage(context: Context): String? {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(LEARN_URL))
        val ri = context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) ?: return null
        val pkg = ri.activityInfo?.packageName ?: return null
        return pkg.takeIf { it != "android" }
    }
}
