package com.cnting.audio_player;


import android.os.Handler;
import android.os.Looper;

import java.util.concurrent.CopyOnWriteArrayList;

import io.flutter.plugin.common.EventChannel;

/**
 * And implementation of {@link EventChannel.EventSink} which can wrap an underlying sink.
 *
 * <p>It delivers messages immediately when downstream is available, but it queues messages before
 * the delegate event sink is set with setDelegate.
 *
 * <p>This class is not thread-safe. All calls must be done on the same thread or synchronized
 * externally.
 */
public final class QueuingEventSink implements EventChannel.EventSink {
    private EventChannel.EventSink delegate;
    private CopyOnWriteArrayList<Object> eventQueue = new CopyOnWriteArrayList<>();
    private boolean done = false;
    private Handler handler;

    QueuingEventSink() {
        handler = new Handler(Looper.getMainLooper());
    }

    void setDelegate(EventChannel.EventSink delegate) {
        this.delegate = delegate;
        maybeFlush();
    }

    @Override
    public void endOfStream() {
        enqueue(new EndOfStreamEvent());
        maybeFlush();
        done = true;
    }

    @Override
    public void error(String code, String message, Object details) {
        enqueue(new ErrorEvent(code, message, details));
        maybeFlush();
    }

    @Override
    public void success(Object event) {
        enqueue(event);
        maybeFlush();
    }

    private void enqueue(Object event) {
        if (done) {
            return;
        }
        eventQueue.add(event);
    }

    private void maybeFlush() {
        if (delegate == null) {
            return;
        }
        for (Object event : eventQueue) {
            if (event instanceof EndOfStreamEvent) {
                delegate.endOfStream();
            } else if (event instanceof ErrorEvent) {
                ErrorEvent errorEvent = (ErrorEvent) event;
                handler.post(() -> {
                    if (delegate != null)
                        delegate.error(errorEvent.code, errorEvent.message, errorEvent.details);
                });
            } else {
                handler.post(() -> {
                    if (delegate != null)
                        delegate.success(event);
                });
            }
        }
        eventQueue.clear();
    }

    private static class EndOfStreamEvent {
    }

    private static class ErrorEvent {
        String code;
        String message;
        Object details;

        ErrorEvent(String code, String message, Object details) {
            this.code = code;
            this.message = message;
            this.details = details;
        }
    }
}
