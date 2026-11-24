package app.veya.veya

import android.Manifest
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
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

class MainActivity : FlutterActivity() {
 companion object {
  /**
   * Ephemeral handoff from Flutter after sign-in to the accessibility service.
   * It deliberately lives only in process memory; Firebase Auth remains the
   * durable, encrypted session store and the service refreshes from it.
   */
  @Volatile var inMemoryFirebaseIdToken: String? = null
  @Volatile var inMemoryFirebaseTokenReceivedAt: Long = 0L
 }
 private var permissionResult: MethodChannel.Result? = null
 private var otpReceiver: BroadcastReceiver? = null
 private lateinit var bridge: MethodChannel
 private val smsConsentRequestCode = 3241
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
     // Release builds only talk to Veya's HTTPS gateway. Do not retain a
     // development endpoint or a bearer token in ordinary SharedPreferences.
     val requestedEndpoint = args["endpoint"]?.toString()?.trimEnd('/') ?: ""
     edit.putString("endpoint", if (BuildConfig.DEBUG) requestedEndpoint else "https://api.heyveya.app")
     edit.putString("language", args["language"]?.toString() ?: "")
     edit.remove("firebaseIdToken")
     inMemoryFirebaseIdToken = args["firebaseIdToken"]?.toString()?.takeIf { it.isNotBlank() }
     inMemoryFirebaseTokenReceivedAt = android.os.SystemClock.elapsedRealtime()
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
    // A hash-tagged SMS includes the message directly and can be read without
    // a prompt. Providers that do not support the Retriever hash supply a
    // consent intent instead; Android asks for one-tap approval first.
    val consentIntent = intent.extras?.getParcelable<Intent>(SmsRetriever.EXTRA_CONSENT_INTENT)
    if (consentIntent != null) {
      runCatching { startActivityForResult(consentIntent, smsConsentRequestCode) }
        .onFailure { error -> Log.e("VeyaOtp", "Could not show SMS consent", error) }
      return
    }
    deliverOtp(intent.extras?.getString(SmsRetriever.EXTRA_SMS_MESSAGE))
   }
  }
  ContextCompat.registerReceiver(
   this, otpReceiver, IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION), ContextCompat.RECEIVER_EXPORTED
  )
  val client = SmsRetriever.getClient(this)
  // Keep the hash-based Retriever path for zero-tap autofill, and register
  // User Consent as a fallback for provider-controlled SMS text.
  client.startSmsRetriever()
   .addOnSuccessListener { Log.d("VeyaOtp", "SMS Retriever listener ready") }
   .addOnFailureListener { error -> Log.w("VeyaOtp", "SMS Retriever unavailable", error) }
  client.startSmsUserConsent(null)
   .addOnSuccessListener { Log.d("VeyaOtp", "SMS User Consent listener ready"); result.success(null) }
   .addOnFailureListener { error -> Log.e("VeyaOtp", "SMS User Consent unavailable", error); result.success(null) }
 }

 private fun deliverOtp(message: String?) {
  val code = message?.let { Regex("\\b\\d{6}\\b").find(it)?.value } ?: return
  Log.d("VeyaOtp", "Received OTP from SMS listener")
  bridge.invokeMethod("otpReceived", code)
  stopOtpListener()
 }

 private fun stopOtpListener() {
  otpReceiver?.let { runCatching { unregisterReceiver(it) } }
  otpReceiver = null
 }

 private fun smsRetrieverHash(): String {
  // PackageInfo.signingInfo was introduced in Android 9 (API 28). The SMS
  // Retriever is also supported by our Android 8 minimum version, so use the
  // legacy signatures field there instead of resolving a field that does not
  // exist on those devices.
  @Suppress("DEPRECATION")
  val signature = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
   packageManager
    .getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
    .signingInfo
    ?.apkContentsSigners
    ?.firstOrNull()
    ?.toCharsString()
  } else {
   packageManager
    .getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
    .signatures
    ?.firstOrNull()
    ?.toCharsString()
  } ?: return "unavailable"
  val bytes = MessageDigest.getInstance("SHA-256").digest("$packageName $signature".toByteArray(Charsets.UTF_8))
  return Base64.encodeToString(bytes.copyOfRange(0, 9), Base64.NO_PADDING or Base64.NO_WRAP).take(11)
 }
 override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
  super.onRequestPermissionsResult(code, permissions, results)
  if(code == 501) { permissionResult?.success(results.firstOrNull() == PackageManager.PERMISSION_GRANTED); permissionResult = null }
 }
 override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
  super.onActivityResult(requestCode, resultCode, data)
  if (requestCode != smsConsentRequestCode) return
  if (resultCode == RESULT_OK) deliverOtp(data?.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE))
  else {
   Log.d("VeyaOtp", "SMS User Consent was dismissed")
   stopOtpListener()
  }
 }
 override fun onDestroy() { stopOtpListener(); super.onDestroy() }
}
