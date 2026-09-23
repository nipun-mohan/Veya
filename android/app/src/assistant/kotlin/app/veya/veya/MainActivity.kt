package app.veya.veya

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
 private var permissionResult: MethodChannel.Result? = null
 override fun configureFlutterEngine(engine: FlutterEngine) {
  super.configureFlutterEngine(engine)
  MethodChannel(engine.dartExecutor.binaryMessenger, "app.veya/assistant").setMethodCallHandler { call, result ->
   val prefs = getSharedPreferences("assistant", MODE_PRIVATE)
   when(call.method) {
    "configure" -> {
     val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
     val edit = prefs.edit()
     for (key in listOf("endpoint", "language")) edit.putString(key, args[key]?.toString() ?: "")
     edit.putFloat("floatingIconScale", (args["floatingIconScale"] as? Number)?.toFloat() ?: 1f)
     edit.putFloat("floatingIconOpacity", (args["floatingIconOpacity"] as? Number)?.toFloat() ?: .9f)
     edit.putStringSet("allowedApps", (args["allowedApps"] as? List<*>)?.map { it.toString() }?.toSet() ?: emptySet())
     edit.apply(); FloatingAssistant.instance?.refresh(); result.success(null)
    }
    "isEnabled" -> result.success(FloatingAssistant.instance != null)
    "openAccessibility" -> {
     prefs.edit().putBoolean("returnToVeyaAfterAccessibility", true).apply()
     startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
     result.success(null)
    }
    "requestMicrophone" -> {
     if(checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) result.success(true)
     else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 501) }
    }
    "showBubble" -> { FloatingAssistant.instance?.restore(); result.success(null) }
    "installedApps" -> {
     val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
     result.success(packageManager.queryIntentActivities(intent, 0).distinctBy { it.activityInfo.packageName }
      .filter { it.activityInfo.packageName != packageName }
      .map { mapOf("package" to it.activityInfo.packageName, "name" to it.loadLabel(packageManager).toString()) }.sortedBy { it["name"] })
    }
    else -> result.notImplemented()
   }
  }
 }
 override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
  super.onRequestPermissionsResult(code, permissions, results)
  if(code == 501) { permissionResult?.success(results.firstOrNull() == PackageManager.PERMISSION_GRANTED); permissionResult = null }
 }
}
