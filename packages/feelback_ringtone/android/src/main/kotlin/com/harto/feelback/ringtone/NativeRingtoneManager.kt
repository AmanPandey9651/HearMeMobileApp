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

object NativeRingtoneManager {
    private const val TAG = "NativeRingtoneMgr"
    @Volatile private var ringtone: Ringtone? = null
    @Volatile private var vibrator: Vibrator? = null
    @Volatile private var isPlaying = false

    @Synchronized
    fun start(context: Context) {
        if (isPlaying && ringtone?.isPlaying == true) {
            Log.d(TAG, "Already ringing, skipping start")
            return
        }
        stop(context)

        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            val ringerMode = audioManager?.ringerMode ?: AudioManager.RINGER_MODE_NORMAL

            if (ringerMode != AudioManager.RINGER_MODE_SILENT) {
                startVibrator(context)
            }

            if (ringerMode == AudioManager.RINGER_MODE_SILENT) {
                isPlaying = true
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
                Log.d(TAG, "Ringtone started with USAGE_ALARM successfully")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start ringtone: ${e.message}", e)
        }
    }

    @Synchronized
    fun stop(context: Context? = null) {
        isPlaying = false
        try {
            ringtone?.let {
                if (it.isPlaying) {
                    it.stop()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping ringtone: ${e.message}")
        } finally {
            ringtone = null
        }

        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping vibrator: ${e.message}")
        } finally {
            vibrator = null
        }
        Log.d(TAG, "Native ringtone stopped cleanly")
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
