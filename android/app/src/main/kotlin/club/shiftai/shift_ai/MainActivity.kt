package club.shiftai.shift_ai

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Adds the one thing the updater cannot do from Dart: hand a downloaded APK
 * to the system package installer.
 *
 * Android has no silent sideload path, so this is as automatic as an
 * unsigned build gets — the app fetches the APK itself and the user confirms
 * the install once. The file lives in the app's own cache, which is not
 * world-readable, so it is exposed through a FileProvider `content://` URI
 * rather than a `file://` one (which Android has rejected since Nougat).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "club.shiftai.app/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.arguments as? String
                result.success(path != null && openInstaller(path))
            }
    }

    private fun openInstaller(path: String): Boolean = try {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            File(path),
        )
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
        true
    } catch (e: Exception) {
        // Failing here just means no prompt appears; the release page's
        // download button still works.
        false
    }
}
