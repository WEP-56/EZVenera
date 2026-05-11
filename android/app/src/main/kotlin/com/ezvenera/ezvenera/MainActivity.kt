package com.ezvenera.ezvenera

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Flutter host activity for EZVenera.
 *
 * Besides the standard Flutter wiring, this activity owns the native side of
 * the volume-key page turning feature exposed at the `ezvenera/volume`
 * event channel. The handshake mirrors venera's original implementation:
 *
 *   - Dart subscribes -> we flip `listening = true`.
 *   - onKeyDown(VOLUME_UP) sends `1`, onKeyDown(VOLUME_DOWN) sends `2`.
 *   - Dart cancels -> `listening = false` and the keys fall through to
 *     the system so the media volume still works outside the reader.
 */
class MainActivity : FlutterFragmentActivity() {

    private var volumeEventSink: EventChannel.EventSink? = null
    private var listening = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    volumeEventSink = events
                    listening = true
                }

                override fun onCancel(arguments: Any?) {
                    volumeEventSink = null
                    listening = false
                }
            })
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (listening) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    volumeEventSink?.success(1)
                    return true
                }

                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    volumeEventSink?.success(2)
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    companion object {
        private const val VOLUME_CHANNEL = "ezvenera/volume"
    }
}
