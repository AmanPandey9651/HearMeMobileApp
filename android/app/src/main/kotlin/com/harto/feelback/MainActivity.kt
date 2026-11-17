package com.harto.feelback

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Process
import android.os.Build
import android.util.Rational
import android.view.WindowManager
import android.app.Activity.ScreenCaptureCallback
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    private lateinit var voiceFx: VoiceFxEngine
    private var privacyEventSink: EventChannel.EventSink? = null
    private var screenCaptureCallback: Any? = null // ScreenCaptureCallback (API 34+)
    private var mediaObserver: android.database.ContentObserver? = null
    private var callAudioRecorder: CallAudioRecorder? = null
    private var pipMethodChannel: MethodChannel? = null
    private var isPipEligible = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            com.harto.feelback.ringtone.NativeRingtoneManager.stop(this)
        } catch (_: Exception) {}
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onResume() {
        super.onResume()
        try {
            com.harto.feelback.ringtone.NativeRingtoneManager.stop(this)
        } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        try {
            com.harto.feelback.ringtone.NativeRingtoneManager.stop(this)
        } catch (_: Exception) {}
    }

    override fun onStart() {
        super.onStart()
        registerScreenCaptureDetection()
    }

    override fun onStop() {
        unregisterScreenCaptureDetection()
        super.onStop()
    }

    private fun registerScreenCaptureDetection() {
        if (Build.VERSION.SDK_INT >= 34) {
            // Android 14+: Use ScreenCaptureCallback — reliable, fires even when FLAG_SECURE blocks it
            val callback = ScreenCaptureCallback {
                runOnUiThread {
                    privacyEventSink?.success(mapOf("type" to "SCREENSHOT_ATTEMPT", "platform" to "android"))
                }
            }
            try {
                registerScreenCaptureCallback(mainExecutor, callback)
                screenCaptureCallback = callback
            } catch (_: Exception) {}
        } else {
            // Android 13 and below: Watch MediaStore for new screenshots via ContentObserver
            val resolver = contentResolver
            val screenshotUri = android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val observer = object : android.database.ContentObserver(android.os.Handler(mainLooper)) {
                override fun onChange(selfChange: Boolean, uri: android.net.Uri?) {
                    super.onChange(selfChange, uri)
                    // Check if the new image is in Screenshots folder
                    if (uri != null) {
                        try {
                            resolver.query(
                                uri,
                                arrayOf(android.provider.MediaStore.Images.Media.DISPLAY_NAME, android.provider.MediaStore.Images.Media.RELATIVE_PATH),
                                null, null, "${android.provider.MediaStore.Images.Media.DATE_ADDED} DESC"
                            )?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    val path = cursor.getString(cursor.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.RELATIVE_PATH)) ?: ""
                                    if (path.lowercase().contains("screenshot")) {
                                        runOnUiThread {
                                            privacyEventSink?.success(mapOf("type" to "SCREENSHOT_ATTEMPT", "platform" to "android"))
                                        }
                                    }
                                }
                            }
                        } catch (_: Exception) {}
                    }
                }
            }
            try {
                resolver.registerContentObserver(screenshotUri, true, observer)
                mediaObserver = observer
            } catch (_: Exception) {}
        }
    }

    private fun unregisterScreenCaptureDetection() {
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                val callback = screenCaptureCallback
                if (callback is ScreenCaptureCallback) {
                    unregisterScreenCaptureCallback(callback)
                }
            } catch (_: Exception) {}
            screenCaptureCallback = null
        } else {
            try { mediaObserver?.let { contentResolver.unregisterContentObserver(it) } } catch (_: Exception) {}
            mediaObserver = null
        }
    }

    private fun updateAutoPiP(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val paramsBuilder = PictureInPictureParams.Builder()
                paramsBuilder.setAspectRatio(Rational(9, 16))
                paramsBuilder.setAutoEnterEnabled(enabled)
                setPictureInPictureParams(paramsBuilder.build())
            } catch (e: Exception) {
                android.util.Log.w("MainActivity", "Failed setting auto-enter PiP: ${e.message}")
            }
        }
    }

    private fun triggerPiP(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
                return false
            }
            try {
                // Temporarily clear FLAG_SECURE so video renders inside floating PiP window
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(9, 16))
                    .build()
                return enterPictureInPictureMode(params)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "enterPictureInPictureMode error: ${e.message}")
            }
        }
        return false
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isPipEligible && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            triggerPiP()
        }
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            // Restoring from PiP back to full app: restore secure flag
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        runOnUiThread {
            pipMethodChannel?.invokeMethod("onPictureInPictureChanged", mapOf("isPip" to isInPictureInPictureMode))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voiceFx = VoiceFxEngine(this)

        pipMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "talkstrangers/pip")
        pipMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "enableAutoPiP" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isPipEligible = enabled
                    updateAutoPiP(enabled)
                    result.success(true)
                }
                "enterPiP" -> {
                    val ok = triggerPiP()
                    result.success(ok)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "talkstrangers/voice_fx")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCapture" -> {
                        val filter = call.argument<String>("filter") ?: "NORMAL"
                        try {
                            voiceFx.startCapture(filter)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("VOICE_FX_START", e.message, null)
                        }
                    }
                    "setFilter" -> {
                        voiceFx.filter = call.argument<String>("filter") ?: "NORMAL"
                        result.success(null)
                    }
                    "playPcm" -> {
                        val data = call.arguments as? ByteArray
                        if (data != null) voiceFx.enqueuePlayback(data)
                        result.success(null)
                    }
                    "stopCapture" -> {
                        voiceFx.stopCapture()
                        result.success(null)
                    }
                    "stopPlayback" -> {
                        voiceFx.stopPlayback()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "talkstrangers/voice_fx_frames")
            .setStreamHandler(voiceFx)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "talkstrangers/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.argument<Boolean>("secure") ?: false
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // EventChannel: privacy alerts (screenshot/screen-recording attempts) → Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "talkstrangers/privacy_alerts")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    privacyEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    privacyEventSink = null
                }
            })

        // MethodChannel: Call Audio Recording (Respects Admin Governance)
        callAudioRecorder = CallAudioRecorder(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "talkstrangers/call_recording")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRecordingFilePath" -> {
                        val sessionId = call.argument<String>("sessionId") ?: "call"
                        val ext = call.argument<String>("ext") ?: ".mp4"
                        val dir = java.io.File(cacheDir, "recordings")
                        if (!dir.exists()) dir.mkdirs()
                        val fileName = "rec_${sessionId}_${System.currentTimeMillis()}$ext"
                        val path = java.io.File(dir, fileName).absolutePath
                        result.success(path)
                    }
                    "startAudioRecording" -> {
                        val sessionId = call.argument<String>("sessionId") ?: "call"
                        val dir = java.io.File(cacheDir, "recordings")
                        if (!dir.exists()) dir.mkdirs()
                        val fileName = "rec_${sessionId}_${System.currentTimeMillis()}.mp4"
                        val filePath = java.io.File(dir, fileName).absolutePath
                        val ok = callAudioRecorder?.start(filePath) ?: false
                        if (ok) {
                            result.success(filePath)
                        } else {
                            result.error("RECORDING_START_FAILED", "Could not start audio recorder", null)
                        }
                    }
                    "stopAudioRecording" -> {
                        val path = callAudioRecorder?.stop()
                        result.success(path)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (::voiceFx.isInitialized) voiceFx.shutdown()
        callAudioRecorder?.stop()
        super.onDestroy()
    }
}

