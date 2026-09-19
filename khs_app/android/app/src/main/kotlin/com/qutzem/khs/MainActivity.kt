package com.qutzem.khs

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val installChannelName = "khs/install"
    private val vaultChannelName = "khs/vault"
    private val backgroundChannelName = "khs/background"
    private val shortcutChannelName = "khs/shortcut"
    private val startTasksExtra = "khs_start_tasks"
    private val QUTZEM_READER_PACKAGE = "dev.qutzem.qutzem_reader"

    private var shortcutChannel: MethodChannel? = null
    private var pendingVaultResult: MethodChannel.Result? = null
    private var vaultPickRequestCode = 0x0A11

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
                "openInstallSourcesSettings" -> openInstallSourcesSettings()
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            vaultChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                "requestAllFilesAccess" -> requestAllFilesAccess()
                "pickVaultFolder" -> pickVaultFolder(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            backgroundChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" ->
                    requestIgnoreBatteryOptimizations()
                else -> result.notImplemented()
            }
        }
        shortcutChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            shortcutChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "createTasksShortcut" -> {
                        val label = call.argument<String>("label") ?: "KHS Tasks"
                        result.success(createTasksShortcut(label))
                    }
                    "createAppShortcut" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        val label = call.argument<String>("label") ?: pkg
                        result.success(createAppShortcut(pkg, label))
                    }
                    "isPackageInstalled" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        result.success(isPackageInstalled(pkg))
                    }
                    "getPackageVersion" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        result.success(getPackageVersion(pkg))
                    }
                    "launchPackage" -> {
                        val pkg = call.argument<String>("package") ?: ""
                        val fallbackUrl = call.argument<String>("fallbackUrl")
                        result.success(launchPackage(pkg, fallbackUrl))
                    }
                    "getInitialStart" ->
                        result.success(intent?.getStringExtra(startTasksExtra))
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getStringExtra(startTasksExtra) != null) {
            shortcutChannel?.invokeMethod("startTasks", null)
        }
    }

    /** Закрепить ярлык «KHS Tasks» на домашнем экране (Android 8+). */
    private fun createTasksShortcut(label: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val sm = getSystemService(ShortcutManager::class.java) ?: return false
        if (!sm.isRequestPinShortcutSupported) return false
        val launch = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            putExtra(startTasksExtra, "1")
        }
        val info = ShortcutInfo.Builder(this, "khs_tasks")
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(Icon.createWithResource(this, R.drawable.ic_tasks))
            .setIntent(launch)
            .build()
        return sm.requestPinShortcut(info, null)
    }

    /** Пин ярлыка любого установленного приложения (Android 8+), иконка для читалки своя. */
    private fun createAppShortcut(packageName: String, label: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (packageName.isEmpty()) return false
        val sm = getSystemService(ShortcutManager::class.java) ?: return false
        if (!sm.isRequestPinShortcutSupported) return false
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        launch.action = Intent.ACTION_MAIN
        launch.addCategory(Intent.CATEGORY_LAUNCHER)
        launch.setPackage(null)
        val icon = if (packageName == QUTZEM_READER_PACKAGE) {
            Icon.createWithResource(this, R.drawable.ic_qutzem)
        } else {
            return false
        }
        val info = ShortcutInfo.Builder(this, "app_$packageName")
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(icon)
            .setIntent(launch)
            .build()
        return sm.requestPinShortcut(info, null)
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return packageManager.getLaunchIntentForPackage(packageName) != null
    }

    /** Версия установленного пакета (versionName) или null, если не установлен. */
    private fun getPackageVersion(packageName: String): String? {
        if (isPackageInstalled(packageName)) {
            return try {
                packageManager.getPackageInfo(packageName, 0).versionName
            } catch (_: Exception) {
                null
            }
        }
        return null
    }

    private fun launchPackage(packageName: String, fallbackUrl: String?): Boolean {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            try {
                startActivity(launch)
                return true
            } catch (_: Exception) {}
        }
        if (!fallbackUrl.isNullOrEmpty()) {
            try {
                val browser = Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUrl))
                browser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(browser)
            } catch (_: Exception) {}
        }
        return false
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vaultPickRequestCode) {
            val result = pendingVaultResult
            pendingVaultResult = null
            if (result == null) return
            if (resultCode == RESULT_OK && data != null) {
                val real = treeToRealPath(data.data)
                result.success(real)
            } else {
                result.success(null)
            }
        }
    }

    private fun canRequestPackageInstalls(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.canRequestPackageInstalls()
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations()) return
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName")
        )
        try {
            startActivity(intent)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                // Нет подходящего экрана — просто пропускаем.
            }
        }
    }

    private fun openInstallSourcesSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    private fun hasAllFilesAccess(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()
    }

    private fun requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            !Environment.isExternalStorageManager()
        ) {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName")
            )
            try {
                startActivity(intent)
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        }
    }

    private fun pickVaultFolder(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            !Environment.isExternalStorageManager()
        ) {
            result.error("no_all_files_access", "Grant all-files access first", null)
            return
        }
        if (pendingVaultResult != null) {
            result.error("busy", "Picker already open", null)
            return
        }
        pendingVaultResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        try {
            startActivityForResult(intent, vaultPickRequestCode)
        } catch (e: Exception) {
            pendingVaultResult = null
            result.error("picker_failed", e.toString(), null)
        }
    }

    /** Из tree-URI вида content://…/tree/primary%3ADocuments%2Fobsidian
     *  достаёт реальный путь /storage/emulated/0/Documents/obsidian. */
    private fun treeToRealPath(treeUri: Uri?): String? {
        if (treeUri == null) return null
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        val parts = docId.split(":")
        if (parts.size < 2) return null
        val volume = parts[0]
        val relative = parts.drop(1).joinToString("/")
        val root = if (volume == "primary") {
            Environment.getExternalStorageDirectory()?.absolutePath
        } else {
            "/storage/$volume"
        }
        if (root == null) return null
        return if (relative.isEmpty()) root else "$root/$relative"
    }
}
