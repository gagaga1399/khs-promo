package com.qutzem.khs

import android.content.Intent
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
