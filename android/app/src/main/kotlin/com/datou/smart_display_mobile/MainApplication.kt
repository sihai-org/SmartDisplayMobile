package com.datou.smart_display_mobile

import android.app.Application
import android.util.Log
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins
import java.io.IOException
import java.net.SocketException

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // Prevent RxJava from crashing the app with UndeliverableException
        RxJavaPlugins.setErrorHandler { e: Throwable ->
            var error = e
            if (error is UndeliverableException && error.cause != null) {
                error = error.cause!!
            }
            when (error) {
                is IOException, is SocketException -> {
                    // Irrelevant network problem or API that throws on cancellation.
                    return@setErrorHandler
                }
                is InterruptedException -> {
                    // Fine, some blocking code was interrupted by a dispose call.
                    return@setErrorHandler
                }
                else -> {
                    // Common with BLE libs: disconnect during dispose. Don't crash app.
                    val msg = error.message ?: error.javaClass.simpleName
                    Log.w("RxJava", "Undeliverable error: $msg", error)
                    return@setErrorHandler
                }
            }
        }
    }
}
