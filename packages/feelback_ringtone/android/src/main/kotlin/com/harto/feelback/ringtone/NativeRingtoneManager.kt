package com.harto.feelback.ringtone

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import java.util.Collections
import java.util.HashSet

object NativeRingtoneManager {
    private const val TAG = "NativeRingtoneMgr"
    @Volatile private var ringtone: Ringtone? = null
    @Volatile private var vibrator: Vibrator? = null
    @Volatile private var isPlaying = false
    @Volatile private var activeCallId: String? = null

    // Terminal & Accepted state guards to prevent stale FCM/snapshots from restarting audio
    private val acceptedCallIds = Collections.synchronizedSet(HashSet<String>())
    private val terminalCallIds = Collections.synchronizedSet(HashSet<String>())

    @Synchronized
    fun start(context: Context, callId: String? = null, source: String = "unknown") {
        val now = System.currentTimeMillis()
        val cId = callId?.trim() ?: "unknown"

        if (cId != "unknown") {
            if (acceptedCallIds.contains(cId)) {
                Log.w(TAG, "[BLOCKED_START] timestamp=$now callId=$cId source=$source reason=CALL_ALREADY_ACCEPTED")
                return
            }
            if (terminalCallIds.contains(cId)) {
                Log.w(TAG, "[BLOCKED_START] timestamp=$now callId=$cId source=$source reason=CALL_ALREADY_TERMINAL")
                return
            }
        }

        if (isPlaying && ringtone?.isPlaying == true && (activeCallId == cId || cId == "unknown")) {
            Log.d(TAG, "[IDEMPOTENT_START] timestamp=$now callId=$cId source=$source already ringing")
            return
        }

        stop(context, callId = cId, source = "pre_start_cleanup")

        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            val ringerMode = audioManager?.ringerMode ?: AudioManager.RINGER_MODE_NORMAL

            if (ringerMode != AudioManager.RINGER_MODE_SILENT) {
                startVibrator(context)
            }

            if (ringerMode == AudioManager.RINGER_MODE_SILENT) {
                isPlaying = true
                activeCallId = cId
                Log.d(TAG, "[START_SILENT] timestamp=$now callId=$cId source=$source ringerMode=SILENT")
                return
            }

            var uri: Uri? = null
            val resId = context.resources.getIdentifier("ringtone_default", "raw", context.packageName)
            if (resId != 0) {
                uri = Uri.parse("android.resource://${context.packageName}/$resId")
            } else {
                uri = RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_RINGTONE)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            }

            val r = RingtoneManager.getRingtone(context, uri)
            if (r != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    r.isLooping = true
                    r.volume = 1.0f
                }
                r.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                r.play()
                ringtone = r
                isPlaying = true
                activeCallId = cId
                Log.i(TAG, "[START_SUCCESS] timestamp=$now callId=$cId source=$source audioStream=USAGE_ALARM")
            } else {
                Log.e(TAG, "[START_FAILED] timestamp=$now callId=$cId source=$source Ringtone instance was null")
            }
        } catch (e: Exception) {
            Log.e(TAG, "[START_ERROR] timestamp=$now callId=$cId source=$source error=${e.message}", e)
        }
    }

    @Synchronized
    fun stop(context: Context? = null, callId: String? = null, source: String = "unknown") {
        val now = System.currentTimeMillis()
        val cId = callId ?: activeCallId ?: "ALL"
        isPlaying = false
        activeCallId = null

        try {
            ringtone?.let {
                if (it.isPlaying) {
                    it.stop()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "[STOP_WARN] timestamp=$now callId=$cId source=$source error=${e.message}")
        } finally {
            ringtone = null
        }

        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "[VIBRATOR_STOP_WARN] timestamp=$now callId=$cId source=$source error=${e.message}")
        } finally {
            vibrator = null
        }
        Log.i(TAG, "[STOP_SUCCESS] timestamp=$now callId=$cId source=$source")
    }

    @Synchronized
    fun markAccepted(callId: String, source: String = "unknown", context: Context? = null) {
        val now = System.currentTimeMillis()
        val cId = callId.trim()
        if (cId.isNotEmpty()) {
            acceptedCallIds.add(cId)
            Log.i(TAG, "[MARK_ACCEPTED_PERMANENT] timestamp=$now callId=$cId source=$source ringtone permanently guarded against restart")
        }
        stop(context, callId = cId, source = "markAccepted:$source")
    }

    @Synchronized
    fun markTerminal(callId: String, status: String, source: String = "unknown", context: Context? = null) {
        val now = System.currentTimeMillis()
        val cId = callId.trim()
        if (cId.isNotEmpty()) {
            terminalCallIds.add(cId)
            Log.i(TAG, "[MARK_TERMINAL_PERMANENT] timestamp=$now callId=$cId status=$status source=$source")
        }
        stop(context, callId = cId, source = "markTerminal:$source")
    }

    fun isCallAcceptedOrTerminal(callId: String): Boolean {
        val cId = callId.trim()
        return acceptedCallIds.contains(cId) || terminalCallIds.contains(cId)
    }

    private fun startVibrator(context: Context) {
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            val pattern = longArrayOf(0, 1000, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed starting vibration: ${e.message}")
        }
    }
}
