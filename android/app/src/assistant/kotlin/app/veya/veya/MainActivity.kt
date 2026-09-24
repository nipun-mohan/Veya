package app.veya.veya

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.provider.Settings
import android.util.Base64
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
 private var permissionResult: MethodChannel.Result? = null
 private var otpReceiver: BroadcastReceiver? = null
 private lateinit var bridge: MethodChannel
 override fun configureFlutterEngine(engine: FlutterEngine) {
  super.configureFlutterEngine(engine)
  bridge = MethodChannel(engine.dartExecutor.binaryMessenger, "app.veya/assistant")
  bridge.setMethodCallHandler { call, result ->
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
    "isEnabled" -> result.success(isAccessibilityEnabled())
    "isMicrophoneGranted" -> result.success(
     checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    )
    "openAccessibility" -> {
     prefs.edit().putBoolean("returnToVeyaAfterAccessibility", true).apply()
     openAccessibilitySettings()
     result.success(null)
    }
    "openAccessibilityForDisable" -> {
     prefs.edit().putBoolean("returnToVeyaAfterDisable", true).apply()
     openAccessibilitySettings()
     result.success(null)
    }
    "requestMicrophone" -> {
     if(checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) result.success(true)
     else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 501) }
    }
    "startOtpListener" -> startOtpListener(result)
    "stopOtpListener" -> { stopOtpListener(); result.success(null) }
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

 private fun openAccessibilitySettings() {
  startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
 }

 private fun isAccessibilityEnabled(): Boolean {
  val enabled = Settings.Secure.getString(
   contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
  ) ?: return false
  val component = ComponentName(this, FloatingAssistant::class.java)
  return enabled.split(':').mapNotNull(ComponentName::unflattenFromString).any {
   it.packageName == component.packageName && it.className == component.className
  }
 }


 private fun startOtpListener(result: MethodChannel.Result) {
  stopOtpListener()
  Log.d("VeyaOtp", "Starting SMS Retriever listener; appHash=${smsRetrieverHash()}")
  otpReceiver = object : BroadcastReceiver() {
   override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
    val status = intent.extras?.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return
    Log.d("VeyaOtp", "SMS Retriever status=${status.statusCode}")
    if (status.statusCode != CommonStatusCodes.SUCCESS) return
    val message = intent.extras?.getString(SmsRetriever.EXTRA_SMS_MESSAGE) ?: return
    val code = Regex("\\b\\d{4}\\b").find(message)?.value ?: return
    Log.d("VeyaOtp", "Received a four-digit OTP")
    bridge.invokeMethod("otpReceived", code)
    stopOtpListener()
   }
  }
  ContextCompat.registerReceiver(
   this, otpReceiver, IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION), ContextCompat.RECEIVER_EXPORTED
  )
  SmsRetriever.getClient(this).startSmsRetriever()
   .addOnSuccessListener { Log.d("VeyaOtp", "SMS Retriever listener ready"); result.success(null) }
   .addOnFailureListener { error -> Log.e("VeyaOtp", "SMS Retriever unavailable", error); stopOtpListener(); result.success(null) }
 }

 private fun stopOtpListener() {
  otpReceiver?.let { runCatching { unregisterReceiver(it) } }
  otpReceiver = null
 }

 private fun smsRetrieverHash(): String {
  val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
  val signature = info.signingInfo?.apkContentsSigners?.firstOrNull()?.toCharsString() ?: return "unavailable"
  val bytes = MessageDigest.getInstance("SHA-256").digest("$packageName $signature".toByteArray(Charsets.UTF_8))
  return Base64.encodeToString(bytes.copyOfRange(0, 9), Base64.NO_PADDING or Base64.NO_WRAP).take(11)
 }
 override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
  super.onRequestPermissionsResult(code, permissions, results)
  if(code == 501) { permissionResult?.success(results.firstOrNull() == PackageManager.PERMISSION_GRANTED); permissionResult = null }
 }
 override fun onDestroy() { stopOtpListener(); super.onDestroy() }
}