private class CallAudioRecorder(private val context: android.content.Context) {
    private var recorder: android.media.MediaRecorder? = null
    private var currentFilePath: String? = null

    fun start(filePath: String): Boolean {
        stop()
        val file = java.io.File(filePath)
        file.parentFile?.mkdirs()

        val audioSources = listOf(
            android.media.MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            android.media.MediaRecorder.AudioSource.MIC,
            android.media.MediaRecorder.AudioSource.DEFAULT
        )

        for (source in audioSources) {
            var mr: android.media.MediaRecorder? = null
            try {
                mr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    android.media.MediaRecorder(context)
                } else {
                    @Suppress("DEPRECATION")
                    android.media.MediaRecorder()
                }
                mr.setAudioSource(source)
                mr.setOutputFormat(android.media.MediaRecorder.OutputFormat.MPEG_4)
                mr.setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AAC)
                mr.setAudioEncodingBitRate(64000)
                mr.setAudioSamplingRate(44100)
                mr.setOutputFile(file.absolutePath)
                mr.prepare()
                mr.start()

                recorder = mr
                currentFilePath = file.absolutePath
                android.util.Log.i("CallAudioRecorder", "Successfully started audio recording using source $source")
                return true
            } catch (e: Exception) {
                android.util.Log.w("CallAudioRecorder", "Audio source $source failed: ${e.message}, trying next fallback...")
                try { mr?.release() } catch (_: Exception) {}
            }
        }
        android.util.Log.e("CallAudioRecorder", "All audio sources failed to start recording.")
        currentFilePath = null
        recorder = null
        return false
    }

    fun stop(): String? {
        val path = currentFilePath
        try {
            recorder?.stop()
        } catch (e: Exception) {
            android.util.Log.w("CallAudioRecorder", "Failed to stop recording cleanly: ${e.message}")
        }
        try {
            recorder?.release()
        } catch (_: Exception) {}
        recorder = null
        currentFilePath = null
        return path
    }
}

