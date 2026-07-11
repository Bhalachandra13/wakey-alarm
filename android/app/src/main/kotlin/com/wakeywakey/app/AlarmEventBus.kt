package com.wakeywakey.app

import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicReference

/**
 * Process-wide bridge between native components and the Flutter
 * [EventChannel] for [com.wakeywakey.alarm_events].
 *
 * [MainActivity] owns the `EventChannel` (because the channel
 * lives on the Flutter engine's binary messenger), but other
 * native components — [RingingActivity] in particular — need to
 * emit events too. The bus is the rendezvous point:
 *
 *  - [MainActivity]'s `StreamHandler.onListen` calls
 *    [attach] with the channel's sink.
 *  - [MainActivity]'s `StreamHandler.onCancel` calls [detach].
 *  - [RingingActivity] (or any other native component) calls
 *    [emit] to push an event to the Dart side.
 *
 * If no Dart listener is attached (e.g. the process was cold-
 * started by an alarm fire and the user never opened the app),
 * [emit] is a no-op — the event is silently dropped, which is
 * the right behaviour because the Dart side has no way to
 * observe it anyway.
 */
object AlarmEventBus {

    private val sinkRef = AtomicReference<EventChannel.EventSink?>(null)

    fun attach(sink: EventChannel.EventSink) {
        sinkRef.set(sink)
    }

    fun detach() {
        sinkRef.set(null)
    }

    /**
     * Push an event to the Dart side. No-op if no listener is
     * currently attached. The payload is a [Map] of primitive
     * types; complex objects should be flattened by the caller
     * (Dart's [StandardMethodCodec] does not encode arbitrary
     * Kotlin types).
     */
    fun emit(event: Map<String, Any?>) {
        sinkRef.get()?.success(event)
    }
}
