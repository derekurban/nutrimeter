package app.nutrimeter

import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Hosts two small channels: the updater (what build and phone this is, the install permission, and installing a
/// downloaded APK over this app) and links (opening a web page in the browser).
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val update = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nutrimeter/update")
        UpdateReceiver.onStatus = { status, message -> runOnUiThread { update.invokeMethod("installStatus", mapOf("status" to status, "message" to message)) } }
        update.setMethodCallHandler { call, result ->
            when (call.method) {
                "appInfo" -> {
                    val pi = packageManager.getPackageInfo(packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else @Suppress("DEPRECATION") pi.versionCode.toLong()
                    result.success(mapOf("versionName" to (pi.versionName ?: ""), "versionCode" to code, "flavor" to BuildConfig.FLAVOR, "package" to packageName,
                        "maker" to Build.MANUFACTURER, "model" to Build.MODEL, "android" to Build.VERSION.RELEASE, "sdk" to Build.VERSION.SDK_INT))
                }
                "canInstall" -> result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= 26) startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                    result.success(true)
                }
                // not the cache: Android empties that when storage runs low, which can take the APK mid-update
                "cacheDir" -> result.success(File(noBackupFilesDir, "updates").apply { mkdirs() }.absolutePath)
                "install" -> result.success(installApk(call.argument<String>("path")!!))
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nutrimeter/links").setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> result.success(try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")!!)).addCategory(Intent.CATEGORY_BROWSABLE))
                    true
                } catch (e: ActivityNotFoundException) { false })
                else -> result.notImplemented()
            }
        }
    }

    /// Installs an APK from our files over this app through a PackageInstaller session. On Android 12+ the session asks
    /// for no user action, which Android honours once this app is its own installer of record (after the first update
    /// it installs); until then, or on older Android, UpdateReceiver shows the system's confirm screen. On success
    /// Android stops this process and the new version starts on the next launch.
    private fun installApk(path: String): Boolean = try {
        val file = File(path)
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(packageName)
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            file.inputStream().use { input ->
                session.openWrite("update.apk", 0, file.length()).use { out -> input.copyTo(out); session.fsync(out) }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val done = PendingIntent.getBroadcast(this, id, Intent(this, UpdateReceiver::class.java).setPackage(packageName), flags)
            session.commit(done.intentSender)
        }
        file.delete()   // the session holds its own copy now
        true
    } catch (e: Exception) {
        false
    }
}