private class VoiceFxEngine(private val activity: Activity) : EventChannel.StreamHandler {
    private val sampleRate = 16000
    private val frameSamples = 640 // 40 ms
    @Volatile var filter: String = "NORMAL"
    @Volatile private var capturing = false
    @Volatile private var playing = false
    private var sink: EventChannel.EventSink? = null
    private var recorder: AudioRecord? = null
    private var player: AudioTrack? = null
    private val playbackQueue = ArrayBlockingQueue<ByteArray>(8)

    private var lowState = 0.0
    private var hpPrevIn = 0.0
    private var hpPrevOut = 0.0
    private var radioLow = 0.0
    private var radioHpPrevIn = 0.0
    private var radioHpPrevOut = 0.0
    private var phase = 0.0
    private val comb = DoubleArray(240)
    private var combIndex = 0

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    @Synchronized fun startCapture(newFilter: String) {
        filter = newFilter
        if (capturing) return
        val min = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val bufferSize = maxOf(min, frameSamples * 4)
        val r = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        recorder = r
        capturing = true
        r.startRecording()
        thread(name = "TalkStrangersVoiceFxCapture", isDaemon = true) {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val samples = ShortArray(frameSamples)
            while (capturing) {
                val read = try { r.read(samples, 0, samples.size) } catch (_: Exception) { -1 }
                if (read <= 0) continue
                val processed = process(samples, read)
                val bytes = ByteBuffer.allocate(read * 2).order(ByteOrder.LITTLE_ENDIAN)
                for (i in 0 until read) bytes.putShort(processed[i])
                val frame = bytes.array()
                activity.runOnUiThread { sink?.success(frame) }
            }
            try { r.stop() } catch (_: Exception) {}
            r.release()
            if (recorder === r) recorder = null
        }
    }

    @Synchronized fun stopCapture() {
        capturing = false
        try { recorder?.stop() } catch (_: Exception) {}
    }

    @Synchronized fun enqueuePlayback(data: ByteArray) {
        if (!playing) startPlayback()
        if (!playbackQueue.offer(data)) {
            playbackQueue.poll()
            playbackQueue.offer(data)
        }
    }

    @Synchronized private fun startPlayback() {
        if (playing) return
        val min = AudioTrack.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val p = AudioTrack(
            AudioManager.STREAM_VOICE_CALL,
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(min, frameSamples * 8),
            AudioTrack.MODE_STREAM
        )
        player = p
        playing = true
        p.play()
        thread(name = "TalkStrangersVoiceFxPlayback", isDaemon = true) {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            while (playing) {
                val frame = try { playbackQueue.take() } catch (_: InterruptedException) { continue }
                try { p.write(frame, 0, frame.size) } catch (_: Exception) {}
            }
            try { p.stop() } catch (_: Exception) {}
            p.release()
            if (player === p) player = null
        }
    }

    @Synchronized fun stopPlayback() {
        playing = false
        playbackQueue.clear()
        try { player?.pause() } catch (_: Exception) {}
        try { player?.flush() } catch (_: Exception) {}
    }

    fun shutdown() {
        stopCapture()
        stopPlayback()
        sink = null
    }

    private fun process(input: ShortArray, count: Int): ShortArray {
        val out = ShortArray(count)
        val mode = filter
        for (i in 0 until count) {
            val x = input[i] / 32768.0
            var y = x
            when (mode) {
                "DEEP_BARITONE" -> {
                    // Matches the web effect concept: bass emphasis + high-frequency roll-off.
                    lowState += 0.10 * (x - lowState)
                    y = lowState * 1.45 + x * 0.12
                }
                "HELIUM" -> {
                    // Bright anonymizer: strong high-pass / presence emphasis.
                    val hp = 0.86 * (hpPrevOut + x - hpPrevIn)
                    hpPrevIn = x
                    hpPrevOut = hp
                    y = hp * 1.25 + x * 0.22
                }
                "ROBOT" -> {
                    val delayed = comb[combIndex]
                    comb[combIndex] = x + delayed * 0.55
                    combIndex = (combIndex + 1) % comb.size
                    val carrier = sin(phase)
                    phase += 2.0 * PI * 50.0 / sampleRate
                    if (phase > 2.0 * PI) phase -= 2.0 * PI
                    y = (x * 0.62 + delayed * 0.38) * (0.58 + 0.42 * carrier)
                }
                "RADIO" -> {
                    val hp = 0.78 * (radioHpPrevOut + x - radioHpPrevIn)
                    radioHpPrevIn = x
                    radioHpPrevOut = hp
                    radioLow += 0.24 * (hp - radioLow)
                    val z = radioLow * 1.8
                    y = z / (1.0 + kotlin.math.abs(z))
                }
            }
            val clipped = y.coerceIn(-0.98, 0.98)
            out[i] = (clipped * 32767.0).toInt().toShort()
        }
        return out
    }
}
