package com.financetracker.finance_tracker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var expensePlayback: ExpensePlayback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        expensePlayback = ExpensePlayback(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onPause() {
        expensePlayback?.stopSpeaking()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        expensePlayback?.close()
        expensePlayback = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
