package app.veya.veya

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.provider.Settings
import android.util.Base64
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
 private var permissionResult: MethodChannel.Result? = null
 private var otpReceiver: BroadcastReceiver? = null
 private lateinit var bridge: MethodChannel
 override fun onCreate(savedInstanceState: Bundle?) {
  installSplashScreen()
  super.onCreate(savedInstanceState)
 }
 override fun configureFlutterEngine(engine: FlutterEngine) {
  super.configureFlutterEngine(engine)
  bridge = MethodChannel(engine.dartExecutor.binaryMessenger, "app.veya/assistant")
  bridge.setMethodCallHandler { call, result ->
   val prefs = getSharedPreferences("assistant", MODE_PRIVATE)
   when(call.method) {
    "configure" -> {
     val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
     val edit = prefs.edit()
     for (key in listOf("endpoint", "language", "firebaseIdToken")) edit.putString(key, args[key]?.toString() ?: "")
     edit.putFloat("floatingIconScale", (args["floatingIconScale"] as? Number)?.toFloat() ?: 1f)
     edit.putFloat("floatingIconOpacity", (args["floatingIconOpacity"] as? Number)?.toFloat() ?: .9f)
     edit.putStringSet("allowedApps", (args["allowedApps"] as? List<*>)?.map { it.toString() }?.toSet() ?: emptySet())
     edit.apply()
     FloatingAssistant.instance?.requestSilentTokenRefresh()
     FloatingAssistant.instance?.refresh()
     result.success(null)
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
    "launchUpiIntent" -> {
     val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
     val raw = args["intentUrl"]?.toString()
     val packageId = args["packageName"]?.toString()
     if (raw.isNullOrBlank() || packageId.isNullOrBlank()) { result.success(false); return@setMethodCallHandler }
     val launched = runCatching {
      val intent = Intent.parseUri(raw, Intent.URI_INTENT_SCHEME).apply {
       addCategory(Intent.CATEGORY_BROWSABLE)
       addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
       // Cashfree returns HTTPS app links. Pinning the selected installed UPI
       // package prevents Android from handing the link to a web browser.
       setPackage(packageId)
      }
      if (intent.resolveActivity(packageManager) == null) false
      else { startActivity(intent); true }
     }.getOrDefault(false)
     result.success(launched)
    }
    "installedApps" -> {
     Thread {
      val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
      val apps = packageManager.queryIntentActivities(launcherIntent, 0)
       .distinctBy { it.activityInfo.packageName }
       .filter { it.activityInfo.packageName != packageName }
       .map { mapOf("package" to it.activityInfo.packageName, "name" to it.loadLabel(packageManager).toString()) }
       .sortedBy { it["name"] }
      runOnUiThread { result.success(apps) }
     }.start()
    }
    "installedUpiApps" -> {
     Thread {
      val supported = linkedMapOf(
       "com.phonepe.app" to "PhonePe",
       "com.google.android.apps.nbu.paisa.user" to "Google Pay",
       "net.one97.paytm" to "Paytm",
       "com.dreamplug.androidapp" to "CRED",
       "in.amazon.mShop.android.shopping" to "Amazon Pay",
       "in.org.npci.upiapp" to "BHIM",
       "com.supermoney.app" to "SuperMoney"
      )
      val apps = supported.mapNotNull { (packageId, fallbackName) ->
       runCatching {
        val info = packageManager.getApplicationInfo(packageId, 0)
        mapOf(
         "package" to packageId,
         "name" to packageManager.getApplicationLabel(info).toString().ifBlank { fallbackName },
         "icon" to appIconDataUri(info)
        )
       }.getOrNull()
      }
      runOnUiThread { result.success(apps) }
     }.start()
    }
    else -> result.notImplemented()
   }
  }
 }

 private fun appIconDataUri(info: android.content.pm.ApplicationInfo): String {
  val size = (48 * resources.displayMetrics.density).toInt()
  val drawable = packageManager.getApplicationIcon(info)
  val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
  drawable.setBounds(0, 0, size, size)
  drawable.draw(Canvas(bitmap))
  val bytes = ByteArrayOutputStream()
  bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
  return Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
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
    val code = Regex("\\b\\d{6}\\b").find(message)?.value ?: return
    Log.d("VeyaOtp", "Received OTP from SMS Retriever")
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
