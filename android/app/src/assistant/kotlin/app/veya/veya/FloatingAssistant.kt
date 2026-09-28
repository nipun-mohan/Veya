package app.veya.veya

import android.accessibilityservice.AccessibilityService
import android.animation.ValueAnimator
import android.content.*
import android.content.pm.PackageManager
import android.graphics.*
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import android.hardware.*
import android.os.*
import android.view.*
import android.view.accessibility.*
import android.view.animation.OvershootInterpolator
import android.widget.*
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
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
 private val streamClient by lazy {
  // A long dictation can legitimately outlive the REST timeout. Keep the
  // realtime channel alive until Sarvam emits its explicit final response.
  OkHttpClient.Builder()
   .connectTimeout(15, TimeUnit.SECONDS)
   .readTimeout(0, TimeUnit.MILLISECONDS)
   .pingInterval(20, TimeUnit.SECONDS)
   .build()
 }
 private val prefs by lazy { getSharedPreferences("assistant", MODE_PRIVATE) }
 private val wm by lazy { getSystemService(WINDOW_SERVICE) as WindowManager }
 private var panel: LinearLayout? = null
 private var params: WindowManager.LayoutParams? = null
 private var recorder: MediaRecorder? = null
 private var streamRecorder: AudioRecord? = null
 private var streamSocket: WebSocket? = null
 private var streamRequestId = 0
 private val streamWorker = Executors.newSingleThreadExecutor()
 private var recordingFile: File? = null
 @Volatile private var recordingAmplitude=0
 // Read by the PCM worker and written on the accessibility/main thread. A
 // foreground-app change must stop audio delivery before another frame can be
 // sent to the streaming gateway.
 @Volatile private var state = "idle"
 private var hidden = false
 private var targetPackage = ""
 private var requestId = 0
 private var pulse: ValueAnimator? = null
 private var hideTarget: TextView? = null
 private var hideTargetParams: WindowManager.LayoutParams? = null
 private val ink = Color.rgb(35, 8, 67)
 private val lime = Color.rgb(217, 242, 145)
 private val lavender = Color.rgb(236, 241, 230)
 private val teal = Color.rgb(61, 25, 92)
 private val mango = Color.rgb(255, 138, 32)
 private val reviewSurface = Color.rgb(16, 18, 19)
 private val reviewCard = Color.rgb(23, 25, 26)
 private var x = 20; private var y = 300
 private var sensor: SensorManager? = null
 private var lastShake = 0L
 private val amplitudeTicker = object : Runnable {
  override fun run() {
   if (state != "recording") return
   recordingAmplitude = runCatching { recorder?.maxAmplitude ?: recordingAmplitude }.getOrDefault(recordingAmplitude)
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
 override fun onAccessibilityEvent(event: AccessibilityEvent?) {
  // rootInActiveWindow is null while the current app is closing or Android is
  // switching to the launcher. The former refresh-only implementation returned
  // in that case, leaving a live microphone and WebSocket behind. Wait for the
  // window switch to settle, then stop an active recording unless the original
  // target is still the foreground app.
  if (
   state == "recording" && targetPackage.isNotBlank() &&
   event?.eventType in setOf(
    AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
    AccessibilityEvent.TYPE_WINDOWS_CHANGED,
   )
  ) {
   val eventPackage = event?.packageName?.toString()
   if (eventPackage != targetPackage && eventPackage != packageName) {
    main.postDelayed({
     if (state != "recording") return@postDelayed
     val foregroundPackage = rootInActiveWindow?.packageName?.toString()
     if (foregroundPackage == null || foregroundPackage != targetPackage) {
      Log.i("VeyaAssistant", "Stopping recording after target app left foreground: $foregroundPackage")
      cancel()
      remove()
      targetPackage = ""
     }
    }, 120)
   }
  }
  refresh()
 }
 override fun onInterrupt() { cancel(); remove() }
 override fun onDestroy() {
  sensor?.unregisterListener(this); cancel(); remove(); worker.shutdownNow(); streamWorker.shutdownNow(); instance = null
  if (prefs.getBoolean("returnToVeyaAfterDisable", false)) {
   prefs.edit().remove("returnToVeyaAfterDisable").apply()
   main.postDelayed({
    packageManager.getLaunchIntentForPackage(packageName)?.apply {
     addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
     startActivity(this)
    }
   }, 350)
  }
  super.onDestroy()
 }
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
 private fun recorderBackground() = GradientDrawable().apply {
  setColor(Color.rgb(255, 249, 240)); cornerRadius = dp(30).toFloat()
  setStroke(dp(1), Color.rgb(232, 218, 202))
 }
 private fun responseBackground() = GradientDrawable(
  // A deliberately visible version of the Home screen's Ready-to-go gradient.
  // The third stop gives the compact overlay depth instead of reading as flat
  // charcoal in dimmed apps.
  GradientDrawable.Orientation.TL_BR,
  intArrayOf(Color.rgb(20, 5, 39), Color.rgb(39, 12, 73), Color.rgb(61, 24, 108)),
 ).apply {
  cornerRadius = dp(20).toFloat()
 }
 private fun text(value: String, size: Float = 14f) = TextView(this).apply {
  text = value; textSize = size; setTextColor(lime); gravity = Gravity.CENTER; setPadding(dp(12), dp(10), dp(12), dp(10))
 }
 private fun button(value: String, action: () -> Unit) = text(value).apply { setOnClickListener { action() } }
 private fun circle(value:String, fillColor:Int, textColor:Int, action:()->Unit) = TextView(this).apply {
  text=value; textSize=23f; setTextColor(textColor); gravity=Gravity.CENTER
  background=GradientDrawable().apply { setColor(fillColor); shape=GradientDrawable.OVAL }
  setOnClickListener { haptic(); action() }
 }
 private fun doneCircle(fillColor: Int, action: () -> Unit) = object : View(this) {
  private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = fillColor }
  private val check = Paint(Paint.ANTI_ALIAS_FLAG).apply {
   color = ink; style = Paint.Style.STROKE; strokeWidth = dp(2).toFloat(); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
  }
  init { setOnClickListener { haptic(); action() } }
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
   text="↓  Hide"; textSize=13f; gravity=Gravity.CENTER; setTextColor(Color.WHITE); setTypeface(null,Typeface.BOLD)
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
 private inner class MovableResultSheet : LinearLayout(this@FloatingAssistant) {
  private val touchSlop = ViewConfiguration.get(this@FloatingAssistant).scaledTouchSlop
  private var startX = 0f
  private var startY = 0f
  private var initialX = 0
  private var initialY = 0
  private var dragging = false
  private var gestureStartsInText = false
  var resultScrollArea: View? = null

  private fun begin(event: MotionEvent) {
   startX = event.rawX; startY = event.rawY
   initialX = params?.x ?: 0; initialY = params?.y ?: 0
   dragging = false
   resultScrollArea?.let { area ->
    gestureStartsInText = event.x >= area.left && event.x <= area.right &&
     event.y >= area.top && event.y <= area.bottom
   } ?: run { gestureStartsInText = false }
  }
  private fun move(event: MotionEvent) {
   val lp = params ?: return
   lp.x = (initialX + event.rawX - startX).toInt().coerceIn(
    0, max(0, resources.displayMetrics.widthPixels - lp.width),
   )
   lp.y = (initialY + event.rawY - startY).toInt().coerceIn(
    dp(8), max(dp(8), resources.displayMetrics.heightPixels - (panel?.height ?: dp(60))),
   )
   panel?.let { wm.updateViewLayout(it, lp) }
  }
  override fun onInterceptTouchEvent(event: MotionEvent): Boolean = when (event.actionMasked) {
   MotionEvent.ACTION_DOWN -> { begin(event); false }
   MotionEvent.ACTION_MOVE -> {
    if (gestureStartsInText) {
     false
    } else {
     if (!dragging && hypot(event.rawX - startX, event.rawY - startY) > touchSlop) {
      dragging = true
      move(event)
     }
     dragging
    }
   }
   MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> dragging
   else -> dragging
  }
  override fun onTouchEvent(event: MotionEvent): Boolean {
   when (event.actionMasked) {
    MotionEvent.ACTION_DOWN -> begin(event)
    MotionEvent.ACTION_MOVE -> {
     if (gestureStartsInText) return true
     if (!dragging && hypot(event.rawX - startX, event.rawY - startY) > touchSlop) dragging = true
     if (dragging) move(event)
    }
    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> dragging = false
   }
   return true
  }
 }
 private inner class MiniWaveMark : View(this@FloatingAssistant) {
  private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = mango }
  private val mark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
   color = Color.rgb(19,20,21); strokeWidth = dp(3).toFloat(); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND; style = Paint.Style.STROKE
  }
  override fun onDraw(canvas: Canvas) {
   val size=min(width,height).toFloat(); val cx=width/2f; val cy=height/2f
   canvas.drawCircle(cx,cy,size*.47f,fill)
   val v=Path().apply { moveTo(cx-size*.22f,cy-size*.13f); lineTo(cx,cy+size*.20f); lineTo(cx+size*.22f,cy-size*.13f) }
   canvas.drawPath(v,mark)
   canvas.drawLine(cx-size*.18f,cy+size*.25f,cx+size*.18f,cy+size*.25f,mark)
  }
 }
 private inner class StyleGlyph(private val kind: String, private val nativeGlyph: String = "") : View(this@FloatingAssistant) {
  private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { style=Paint.Style.STROKE; strokeWidth=dp(2).toFloat(); strokeCap=Paint.Cap.ROUND; strokeJoin=Paint.Join.ROUND }
  private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign=Paint.Align.CENTER; setTypeface(Typeface.DEFAULT_BOLD) }
  private var selectedAt = 0L
  var active = false
   set(value) { field=value; if(value) selectedAt=SystemClock.uptimeMillis(); invalidate() }
  override fun onDraw(canvas: Canvas) {
   val animateFor=(SystemClock.uptimeMillis()-selectedAt).coerceAtMost(260)
   val pulse=if(active) sin(animateFor / 260.0 * Math.PI).toFloat()*.10f else 0f
   val color=if(active) Color.rgb(26,20,9) else Color.rgb(238,239,235)
   line.color=color; fill.color=color
   canvas.save(); canvas.scale(1f+pulse,1f+pulse,width/2f,height/2f)
   val cx=width/2f; val cy=height/2f; val u=min(width,height).toFloat()
   when(kind) {
    "casual" -> {
     canvas.drawRoundRect(RectF(cx-u*.29f,cy-u*.22f,cx+u*.29f,cy+u*.22f),u*.13f,u*.13f,line)
     canvas.drawLine(cx-u*.10f,cy+u*.22f,cx-u*.18f,cy+u*.32f,line)
     listOf(-.09f,0f,.09f).forEach { offset -> canvas.drawLine(cx-u*.13f,cy+u*offset,cx+u*.13f,cy+u*offset,line) }
    }
    "formal" -> {
     val page=Path().apply {
      moveTo(cx-u*.22f,cy-u*.30f); lineTo(cx+u*.08f,cy-u*.30f); lineTo(cx+u*.22f,cy-u*.16f)
      lineTo(cx+u*.22f,cy+u*.30f); lineTo(cx-u*.22f,cy+u*.30f); close()
     }
     canvas.drawPath(page,line)
     canvas.drawLine(cx+u*.08f,cy-u*.30f,cx+u*.08f,cy-u*.16f,line)
     canvas.drawLine(cx+u*.08f,cy-u*.16f,cx+u*.22f,cy-u*.16f,line)
     listOf(-.06f,.08f,.20f).forEach { offset -> canvas.drawLine(cx-u*.12f,cy+u*offset,cx+u*.11f,cy+u*offset,line) }
    }
    else -> {
     canvas.drawCircle(cx,cy,u*.27f,line)
     canvas.drawOval(RectF(cx-u*.12f,cy-u*.27f,cx+u*.12f,cy+u*.27f),line)
     canvas.drawLine(cx-u*.25f,cy,cx+u*.25f,cy,line)
    }
   }
   canvas.restore()
  if(active && animateFor<260) postInvalidateDelayed(16)
 }
}
 private inner class CopyGlyph : View(this@FloatingAssistant) {
  private val line=Paint(Paint.ANTI_ALIAS_FLAG).apply {
   color=Color.rgb(238,239,235); style=Paint.Style.STROKE; strokeWidth=dp(2).toFloat()
   strokeJoin=Paint.Join.ROUND
  }
  override fun onDraw(canvas: Canvas) {
   val u=min(width,height).toFloat(); val inset=u*.25f; val offset=u*.13f
   canvas.drawRoundRect(RectF(inset-offset,inset+offset,u-inset-offset,u-inset+offset),u*.10f,u*.10f,line)
   canvas.drawRoundRect(RectF(inset+offset,inset-offset,u-inset+offset,u-inset-offset),u*.10f,u*.10f,line)
  }
 }
  private inner class CloseGlyph : View(this@FloatingAssistant) {
  private val line=Paint(Paint.ANTI_ALIAS_FLAG).apply {
   color=Color.rgb(238,239,235); style=Paint.Style.STROKE; strokeWidth=dp(3).toFloat()
   strokeCap=Paint.Cap.ROUND
  }
  override fun onDraw(canvas: Canvas) {
   val inset=min(width,height)*.28f
   canvas.drawLine(inset,inset,width-inset,height-inset,line)
   canvas.drawLine(width-inset,inset,inset,height-inset,line)
  }
 }
 private fun showResultSheet(content: (LinearLayout) -> Unit) {
  remove()
  val screenWidth = resources.displayMetrics.widthPixels
  val sideMargin = dp(12)
  val sheetWidth = screenWidth - sideMargin * 2
  val view = MovableResultSheet().apply {
   orientation = LinearLayout.VERTICAL
   background = responseBackground()
   elevation = dp(18).toFloat()
   // Reader and dialog share an edge with no empty top or bottom band.
   setPadding(0, 0, 0, 0)
  }
  content(view)
  view.measure(
   View.MeasureSpec.makeMeasureSpec(sheetWidth, View.MeasureSpec.EXACTLY),
   View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
  )
  val lp = WindowManager.LayoutParams(
   sheetWidth,
   WindowManager.LayoutParams.WRAP_CONTENT,
   WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
   PixelFormat.TRANSLUCENT,
  ).apply {
   gravity = Gravity.TOP or Gravity.LEFT
   x = sideMargin
   y = dp(28)
   flags = flags or WindowManager.LayoutParams.FLAG_DIM_BEHIND
   dimAmount = .62f
  }
  panel = view; params = lp; wm.addView(view, lp)
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
   addView(orb, LinearLayout.LayoutParams((dp(54)*scale).roundToInt(), (dp(54)*scale).roundToInt()))
  }
  val lp = WindowManager.LayoutParams((dp(64)*scale).roundToInt(), (dp(64)*scale).roundToInt(), WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL, PixelFormat.TRANSLUCENT).apply {
    gravity=Gravity.TOP or Gravity.LEFT; x=this@FloatingAssistant.x; y=this@FloatingAssistant.y
  }
  frame.alpha=opacity
  panel = frame; params = lp
  wm.addView(frame, lp)
  draggable(orb) { startRecording() }
 }
 private inner class Orb(private val active:Boolean): View(this@FloatingAssistant) {
  private val mango=Color.rgb(255, 157, 27)
  private val deepInk=Color.rgb(27, 7, 52)
  private val fill=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=mango }
  private val bar=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=deepInk; strokeWidth=dp(5).toFloat(); strokeCap=Paint.Cap.ROUND }
  override fun onDraw(c:Canvas) {
   // The in-app assistant is the circular companion to the launcher tile:
   // same Mango Ink palette and the same five-bar V-wave geometry.
   val u=min(width.toFloat()/dp(54),height.toFloat()/dp(54))
   fun unit(value:Int)=dp(value)*u
   c.drawCircle(width / 2f, height / 2f, min(width, height) / 2f, fill)
   val time=SystemClock.uptimeMillis()/130.0
   val tops=floatArrayOf(.31f, .44f, .57f, .44f, .31f)
   val baseHeight=height*.31f
   bar.strokeWidth=unit(5)
   for(i in 0..4) {
    val pulse=if(active) (abs(sin(time+i*.8))*unit(5)).toFloat() else 0f
    val xx=width*(.21f+i*.14f)
    val top=height*tops[i]-pulse*.45f
    c.drawLine(xx,top,xx,top+baseHeight+pulse,bar)
   }
   if(active) postInvalidateDelayed(45)
  }
 }
 private fun cancel() {
  requestId++
  main.removeCallbacks(amplitudeTicker)
  streamSocket?.send(JSONObject().put("event", "cancel").toString())
  streamSocket?.close(1000, "cancelled"); streamSocket=null
  streamRecorder?.let { runCatching { it.stop() }; it.release() }; streamRecorder=null
  recorder?.let { runCatching { it.stop() }; it.release() }; recorder=null; recordingFile?.delete(); recordingFile=null; recordingAmplitude=0; state="idle"
 }
 private fun startRecording() {
  if(state!="idle") return
  if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
   // Runtime permissions need an Activity. This transparent activity shows
   // only Android's microphone prompt over the current app, then closes.
   Intent(this, MicPermissionActivity::class.java).apply {
    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
    startActivity(this)
   }
   return
  }
  try {
   if(prefs.getString("endpoint", "").isNullOrBlank()) error("Set the translation service in Veya Settings.")
   ++requestId
   // Set the state before the asynchronous WebSocket can open.  Previously a
   // quick connection could observe "idle" in onOpen and cancel itself.
   state="recording"
   startSarvamStream(requestId)
   recorderControls(); main.post(amplitudeTicker)
  } catch(e: Exception) { Log.e("VeyaAssistant", "Floating recorder startup failed", e); cancel(); failure("Could not start recording. Open Veya once, then try again.") }
 }

 private fun startSarvamStream(id: Int) {
  val endpoint=prefs.getString("endpoint", "")!!.trimEnd('/')
  val language=prefs.getString("language","en-IN")!!
  val streamEndpoint=when {
   endpoint.startsWith("https://") -> "wss://${endpoint.removePrefix("https://")}"
   endpoint.startsWith("http://") -> "ws://${endpoint.removePrefix("http://")}"
   else -> endpoint
  }
  val bufferSize=AudioRecord.getMinBufferSize(
   16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
  ).coerceAtLeast(3200)
  streamRecorder=AudioRecord(
   MediaRecorder.AudioSource.MIC, 16000, AudioFormat.CHANNEL_IN_MONO,
   AudioFormat.ENCODING_PCM_16BIT, bufferSize * 2,
  )
  if(streamRecorder?.state != AudioRecord.STATE_INITIALIZED) error("Could not start the microphone.")
  streamRequestId=id
  val request=Request.Builder()
   .url("$streamEndpoint/stream?source_language=${java.net.URLEncoder.encode(language, "UTF-8")}")
   // Accessibility services can outlive the token cached by Flutter. Refresh
   // it before opening the long-lived authenticated stream.
   .apply { activeFirebaseToken(forceRefresh=true)?.let { header("Authorization", "Bearer $it") } }
   .build()
  streamSocket=streamClient.newWebSocket(request, object : WebSocketListener() {
   override fun onOpen(socket: WebSocket, response: Response) {
    if(id != streamRequestId || state != "recording") {
     socket.send(JSONObject().put("event", "cancel").toString()); socket.close(1000,"cancelled"); return
    }
    val audio=streamRecorder ?: return
    runCatching { audio.startRecording() }.onFailure { error ->
     Log.e("VeyaAssistant", "PCM recorder startup failed", error)
     main.post { if(id == streamRequestId) { cancel(); failure("Could not start the microphone.") } }
     return
    }
    streamWorker.execute {
     val chunk=ByteArray(3200) // 100 ms of mono linear16 at 16 kHz.
     while(state == "recording" && id == streamRequestId && streamRecorder === audio) {
      val count=audio.read(chunk,0,chunk.size)
      if(count <= 0) continue
      var peak=0
      var index=0
      while(index + 1 < count) {
       val sample=((chunk[index].toInt() and 0xff) or (chunk[index + 1].toInt() shl 8))
       peak=max(peak, abs(sample.toShort().toInt())); index += 2
      }
      recordingAmplitude=peak
      val encoded=android.util.Base64.encodeToString(
       chunk.copyOf(count), android.util.Base64.NO_WRAP,
      )
      if(!socket.send(JSONObject().put("event", "audio").put("audio", encoded).toString())) break
     }
    }
   }
   override fun onMessage(socket: WebSocket, text: String) {
    val data=runCatching { JSONObject(text) }.getOrNull() ?: return
    when(data.optString("type")) {
     "partial" -> Log.d("VeyaAssistant", "Sarvam partial: ${data.optString("text")}")
     "result" -> main.post {
      if(id == streamRequestId) { streamSocket=null; results(data) }
     }
     "error" -> main.post {
      if(id == streamRequestId) { streamSocket=null; failure(data.optString("message", "We couldn't process that recording. Please try again.")) }
     }
    }
   }
   override fun onFailure(socket: WebSocket, throwable: Throwable, response: Response?) {
    Log.e("VeyaAssistant", "Sarvam stream failed", throwable)
    main.post {
     if(id == streamRequestId && state != "idle") {
      streamSocket=null
      failure("We couldn't process that recording. Please try again.")
     }
    }
   }
   override fun onClosing(socket: WebSocket, code: Int, reason: String) {
    socket.close(code, reason)
    main.post {
     if(id == streamRequestId && state == "generating") {
      streamSocket=null
      failure("The transcription stream closed before completing. Please try again.")
     }
    }
   }
   override fun onClosed(socket: WebSocket, code: Int, reason: String) {
    main.post {
     if(id == streamRequestId && state == "generating") {
      streamSocket=null
      failure("The transcription stream closed before completing. Please try again.")
     }
    }
   }
  })
 }
 private fun recorderControls() {
  remove()
  val row=LinearLayout(this).apply {
   gravity=Gravity.CENTER_VERTICAL; setPadding(dp(8),dp(8),dp(8),dp(8)); background=recorderBackground(); elevation=dp(10).toFloat()
  }
  val lp=WindowManager.LayoutParams(dp(236),dp(68),WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,PixelFormat.TRANSLUCENT).apply { gravity=Gravity.TOP or Gravity.LEFT; x=this@FloatingAssistant.x; y=this@FloatingAssistant.y }
  val close=circle("×",Color.rgb(247,232,217),ink) { cancel(); bubble() }
  row.addView(close,LinearLayout.LayoutParams(dp(48),dp(48)))
  val capsule=Wave().apply { background=GradientDrawable().apply { setColor(ink); cornerRadius=dp(24).toFloat() }; setPadding(dp(8),0,dp(8),0) }
  row.addView(capsule,LinearLayout.LayoutParams(0,dp(48),1f).apply { setMargins(dp(10),0,dp(10),0) })
  row.addView(doneCircle(Color.rgb(255,157,27)) { finishRecording() },LinearLayout.LayoutParams(dp(48),dp(48)))
  panel=row; params=lp; wm.addView(row,lp); draggable(capsule)
 }
 private fun generatingControls() {
  remove()
  val row=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL; setPadding(dp(8),dp(8),dp(8),dp(8)); background=recorderBackground(); elevation=dp(10).toFloat() }
  val lp=WindowManager.LayoutParams(dp(236),dp(68),WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
   WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,PixelFormat.TRANSLUCENT).apply { gravity=Gravity.TOP or Gravity.LEFT; x=this@FloatingAssistant.x; y=this@FloatingAssistant.y }
  val close=circle("×",Color.rgb(247,232,217),ink) { cancel(); bubble() }
  row.addView(close,LinearLayout.LayoutParams(dp(48),dp(48)))
  val capsule=Wave().apply { background=GradientDrawable().apply { setColor(ink); cornerRadius=dp(24).toFloat() } }
  row.addView(capsule,LinearLayout.LayoutParams(0,dp(48),1f).apply { setMargins(dp(10),0,dp(10),0) })
  row.addView(Spinner(Color.rgb(255,157,27)),LinearLayout.LayoutParams(dp(48),dp(48)))
  panel=row; params=lp; wm.addView(row,lp)
 }
 private inner class Spinner(private val backgroundColor: Int) : View(this@FloatingAssistant) {
  private val fill=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=backgroundColor }
  private val arc=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=ink; style=Paint.Style.STROKE; strokeWidth=dp(3).toFloat(); strokeCap=Paint.Cap.ROUND }
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
   fill.color=if(active) Color.rgb(255,157,27) else Color.rgb(255,249,240)
   line.color=ink
   glyph.color=ink
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
  private val arrow=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=ink; style=Paint.Style.STROKE; strokeWidth=dp(2).toFloat(); strokeCap=Paint.Cap.ROUND; strokeJoin=Paint.Join.ROUND }
  init { setOnClickListener { haptic(); action() } }
  override fun onDraw(canvas: Canvas) {
   val cx=width/2f; val cy=height/2f; canvas.drawCircle(cx,cy,min(width,height)/2f,fill)
   val path=Path().apply { if(direction<0) { moveTo(cx+dp(4),cy-dp(7)); lineTo(cx-dp(4),cy); lineTo(cx+dp(4),cy+dp(7)) } else { moveTo(cx-dp(4),cy-dp(7)); lineTo(cx+dp(4),cy); lineTo(cx-dp(4),cy+dp(7)) } }
   canvas.drawPath(path,arrow)
  }
 }
 private inner class Wave: View(this@FloatingAssistant) {
  private val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.rgb(255, 190, 78); strokeWidth=dp(3).toFloat(); strokeCap=Paint.Cap.ROUND }
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
  main.removeCallbacks(amplitudeTicker)
  streamRecorder?.let { runCatching { it.stop() }; it.release() }; streamRecorder=null
  recordingAmplitude=0
  state="generating"
  generatingControls()
  streamSocket?.send(JSONObject().put("event", "finish").toString())
 }
 private fun processRecording(id:Int, file:File) {
  try {
   val endpoint=prefs.getString("endpoint", "")!!.trimEnd('/')
   val language=prefs.getString("language","en-IN")!!
   Log.i("VeyaAssistant","Processing request: endpoint=$endpoint selectedLanguage=$language")
   val result=postRecording("$endpoint/process",file,language)
   main.post { if(id==requestId) results(result) }
  } catch(e: Exception) {
   Log.e("VeyaAssistant","Recording processing failed",e)
   main.post {
    if(id==requestId) {
     failure(if (e.message?.contains("401") == true || e.message?.contains("403") == true || e.message?.contains("session has expired", ignoreCase = true) == true)
      "Your Veya session needs to be refreshed. Open Veya and try again."
      else "We couldn't process that recording. Please try again.")
    }
   }
  } finally { file.delete(); if(recordingFile==file) recordingFile=null }
 }
 private fun postRecording(url:String, file:File, language:String):JSONObject {
  val requestBody=file.asRequestBody("audio/mp4".toMediaType())
  fun requestFor(token: String?) = Request.Builder()
   .url(url.removeSuffix("/process") + "/process-audio")
   .header("X-Veya-Source-Language", language)
   .apply { token?.takeIf { it.isNotBlank() }?.let { header("Authorization", "Bearer $it") } }
   .post(requestBody)
   .build()
  val started=SystemClock.elapsedRealtime()
  var response=httpClient.newCall(requestFor(activeFirebaseToken())).execute()
  if(response.code==401 || response.code==403) {
   response.close()
   // A background accessibility service may outlive the token supplied by
   // Flutter. Refresh the persisted Firebase session and retry once.
   response=httpClient.newCall(requestFor(activeFirebaseToken(forceRefresh=true))).execute()
  }
  response.use { response ->
   val raw=response.body?.string().orEmpty()
   val data=runCatching { JSONObject(raw) }.getOrElse { JSONObject() }
   Log.i("VeyaAssistant","OkHttp upload + processing: ${SystemClock.elapsedRealtime()-started}ms; protocol=${response.protocol}")
   if(!response.isSuccessful) error(data.optString("detail", "Translation service failed (${response.code})."))
   return data
  }
 }
 private fun activeFirebaseToken(forceRefresh: Boolean=false): String? {
  val refreshed=runCatching {
   val user=FirebaseAuth.getInstance().currentUser ?: return@runCatching null
   Tasks.await(user.getIdToken(forceRefresh),20,TimeUnit.SECONDS).token
  }.getOrNull()
  if(!refreshed.isNullOrBlank()) prefs.edit().putString("firebaseIdToken",refreshed).apply()
  return refreshed ?: prefs.getString("firebaseIdToken","")?.takeIf { it.isNotBlank() }
 }
 private fun postJson(url: String, body: JSONObject): JSONObject {
  // Style text is safe JSON. The normal endpoint avoids edge WAF rejection of
  // opaque payloads before they reach the authenticated Cloud Run service.
  fun requestFor(token: String?) = Request.Builder().url(url)
   .post(body.toString().toRequestBody("application/json".toMediaType()))
   .apply { token?.takeIf { it.isNotBlank() }?.let { header("Authorization", "Bearer $it") } }
   .build()
  // Style generation runs after the result panel opens, so its cached Firebase
  // token can be stale even when the recording stream was authenticated.
  var response=httpClient.newCall(requestFor(activeFirebaseToken())).execute()
  if(response.code==401 || response.code==403) {
   response.close()
   response=httpClient.newCall(requestFor(activeFirebaseToken(forceRefresh=true))).execute()
  }
  response.use { response ->
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
  val detected=data.optString("detected_language", "unknown")
  val casual=styles.optString("casual",data.optString("english_text"))
  Log.i(
   "VeyaAssistant",
   "Result metadata: detectedLanguage=$detected selectedLanguage=$sourceCode " +
    "originalChars=${original.length} originalLatin=${original.count { it.isLetter() && it.code < 128 }} " +
    "casualChars=${casual.length} casualLatin=${casual.count { it.isLetter() && it.code < 128 }}",
  )
  val language=languageLabels(sourceCode)
  showResultSheet { box ->
   val pages=mutableListOf<Triple<String,String,String>>().apply {
    add(Triple("casual","Casual",styles.optString("casual",data.optString("english_text"))))
    add(Triple("formal","Formal",styles.optString("formal", casual)))
    add(Triple("original",language.second,original))
   }
   var page=0
   lateinit var refreshPage: () -> Unit
   fun rounded(fill:Int, radius:Int=18, stroke:Int?=null, strokeWidth:Int=1) = GradientDrawable().apply {
    setColor(fill); cornerRadius=dp(radius).toFloat()
    stroke?.let { setStroke(dp(strokeWidth),it) }
   }
   fun layeredSurface(
    from: Int,
    to: Int,
    radius: Int = 18,
    stroke: Int = Color.rgb(110, 69, 149),
   ) = GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(from, to)).apply {
    cornerRadius=dp(radius).toFloat()
    setStroke(dp(1),stroke)
   }
   val content=TextView(this).apply {
    text=selected; textSize=13f; gravity=Gravity.START; setTextColor(Color.rgb(246,246,242)); setTypeface(null,Typeface.NORMAL)
    setLineSpacing(dp(3).toFloat(),1f); setPadding(dp(12),dp(11),dp(42),dp(10))
   }
   val resultScroller=ScrollView(this).apply {
    addView(content)
    isVerticalScrollBarEnabled=true; isScrollbarFadingEnabled=false
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
     verticalScrollbarThumbDrawable=rounded(mango,4)
     verticalScrollbarTrackDrawable=rounded(Color.rgb(64,66,67),4)
    }
    setOnTouchListener { _, event ->
     when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> box.requestDisallowInterceptTouchEvent(true)
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> box.requestDisallowInterceptTouchEvent(false)
     }
     false
    }
   }
   val viewer=FrameLayout(this).apply {
    // The reader follows the parent gradient instead of dropping into a
    // disconnected black rectangle, while remaining dark enough for text.
    // Avoid a stroke so the tab bridge remains a clean opening into the reader.
    background=layeredSurface(Color.rgb(26,10,48), Color.rgb(47,18,82), 20, Color.TRANSPARENT)
    elevation=dp(5).toFloat()
   }
   viewer.addView(resultScroller,FrameLayout.LayoutParams(-1,-1).apply { bottomMargin=dp(40) })
   // Keep the close affordance inside the reader itself.  It is a text glyph,
   // not an outlined chip, so it remains crisp on every overlay background.
   val close=TextView(this).apply {
    text="×"; textSize=27f; gravity=Gravity.CENTER
    setTextColor(Color.rgb(255,250,244)); setTypeface(null,Typeface.BOLD)
    contentDescription="Close"
    elevation=dp(12).toFloat()
    setOnClickListener { haptic(); bubble() }
   }
   viewer.addView(close,FrameLayout.LayoutParams(dp(38),dp(38),Gravity.TOP or Gravity.RIGHT).apply {
    topMargin=dp(2); rightMargin=dp(3)
   })
   content.measure(
    View.MeasureSpec.makeMeasureSpec(resources.displayMetrics.widthPixels-dp(40),View.MeasureSpec.EXACTLY),
    View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED),
   )
   // Three roomy vertical tabs need a taller minimum to keep their icons and
   // labels fully visible at every text length.
   val viewerHeight=(content.measuredHeight+dp(70)).coerceIn(dp(210),dp(242))
   (box as? MovableResultSheet)?.resultScrollArea = viewer

   val grid=LinearLayout(this).apply {
   orientation=LinearLayout.VERTICAL
    gravity=Gravity.CENTER
    // Tabs have their own surface so their labels and icons can breathe.
    setPadding(dp(6),dp(8),dp(6),dp(8))
    background=layeredSurface(Color.rgb(31,9,56), Color.rgb(50,18,88),20,Color.rgb(90,53,128))
    elevation=dp(5).toFloat()
    clipChildren=false
   }
   val cards=mutableListOf<FrameLayout>()
   val cardIcons=mutableListOf<StyleGlyph>()
   val iconShells=mutableListOf<FrameLayout>()
   val cardLabels=mutableListOf<TextView>()
   pages.forEachIndexed { index, item ->
     val card=FrameLayout(this).apply {
      isClickable=true; isFocusable=true
      setOnClickListener { if(page!=index) { haptic(); page=index; refreshPage() } }
     }
     val body=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; gravity=Gravity.CENTER }
     val icon=StyleGlyph(item.first,language.second)
     val iconShell=FrameLayout(this).apply { foregroundGravity=Gravity.CENTER }
     iconShell.addView(icon,FrameLayout.LayoutParams(dp(30),dp(30),Gravity.CENTER))
     val label=TextView(this).apply { text=item.second; textSize=9f; gravity=Gravity.CENTER; isSingleLine=true; setTypeface(null,Typeface.BOLD) }
     body.addView(iconShell,LinearLayout.LayoutParams(dp(42),dp(38)).apply {
      gravity=Gravity.CENTER_HORIZONTAL; topMargin=dp(3); bottomMargin=dp(3)
     })
     body.addView(label,LinearLayout.LayoutParams(-1,dp(12)))
     card.addView(body,FrameLayout.LayoutParams(-1,-1))
     cards.add(card); cardIcons.add(icon); iconShells.add(iconShell); cardLabels.add(label)
     grid.addView(card,LinearLayout.LayoutParams(-1,0,1f).apply {
      if(index<pages.lastIndex) bottomMargin=dp(6)
     })
   }
   // Separate surfaces keep the style controls airy while the reader remains
   // focused on the selected text.
   val resultBody=FrameLayout(this).apply { clipChildren=false; clipToPadding=false }
   val tabBridge=View(this).apply {
    background=rounded(Color.rgb(42,15,75),7)
   }
   resultBody.addView(viewer,FrameLayout.LayoutParams(-1,viewerHeight).apply { leftMargin=dp(76) })
   // This bridge spans the container gap, making the active tab visibly open
   // into the text it controls.
   resultBody.addView(tabBridge,FrameLayout.LayoutParams(dp(10),dp(34)).apply { leftMargin=dp(68) })
   resultBody.addView(grid,FrameLayout.LayoutParams(dp(72),viewerHeight))
   box.addView(resultBody,LinearLayout.LayoutParams(-1,viewerHeight))

   refreshPage = {
    val next=pages[page]
    selectedKey=next.first; selected=next.third; content.text=selected
    resultScroller.scrollTo(0,0)
    cards.forEachIndexed { index, card ->
     val active=index==page
     // Selection lives on the icon and label only—never on a large purple tile.
     card.background=ColorDrawable(Color.TRANSPARENT)
     iconShells[index].background=if(active) rounded(mango,14) else rounded(Color.rgb(31,9,56),14)
     iconShells[index].elevation=if(active) dp(5).toFloat() else 0f
     cardIcons[index].active=active
     cardLabels[index].setTextColor(if(active) mango else Color.rgb(244,244,241))
     card.animate().cancel()
     card.translationY=if(active) -dp(2).toFloat() else 0f
     card.scaleX=if(active) 1.035f else 1f
     card.scaleY=if(active) 1.035f else 1f
     card.animate().translationY(0f).scaleX(1f).scaleY(1f).setDuration(190).setInterpolator(OvershootInterpolator(.75f)).start()
    }
    val bridgeLp=tabBridge.layoutParams as FrameLayout.LayoutParams
    bridgeLp.topMargin=page*(viewerHeight/pages.size)+(viewerHeight/pages.size-dp(34))/2
    tabBridge.layoutParams=bridgeLp
    tabBridge.pivotX=0f; tabBridge.scaleX=0f; tabBridge.alpha=.35f
    tabBridge.animate().alpha(1f).scaleX(1f).setDuration(220).setInterpolator(OvershootInterpolator(.8f)).start()
    content.animate().cancel(); content.alpha=0f; content.translationY=dp(5).toFloat()
    content.animate().alpha(1f).translationY(0f).setDuration(150).start()
   }
   refreshPage()

   val footer=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL }
   val copy=CopyGlyph().apply {
    contentDescription="Copy message"
    setOnClickListener {
     haptic()
     (getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(
      android.content.ClipData.newPlainText("Veya message",selected)
     )
     Toast.makeText(this@FloatingAssistant,"Copied",Toast.LENGTH_SHORT).show()
    }
   }
   footer.addView(copy,LinearLayout.LayoutParams(dp(28),dp(28)))
   footer.addView(Space(this),LinearLayout.LayoutParams(0,dp(1),1f))
   val insert=TextView(this).apply {
    text="Insert"; textSize=13f; gravity=Gravity.CENTER; setTextColor(Color.rgb(26,20,9)); setTypeface(null,Typeface.BOLD)
    // Keep the action and the active style state on the one Mango accent.
    background=rounded(mango,25); setOnClickListener { haptic(); insert(selected) }
   }
   footer.addView(insert,LinearLayout.LayoutParams(dp(66),dp(30)))
   // Keep actions within the reader so each selected tab is a self-contained
   // review panel: read, scroll, copy, or insert without another footer.
   viewer.addView(footer,FrameLayout.LayoutParams(-1,dp(36),Gravity.BOTTOM).apply {
    leftMargin=dp(8); rightMargin=dp(8); bottomMargin=dp(4)
   })
   // The streaming gateway already returns the final Casual and Formal
   // rewrites together with the result. No second request is needed here.
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
