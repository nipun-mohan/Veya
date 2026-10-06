package app.veya.veya

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle

/** A transparent host for the system microphone prompt above the current app. */
class MicPermissionActivity : Activity() {
 override fun onCreate(savedInstanceState: Bundle?) {
  super.onCreate(savedInstanceState)
  if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
   finishAndRemoveTask()
  } else {
   requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_MICROPHONE)
  }
 }

 override fun onRequestPermissionsResult(
  requestCode: Int,
  permissions: Array<out String>,
  grantResults: IntArray,
 ) {
  super.onRequestPermissionsResult(requestCode, permissions, grantResults)
  if (requestCode == REQUEST_MICROPHONE) finishAndRemoveTask()
 }

 companion object { private const val REQUEST_MICROPHONE = 602 }
}
