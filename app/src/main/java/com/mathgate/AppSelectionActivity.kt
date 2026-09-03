package com.mathgate

import android.app.Activity
import android.content.Intent
import android.content.pm.ResolveInfo
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

/** Launcher-app picker, copied from AnkGate (minus the UsageStats ordering, which needs a permission). */
class AppSelectionActivity : Activity() {

    companion object {
        private val POPULAR_PACKAGES = listOf(
            "com.instagram.android",
            "com.google.android.youtube",
            "com.twitter.android",
            "com.zhiliaoapp.musically", // TikTok
            "com.snapchat.android",
            "com.reddit.frontpage",
            "com.facebook.katana",
            "com.facebook.orca", // Messenger
            "com.whatsapp",
            "com.discord",
            "com.linkedin.android",
        )
    }

    private val selected = mutableSetOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_app_selection)
        selected.addAll(Prefs.getBlockedPackages(this))

        val rv = findViewById<RecyclerView>(R.id.rvApps)
        rv.layoutManager = LinearLayoutManager(this)
        rv.adapter = AppAdapter(buildAppList())

        findViewById<View>(R.id.btnBack).setOnClickListener { finish() }
        findViewById<View>(R.id.btnSave).setOnClickListener {
            Prefs.setBlockedPackages(this, selected)
            finish()
        }
    }

    private fun buildAppList(): List<ListItem> {
        val pm = packageManager
        val launchIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val installed = linkedMapOf<String, ResolveInfo>()
        for (ri in pm.queryIntentActivities(launchIntent, 0)) {
            val pkg = ri.activityInfo.packageName
            if (pkg != packageName) installed[pkg] = ri
        }

        val items = mutableListOf<ListItem>()
        val popular = POPULAR_PACKAGES.filter { it in installed }
        if (popular.isNotEmpty()) {
            items.add(ListItem.Header("Popular"))
            popular.forEach { pkg -> items.add(appItem(pkg, installed.getValue(pkg))) }
        }
        val others = (installed.keys - popular.toSet()).sortedBy { installed.getValue(it).loadLabel(pm).toString().lowercase() }
        if (others.isNotEmpty()) {
            items.add(ListItem.Header("All Apps"))
            others.forEach { pkg -> items.add(appItem(pkg, installed.getValue(pkg))) }
        }
        return items
    }

    private fun appItem(pkg: String, ri: ResolveInfo) = ListItem.App(
        packageName = pkg,
        label = ri.loadLabel(packageManager).toString(),
        icon = ri.loadIcon(packageManager),
    )

    sealed class ListItem {
        data class Header(val title: String) : ListItem()
        data class App(val packageName: String, val label: String, val icon: Drawable) : ListItem()
    }

    private inner class AppAdapter(private val items: List<ListItem>) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        private val typeHeader = 0
        private val typeApp = 1

        inner class HeaderVH(view: View) : RecyclerView.ViewHolder(view) {
            val tv: TextView = view as TextView
        }

        inner class AppVH(view: View) : RecyclerView.ViewHolder(view) {
            val icon: ImageView = view.findViewById(R.id.ivIcon)
            val label: TextView = view.findViewById(R.id.tvAppName)
            val cb: CheckBox = view.findViewById(R.id.cbApp)
        }

        override fun getItemViewType(position: Int) = when (items[position]) {
            is ListItem.Header -> typeHeader
            is ListItem.App -> typeApp
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            return if (viewType == typeHeader) {
                HeaderVH(
                    TextView(parent.context).apply {
                        textSize = 11f
                        setTextColor(0xFF6B6B6B.toInt())
                        setPadding(dp(20), dp(16), dp(20), dp(8))
                        letterSpacing = 0.1f
                        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                    },
                )
            } else {
                AppVH(LayoutInflater.from(parent.context).inflate(R.layout.item_app, parent, false))
            }
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            when (val item = items[position]) {
                is ListItem.Header -> (holder as HeaderVH).tv.text = item.title
                is ListItem.App -> {
                    val h = holder as AppVH
                    h.icon.setImageDrawable(item.icon)
                    h.label.text = item.label
                    h.cb.isChecked = item.packageName in selected
                    h.itemView.setOnClickListener {
                        if (!selected.remove(item.packageName)) selected.add(item.packageName)
                        h.cb.isChecked = item.packageName in selected
                    }
                }
            }
        }

        override fun getItemCount() = items.size

        private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
    }
}
