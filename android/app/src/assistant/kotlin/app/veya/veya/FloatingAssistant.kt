package app.veya.veya

import android.accessibilityservice.AccessibilityService
import android.animation.ValueAnimator
import android.content.*
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.media.MediaRecorder
import android.util.Log
import android.hardware.*
import android.os.*
import android.view.*
import android.view.accessibility.*
import android.view.animation.OvershootInterpolator
import android.widget.*
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class FloatingAssistant : AccessibilityService(), SensorEventListener {
 companion object { var instance: FloatingAssistant? = null }
 private val main = Handler(Looper.getMainLooper())
 private val worker = Executors.newSingleThreadExecutor()
 private val httpClient by lazy {
  OkHttpClient.Builder()
   .connectTimeout(15, TimeUnit.SECONDS)
   .readTimeout(90, TimeUnit.SECONDS)
   .build()
 }
 private val prefs by lazy { getSharedPreferences("assistant", MODE_PRIVATE) }
 private val wm by lazy { getSystemService(WINDOW_SERVICE) as WindowManager }
 private var panel: LinearLayout? = null
 private var params: WindowManager.LayoutParams? = null
 private var recorder: MediaRecorder? = null
 private var recordingFile: File? = null
 @Volatile private var recordingAmplitude=0
 private var state = "idle"
 private var hidden = false
 private var targetPackage = ""
 private var requestId = 0
 private var pulse: ValueAnimator? = null
 private var hideTarget: TextView? = null
 private var hideTargetParams: WindowManager.LayoutParams? = null
 private val ink = Color.rgb(23, 63, 56)
 private val lime = Color.rgb(217, 242, 145)
 private val lavender = Color.rgb(236, 241, 230)
 private val teal = Color.rgb(35, 91, 78)
 private var x = 20; private var y = 300
 private var sensor: SensorManager? = null
 private var lastShake = 0L
 private val amplitudeTicker = object : Runnable {
  override fun run() {
   if (state != "recording") return
   recordingAmplitude = runCatching { recorder?.maxAmplitude ?: 0 }.getOrDefault(0)
   main.postDelayed(this, 60)
  }
 }
 private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
 private fun haptic() {
  val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
   getSystemService(VibratorManager::class.java).defaultVibrator
  } else {
   @Suppress("DEPRECATION") getSystemService(VIBRATOR_SERVICE) as Vibrator
  }
  if (!vibrator.hasVibrator()) return
  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
   vibrator.vibrate(VibrationEffect.createOneShot(24, VibrationEffect.DEFAULT_AMPLITUDE))
  } else {
   @Suppress("DEPRECATION") vibrator.vibrate(24)
  }
 }
 override fun onServiceConnected() {
  instance = this
  sensor = getSystemService(SENSOR_SERVICE) as SensorManager
  sensor?.registerListener(this, sensor?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER), SensorManager.SENSOR_DELAY_UI)
  refresh()
  if (prefs.getBoolean("returnToVeyaAfterAccessibility", false)) {
   prefs.edit().remove("returnToVeyaAfterAccessibility").apply()
   main.postDelayed({
    packageManager.getLaunchIntentForPackage(packageName)?.apply {
     addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
     startActivity(this)
    }
   }, 350)
  }
 }
 override fun onAccessibilityEvent(event: AccessibilityEvent?) { refresh() }
 override fun onInterrupt() { cancel(); remove() }
 override fun onDestroy() { sensor?.unregisterListener(this); cancel(); remove(); worker.shutdownNow(); instance = null; super.onDestroy() }
 override fun onSensorChanged(e: SensorEvent) {
  val force = sqrt(e.values[0]*e.values[0] + e.values[1]*e.values[1] + e.values[2]*e.values[2]) / SensorManager.GRAVITY_EARTH
  if (hidden && force > 2.35f && SystemClock.uptimeMillis() - lastShake > 900) { lastShake=SystemClock.uptimeMillis(); restore() }
 }
 override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
 fun restore() { hidden = false; refresh() }
 fun refresh() {
  val root = rootInActiveWindow ?: return
  val pkg = root.packageName?.toString() ?: return
  val allowed = prefs.getStringSet("allowedApps", emptySet())!!.contains(pkg)
  val focus = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
  if (!allowed || focus?.isPassword == true || focus?.isEditable != true) {
   if (pkg != packageName) { cancel(); remove() }
   return
  }
  if (hidden) return
  if (panel != null && targetPackage != pkg && pkg != packageName) { cancel(); remove() }
  if (panel == null && focus?.isEditable == true) { targetPackage = pkg; bubble() }
 }
 private fun background() = GradientDrawable().apply { setColor(ink); cornerRadius = dp(24).toFloat() }
 private fun responseBackground() = GradientDrawable().apply { setColor(Color.argb(234, 247, 232, 217)); cornerRadius = dp(26).toFloat() }
 private fun text(value: String, size: Float = 16f) = TextView(this).apply {
  text = value; textSize = size; setTextColor(lime); gravity = Gravity.CENTER; setPadding(dp(12), dp(10), dp(12), dp(10))
 }
 private fun button(value: String, action: () -> Unit) = text(value).apply { setOnClickListener { action() } }
 private fun circle(value:String, fillColor:Int, textColor:Int, action:()->Unit) = TextView(this).apply {
  text=value; textSize=26f; setTextColor(textColor); gravity=Gravity.CENTER
  background=GradientDrawable().apply { setColor(fillColor); shape=GradientDrawable.OVAL }
  elevation=dp(6).toFloat(); setOnClickListener { haptic(); action() }
 }
 private fun doneCircle(fillColor: Int, action: () -> Unit) = object : View(this) {
  private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = fillColor }
  private val check = Paint(Paint.ANTI_ALIAS_FLAG).apply {
   color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = dp(2).toFloat(); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
  }
  init { elevation = dp(6).toFloat(); setOnClickListener { haptic(); action() } }
  override fun onDraw(canvas: Canvas) {
   val r = min(width, height) / 2f
   canvas.drawCircle(width / 2f, height / 2f, r, fill)
   val path = Path().apply {
    moveTo(width * .34f, height * .53f)
    lineTo(width * .45f, height * .64f)
    lineTo(width * .67f, height * .39f)
   }
   canvas.drawPath(path, check)
  }
 }
 private fun removeHideTarget() { hideTarget?.let { runCatching { wm.removeView(it) } }; hideTarget=null; hideTargetParams=null }
 private fun showHideTarget() {
  if(hideTarget!=null || state!="idle") return
  val target=TextView(this).apply {
   text="↓  Hide"; textSize=14f; gravity=Gravity.CENTER; setTextColor(Color.WHITE); setTypeface(null,Typeface.BOLD)
   background=GradientDrawable().apply { setColor(Color.argb(224,23,63,56)); cornerRadius=dp(26).toFloat() }
  }
  val lp=WindowManager.LayoutParams(dp(126),dp(52),WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,PixelFormat.TRANSLUCENT).apply { gravity=Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL; y=dp(34) }
  hideTarget=target; hideTargetParams=lp; wm.addView(target,lp)
 }
 private fun remove() { pulse?.cancel(); pulse = null; removeHideTarget(); panel?.let { runCatching { wm.removeView(it) } }; panel = null }
 private fun show(width: Int, content: (LinearLayout) -> Unit) {
  remove()
  val view = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; background = background(); elevation = dp(10).toFloat(); setPadding(dp(6),dp(6),dp(6),dp(6)) }
  val lp = WindowManager.LayoutParams(dp(width), WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL, PixelFormat.TRANSLUCENT)
  lp.gravity = Gravity.TOP or Gravity.LEFT
  lp.x = x.coerceIn(0, max(0, resources.displayMetrics.widthPixels - dp(width))); lp.y = y
  panel = view; params = lp; content(view); wm.addView(view, lp)
 }
 private fun draggable(view: View, tap: (() -> Unit)? = null) {
  var sx = 0f; var sy = 0f; var ox = 0; var oy = 0; var moved = false; var downAt = 0L
  view.setOnTouchListener { _, e ->
   val lp = params ?: return@setOnTouchListener false
   when(e.actionMasked) {
    MotionEvent.ACTION_DOWN -> { downAt=SystemClock.uptimeMillis(); sx=e.rawX; sy=e.rawY; ox=lp.x; oy=lp.y; moved=false; if(state=="idle") showHideTarget(); view.animate().scaleX(1.08f).scaleY(1.08f).setDuration(100).start() }
    MotionEvent.ACTION_MOVE -> {
     if(hypot(e.rawX-sx,e.rawY-sy)>dp(8)) moved=true
     lp.x=(ox+e.rawX-sx).toInt().coerceIn(0,max(0,resources.displayMetrics.widthPixels-lp.width))
     lp.y=(oy+e.rawY-sy).toInt().coerceIn(0,max(0,resources.displayMetrics.heightPixels-(panel?.height ?: dp(60))))
     panel?.let { wm.updateViewLayout(it,lp) }; x=lp.x; y=lp.y
    }
    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
     view.animate().scaleX(1f).scaleY(1f).setInterpolator(OvershootInterpolator(4f)).setDuration(450).start()
     val droppedOnHide=state=="idle" && moved && e.rawY > resources.displayMetrics.heightPixels-dp(150)
     if(droppedOnHide) { hidden=true; removeHideTarget(); remove(); return@setOnTouchListener true }
     removeHideTarget()
     if (moved) {
      val settledX=lp.x; val settledY=lp.y
      ValueAnimator.ofFloat(0f, 1f).apply {
       duration=520; interpolator=OvershootInterpolator(1.8f)
       addUpdateListener { animation ->
        val p=animation.animatedValue as Float
        lp.x=(settledX + sin(p* Math.PI).toFloat()*dp(11)).toInt()
        lp.y=(settledY - abs(sin(p* Math.PI)).toFloat()*dp(9)).toInt()
        panel?.let { wm.updateViewLayout(it,lp) }
       }
       start()
      }
     }
     if(!moved && e.actionMasked==MotionEvent.ACTION_UP) {
      if(state=="idle" && SystemClock.uptimeMillis()-downAt>600) { hidden=true; remove() } else { haptic(); tap?.invoke() }
     }
    }
   }; true
  }
 }
 private fun bubble() {
  state="idle"; remove()
  val scale=prefs.getFloat("floatingIconScale",1f).coerceIn(.75f,1.35f)
  val opacity=prefs.getFloat("floatingIconOpacity",.9f).coerceIn(.35f,1f)
  val orb = Orb(false)
  // Reserve clear space around the icon so the press/drag scale animation is
  // never clipped by the overlay window.
  val frame = LinearLayout(this).apply {
   orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER; clipChildren=false; clipToPadding=false
   addView(orb, LinearLayout.LayoutParams((dp(54)*scale).roundToInt(), (dp(52)*scale).roundToInt()))
  }
  val lp = WindowManager.LayoutParams((dp(64)*scale).roundToInt(), (dp(62)*scale).roundToInt(), WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL, PixelFormat.TRANSLUCENT).apply {
    gravity=Gravity.TOP or Gravity.LEFT; x=this@FloatingAssistant.x; y=this@FloatingAssistant.y
  }
  frame.alpha=opacity
  panel = frame; params = lp
  wm.addView(frame, lp)
  draggable(orb) { startRecording() }
 }
 private inner class Orb(private val active:Boolean): View(this@FloatingAssistant) {
  private val pebblePeach=Color.rgb(247, 232, 217)
  private val pebbleMuted=Color.rgb(115, 129, 123)
  private val fill=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=pebblePeach }
  private val bar=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=teal; strokeWidth=dp(3).toFloat(); strokeCap=Paint.Cap.ROUND }
  override fun onDraw(c:Canvas) {
   // A warm, quiet version of Pebble: a clean peach surface and a small teal
   // waveform that stays visible without competing with the host app.
   val outer=RectF(0f,0f,width.toFloat(),height.toFloat())
   val u=min(width.toFloat()/dp(54),height.toFloat()/dp(52))
   fun unit(value:Int)=dp(value)*u
   c.drawRoundRect(outer,unit(19),unit(19),fill)
   val time=SystemClock.uptimeMillis()/130.0
   val idleHeights=intArrayOf(5, 8, 13, 8, 5)
   bar.strokeWidth=unit(3)
   for(i in 0..4) {
    val halfHeight=if(active) (unit(5).toDouble() + abs(sin(time+i*.8))*unit(9).toDouble()).toFloat() else unit(idleHeights[i])
    val xx=width/2f+(i-2)*unit(7)
    c.drawLine(xx,height/2f-halfHeight,xx,height/2f+halfHeight,bar)
   }
   if(active) postInvalidateDelayed(45)
  }
 }
 private fun cancel() {
  requestId++
  main.removeCallbacks(amplitudeTicker)
  recorder?.let { runCatching { it.stop() }; it.release() }; recorder=null; recordingFile?.delete(); recordingFile=null; recordingAmplitude=0; state="idle"
 }
 private fun startRecording() {
  if(state!="idle") return
  try {
   if(prefs.getString("endpoint", "").isNullOrBlank()) error("Set the translation service in Veya Settings.")
   ++requestId
   recordingFile=File(cacheDir,"veya-${System.currentTimeMillis()}.m4a")
   recorder=MediaRecorder().apply {
    setAudioSource(MediaRecorder.AudioSource.MIC)
    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
    setAudioSamplingRate(16000)
    setAudioEncodingBitRate(24000)
    setOutputFile(recordingFile!!.absolutePath)
    prepare()
    start()
   }
   state="recording"; recorderControls(); main.post(amplitudeTicker)
  } catch(e: Exception) { Log.e("VeyaAssistant", "Floating recorder startup failed", e); cancel(); failure("Could not start recording. Open Veya once, then try again.") }
 }
 private fun recorderControls() {
  remove()
  // Keep the controls compact, but give each action enough clear space to avoid
  // accidental taps while the phone is being held one-handed.
 val row=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL; setPadding(dp(7),dp(7),dp(7),dp(7)) }
  val lp=WindowManager.LayoutParams(dp(202),dp(60),WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,PixelFormat.TRANSLUCENT).apply { gravity=Gravity.TOP or Gravity.LEFT; x=this@FloatingAssistant.x; y=this@FloatingAssistant.y }
  val controlPeach=Color.argb(222, 247, 232, 217)
  val controlTeal=Color.argb(222, 35, 91, 78)
  val close=circle("×",controlPeach,teal) { cancel(); bubble() }
  row.addView(close,LinearLayout.LayoutParams(dp(46),dp(46)))
  val capsule=Wave().apply { background=GradientDrawable().apply { setColor(controlPeach); cornerRadius=dp(23).toFloat() }; setPadding(dp(8),0,dp(8),0) }
  row.addView(capsule,LinearLayout.LayoutParams(0,dp(46),1f).apply { setMargins(dp(9),0,dp(9),0) })
  row.addView(doneCircle(controlTeal) { finishRecording() },LinearLayout.LayoutParams(dp(46),dp(46)))
  panel=row; params=lp; wm.addView(row,lp); draggable(capsule)
 }
 private fun generatingControls() {
  remove()
  val row=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL; setPadding(dp(7),dp(7),dp(7),dp(7)) }
  val lp=WindowManager.LayoutParams(dp(202),dp(60),WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,PixelFormat.TRANSLUCENT).apply { gravity=Gravity.TOP or Gravity.LEFT; x=this@FloatingAssistant.x; y=this@FloatingAssistant.y }
  val controlPeach=Color.argb(222, 247, 232, 217)
  val close=circle("×",controlPeach,teal) { cancel(); bubble() }
  row.addView(close,LinearLayout.LayoutParams(dp(46),dp(46)))
  val capsule=Wave().apply { background=GradientDrawable().apply { setColor(controlPeach); cornerRadius=dp(23).toFloat() } }
  row.addView(capsule,LinearLayout.LayoutParams(0,dp(46),1f).apply { setMargins(dp(9),0,dp(9),0) })
  row.addView(Spinner(controlPeach),LinearLayout.LayoutParams(dp(46),dp(46)))
  panel=row; params=lp; wm.addView(row,lp)
 }
 private inner class Spinner(private val backgroundColor: Int) : View(this@FloatingAssistant) {
  private val fill=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=backgroundColor }
  private val arc=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=teal; style=Paint.Style.STROKE; strokeWidth=dp(3).toFloat(); strokeCap=Paint.Cap.ROUND }
  override fun onDraw(canvas: Canvas) {
   val center=width/2f; val radius=min(width,height)/2f
   canvas.drawCircle(center,height/2f,radius,fill)
   val inset=dp(12).toFloat(); val rect=RectF(inset,inset,width-inset,height-inset)
   canvas.drawArc(rect,(SystemClock.uptimeMillis()/4 % 360).toFloat(),245f,false,arc)
   if(state=="generating") postInvalidateDelayed(16)
  }
 }
 private inner class ModeBadge : View(this@FloatingAssistant) {
 var mode: String = "casual"
   set(value) { field=value; invalidate() }
  var active: Boolean = false
   set(value) { field=value; invalidate() }
  private val fill=Paint(Paint.ANTI_ALIAS_FLAG)
  private val line=Paint(Paint.ANTI_ALIAS_FLAG).apply { style=Paint.Style.STROKE; strokeWidth=dp(1).toFloat(); strokeCap=Paint.Cap.ROUND; strokeJoin=Paint.Join.ROUND }
  private val glyph=Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign=Paint.Align.CENTER; typeface=Typeface.DEFAULT_BOLD }
  override fun onDraw(canvas: Canvas) {
   fill.color=if(active) teal else Color.WHITE
   line.color=if(active) Color.WHITE else teal
   glyph.color=if(active) Color.WHITE else teal
   val cx=width/2f; val cy=height/2f; canvas.drawCircle(cx,cy,min(width,height)/2f,fill)
   when(mode) {
    "casual" -> { canvas.drawCircle(cx,cy,dp(12).toFloat(),line); canvas.drawCircle(cx-dp(4),cy-dp(2),dp(1).toFloat(),Paint(line).apply { style=Paint.Style.FILL }); canvas.drawCircle(cx+dp(4),cy-dp(2),dp(1).toFloat(),Paint(line).apply { style=Paint.Style.FILL }); canvas.drawArc(RectF(cx-dp(6),cy-dp(1),cx+dp(6),cy+dp(8)),0f,180f,false,line) }
    "formal" -> { canvas.drawRoundRect(RectF(cx-dp(9),cy-dp(12),cx+dp(9),cy+dp(12)),dp(2).toFloat(),dp(2).toFloat(),line); canvas.drawLine(cx-dp(5),cy-dp(4),cx+dp(5),cy-dp(4),line); canvas.drawLine(cx-dp(5),cy+dp(2),cx+dp(5),cy+dp(2),line); canvas.drawLine(cx-dp(5),cy+dp(8),cx+dp(2),cy+dp(8),line) }
    else -> { glyph.textSize=dp(17).toFloat(); canvas.drawText(mode.take(1),cx,cy+dp(6),glyph) }
   }
  }
 }
 private fun arrowButton(direction: Int, action: () -> Unit) = object : View(this) {
  private val fill=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.argb(155,255,255,255) }
  private val arrow=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=teal; style=Paint.Style.STROKE; strokeWidth=dp(2).toFloat(); strokeCap=Paint.Cap.ROUND; strokeJoin=Paint.Join.ROUND }
  init { setOnClickListener { haptic(); action() } }
  override fun onDraw(canvas: Canvas) {
   val cx=width/2f; val cy=height/2f; canvas.drawCircle(cx,cy,min(width,height)/2f,fill)
   val path=Path().apply { if(direction<0) { moveTo(cx+dp(4),cy-dp(7)); lineTo(cx-dp(4),cy); lineTo(cx+dp(4),cy+dp(7)) } else { moveTo(cx-dp(4),cy-dp(7)); lineTo(cx+dp(4),cy); lineTo(cx-dp(4),cy+dp(7)) } }
   canvas.drawPath(path,arrow)
  }
 }
 private inner class Wave: View(this@FloatingAssistant) {
  private val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.argb(220, 35, 91, 78); strokeWidth=dp(3).toFloat(); strokeCap=Paint.Cap.ROUND }
  override fun onDraw(c: Canvas) {
   super.onDraw(c)
   // MediaRecorder reports a raw 16-bit peak. Ignore low room noise so the
   // waveform only moves in response to an actual nearby voice.
   val gated=(recordingAmplitude-900).coerceAtLeast(0).toFloat()/9000f
   val amp=sqrt(gated.coerceIn(0f, 1f))
   for(i in 0..8) {
    val variation=if(amp==0f) 0f else (.4f+.6f*abs(sin(i+SystemClock.uptimeMillis()/150.0))).toFloat()
    val h=(dp(3).toFloat()+amp*dp(15).toFloat()*variation).coerceAtMost(dp(17).toFloat())
    val xx=width*(i+1)/10f
    c.drawLine(xx,height/2f-h/2,xx,height/2f+h/2,paint)
   }
   if(state=="recording") postInvalidateDelayed(60)
  }
 }
 private fun finishRecording() {
  if(state!="recording") return
  val id=requestId
  val file=recordingFile
  main.removeCallbacks(amplitudeTicker)
  val stopped=runCatching { recorder?.stop() }.isSuccess
  recorder?.release(); recorder=null
  recordingAmplitude=0
  state="generating"
  generatingControls()
  if (!stopped || file == null || file.length() < 512L) { file?.delete(); recordingFile=null; bubble(); return }
  worker.execute { processRecording(id,file) }
 }
 private fun processRecording(id:Int, file:File) {
  try {
   val endpoint=prefs.getString("endpoint", "")!!.trimEnd('/')
   val language=prefs.getString("language","en-IN")!!
   val result=postRecording("$endpoint/process",file,language)
   main.post { if(id==requestId) results(result) }
  } catch(e: Exception) {
   Log.e("VeyaAssistant","Recording processing failed",e)
   main.post { if(id==requestId) bubble() }
  } finally { file.delete(); if(recordingFile==file) recordingFile=null }
 }
 private fun postRecording(url:String, file:File, language:String):JSONObject {
  val requestBody=MultipartBody.Builder().setType(MultipartBody.FORM)
   .addFormDataPart("source_language",language)
   .addFormDataPart("file","voice.m4a",file.asRequestBody("audio/mp4".toMediaType()))
   .build()
  val request=Request.Builder().url(url).post(requestBody).build()
  val started=SystemClock.elapsedRealtime()
  httpClient.newCall(request).execute().use { response ->
   val raw=response.body?.string().orEmpty()
   val data=runCatching { JSONObject(raw) }.getOrElse { JSONObject() }
   Log.i("VeyaAssistant","OkHttp upload + processing: ${SystemClock.elapsedRealtime()-started}ms; protocol=${response.protocol}")
   if(!response.isSuccessful) error(data.optString("detail", "Translation service failed (${response.code})."))
   return data
  }
 }
 private fun postJson(url: String, body: JSONObject): JSONObject {
  val request = Request.Builder().url(url)
   .post(body.toString().toRequestBody("application/json".toMediaType()))
   .build()
  httpClient.newCall(request).execute().use { response ->
   val raw = response.body?.string().orEmpty()
   if (!response.isSuccessful) error("Style request failed (${response.code}).")
   return JSONObject(raw)
  }
 }
 private fun failure(message:String) { state="error"; show(280) { box -> box.addView(text(message,14f)); box.addView(button("Try again") { bubble() }); box.addView(button("Hide") { hidden=true; remove() }) } }
 private fun languageLabels(code: String): Pair<String, String> = when (code) {
  "hi-IN" -> "Hindi" to "हिन्दी"
  "as-IN" -> "Assamese" to "অসমীয়া"
  "ml-IN" -> "Malayalam" to "മലയാളം"
  "ta-IN" -> "Tamil" to "தமிழ்"
  "te-IN" -> "Telugu" to "తెలుగు"
  "kn-IN" -> "Kannada" to "ಕನ್ನಡ"
  "bn-IN" -> "Bengali" to "বাংলা"
  "mr-IN" -> "Marathi" to "मराठी"
  "ne-IN" -> "Nepali" to "नेपाली"
  "gu-IN" -> "Gujarati" to "ગુજરાતી"
  "ur-IN" -> "Urdu" to "اردو"
  "pa-IN" -> "Punjabi" to "ਪੰਜਾਬੀ"
  else -> "English" to "English"
 }
 private fun results(data:JSONObject) {
  state="results"
  val resultRequest=requestId
  val styles=data.optJSONObject("styles") ?: JSONObject()
  var selectedKey="casual"
  var selected=styles.optString("casual",data.optString("english_text"))
  val original=data.optString("original_text")
  val sourceCode=prefs.getString("language", "en-IN") ?: "en-IN"
  val language=languageLabels(sourceCode)
  show(350) { box ->
   // Keep the result sheet compact enough for its complete message to be read
   // at once in ordinary chat messages, while retaining a scroll fallback for
   // genuinely long dictation.
   box.background=responseBackground(); box.setPadding(dp(10),dp(9),dp(10),dp(10))
   val content=text(selected,14f).apply {
    gravity=Gravity.START; setTextColor(ink); setPadding(dp(8),dp(5),dp(8),dp(5))
   }
   val pages=mutableListOf<Triple<String,String,String>>().apply {
    add(Triple("casual","Casual",styles.optString("casual",data.optString("english_text"))))
    add(Triple("formal","Formal",styles.optString("formal","")))
    add(Triple("original",language.second,original))
   }
   var page=0
   lateinit var refreshPage: () -> Unit
   val selector=LinearLayout(this).apply {
    gravity=Gravity.CENTER_VERTICAL
    setPadding(dp(5),dp(5),dp(5),dp(5))
    background=GradientDrawable().apply { setColor(Color.argb(218,255,255,255)); cornerRadius=dp(16).toFloat() }
   }
   val tabBodies=mutableListOf<LinearLayout>()
   val tabIcons=mutableListOf<ModeBadge>()
   val tabLabels=mutableListOf<TextView>()
   pages.forEachIndexed { index, item ->
    val tab=LinearLayout(this).apply {
     orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER; isClickable=true
     setOnClickListener {
      // Formal remains quiet until its background request completes.
      // Do not switch the sheet or expose a loading label while they are pending.
      if(pages[index].third.isBlank()) return@setOnClickListener
      if(page!=index) { haptic(); page=index; refreshPage() }
     }
    }
    val icon=ModeBadge().apply { mode=if(item.first=="original") language.second else item.first }
    val label=TextView(this).apply { text=item.second; textSize=7f; gravity=Gravity.CENTER; isSingleLine=true; setTypeface(null,Typeface.BOLD) }
    tab.addView(icon,LinearLayout.LayoutParams(dp(27),dp(27)))
    tab.addView(label,LinearLayout.LayoutParams(-1,dp(15)))
    selector.addView(tab,LinearLayout.LayoutParams(0,dp(43),1f))
    tabBodies.add(tab); tabIcons.add(icon); tabLabels.add(label)
   }
   box.addView(selector,LinearLayout.LayoutParams(-1,dp(53)))
   refreshPage = {
    val next=pages[page]
    selectedKey=next.first; selected=next.third; content.text=selected
    tabIcons.forEachIndexed { index, icon ->
     icon.active=index==page
     tabLabels[index].setTextColor(if(index==page) teal else if(pages[index].third.isBlank()) Color.rgb(150,165,159) else Color.rgb(86,112,104))
     tabBodies[index].animate().cancel()
     tabBodies[index].scaleX=if(index==page) 1f else .92f
     tabBodies[index].scaleY=if(index==page) 1f else .92f
     tabBodies[index].animate().scaleX(1f).scaleY(1f).setDuration(170).setInterpolator(OvershootInterpolator(.6f)).start()
    }
    content.animate().cancel()
    content.alpha=0f; content.translationY=dp(7).toFloat()
    content.animate().alpha(1f).translationY(0f).setDuration(180).start()
   }
   refreshPage()
   box.addView(ScrollView(this).apply { addView(content) },LinearLayout.LayoutParams(-1,dp(155)))
   val actions=LinearLayout(this); box.addView(actions)
   fun action(label: String, primary: Boolean, onTap: () -> Unit) = TextView(this).apply {
    text=label; textSize=12f; gravity=Gravity.CENTER; setTextColor(if(primary) Color.WHITE else teal)
    background=GradientDrawable().apply { setColor(if(primary) Color.argb(222,35,91,78) else Color.argb(150,255,255,255)); cornerRadius=dp(16).toFloat() }
    setOnClickListener { haptic(); onTap() }
   }
   actions.addView(action("Close",false) { bubble() },LinearLayout.LayoutParams(0,dp(38),1f).apply { setMargins(0,0,dp(6),0) })
   actions.addView(action("Insert",true) { insert(selected) },LinearLayout.LayoutParams(0,dp(38),1f))
   // Casual is shown as soon as Sarvam returns it. The slower two style
   // rewrites arrive independently and update their tabs without blocking
   // the result sheet or the Insert action.
   worker.execute {
    try {
     val endpoint=prefs.getString("endpoint","")!!.trimEnd('/')
     val deferred=postJson("$endpoint/styles",JSONObject()
      .put("original_text",original).put("english_text",data.optString("english_text"))
      .put("source_language",sourceCode))
     val deferredStyles=deferred.optJSONObject("styles") ?: JSONObject()
     main.post {
      if(state!="results" || requestId!=resultRequest) return@post
      listOf("formal").forEach { key ->
       val value=deferredStyles.optString(key).trim()
       val index=pages.indexOfFirst { it.first==key }
       if(value.isNotEmpty() && index>=0) pages[index]=Triple(key,pages[index].second,value)
      }
      if(selectedKey=="formal") refreshPage()
     }
    } catch(e:Exception) { Log.w("VeyaAssistant","Deferred styles failed",e) }
   }
  }
 }
 private fun insert(value:String) {
  val root=rootInActiveWindow
  val node=root?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
  if(root?.packageName?.toString()!=targetPackage || node==null || !node.isEditable || node.isPassword) {
   Toast.makeText(this,"Tap the message field, then Insert again.",Toast.LENGTH_LONG).show(); return
  }
  val raw=node.text?.toString() ?: ""
  // Some messaging apps expose the visible "Message" hint as node text.
  // Treat an exact hint match as an empty composer rather than inserting after it.
  val hint=node.hintText?.toString()?.trim().orEmpty()
  val description=node.contentDescription?.toString()?.trim().orEmpty()
  val visible=raw.trim()
  val isComposerPlaceholder=listOf("message", "type a message", "write a message").any { visible.equals(it, ignoreCase=true) }
  val old=if(visible.isNotEmpty() && (visible==hint || visible==description || isComposerPlaceholder)) "" else raw
  val a=node.textSelectionStart.coerceIn(0,old.length); val b=node.textSelectionEnd.coerceIn(a,old.length)
  val merged=old.substring(0,a)+value+old.substring(b)
  val ok=node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,merged) })
  if(ok) bubble() else Toast.makeText(this,"This field does not support Insert. Use Copy instead.",Toast.LENGTH_LONG).show()
 }
}
