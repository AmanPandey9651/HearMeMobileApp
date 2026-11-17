package com.harto.feelback.ringtone

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FeelBackRingtonePlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "feelback_ringtone")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val ctx = context
        val callId = call.argument<String>("callId")
        val source = call.argument<String>("source") ?: "MethodChannel"

        when (call.method) {
            "start" -> {
                if (ctx != null) {
                    NativeRingtoneManager.start(ctx, callId = callId, source = source)
                }
                result.success(true)
            }
            "stop" -> {
                NativeRingtoneManager.stop(ctx, callId = callId, source = source)
                result.success(true)
            }
            "markAccepted" -> {
                if (callId != null) {
                    NativeRingtoneManager.markAccepted(callId, source = source, context = ctx)
                } else {
                    NativeRingtoneManager.stop(ctx, source = source)
                }
                result.success(true)
            }
            "markTerminal" -> {
                val status = call.argument<String>("status") ?: "TERMINAL"
                if (callId != null) {
                    NativeRingtoneManager.markTerminal(callId, status = status, source = source, context = ctx)
                } else {
                    NativeRingtoneManager.stop(ctx, source = source)
                }
                result.success(true)
            }
            "isGuarded" -> {
                val guarded = if (callId != null) NativeRingtoneManager.isCallAcceptedOrTerminal(callId) else false
                result.success(guarded)
            }
            else -> result.notImplemented()
        }
    }
}
