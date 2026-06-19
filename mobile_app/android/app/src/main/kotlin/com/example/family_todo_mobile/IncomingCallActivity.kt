package com.example.family_todo_mobile

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView

class IncomingCallActivity : Activity() {
    private var data: Map<String, String> = emptyMap()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        data = intent.pushData()
        if (!isIncomingCallPush(data)) {
            finish()
            return
        }

        applyLockscreenFlags()
        TelecomCallManager.registerPhoneAccounts(this)
        IncomingCallAlertManager.start(this)
        setContentView(buildIncomingCallView(data))
    }

    private fun applyLockscreenFlags() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguard.requestDismissKeyguard(this, null)
            return
        }

        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
    }

    private fun buildIncomingCallView(data: Map<String, String>): LinearLayout {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(32), dp(28), dp(42))
            setBackgroundColor(Color.rgb(12, 16, 22))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        root.addView(callTypeLabel(data))
        root.addView(callerLabel(data))
        root.addView(statusLabel())
        root.addView(Space(this).apply {
            layoutParams = LinearLayout.LayoutParams(1, 0, 1f)
        })
        root.addView(actionRow())
        return root
    }

    private fun callTypeLabel(data: Map<String, String>): TextView {
        return TextView(this).apply {
            text = if (TelecomCallManager.isVideoCall(data)) "Видеозвонок" else "Звонок"
            setTextColor(Color.rgb(190, 202, 216))
            textSize = 22f
            gravity = Gravity.CENTER
        }
    }

    private fun callerLabel(data: Map<String, String>): TextView {
        return TextView(this).apply {
            text = TelecomCallManager.callerDisplayName(data)
            setTextColor(Color.WHITE)
            textSize = 34f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(18), 0, 0)
        }
    }

    private fun statusLabel(): TextView {
        return TextView(this).apply {
            text = "Входящий звонок"
            setTextColor(Color.rgb(150, 164, 180))
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, 0)
        }
    }

    private fun actionRow(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            addView(actionButtonColumn("Отклонить", "×", Color.rgb(220, 55, 55)) { declineCall() })
            addView(Space(this@IncomingCallActivity).apply {
                layoutParams = LinearLayout.LayoutParams(dp(72), 1)
            })
            addView(actionButtonColumn("Принять", "✓", Color.rgb(38, 170, 90)) { acceptCall() })
        }
    }

    private fun actionButtonColumn(
        label: String,
        glyph: String,
        color: Int,
        onClick: () -> Unit,
    ): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            addView(callActionCircle(label, glyph, color, onClick))
            addView(TextView(this@IncomingCallActivity).apply {
                text = label
                setTextColor(Color.rgb(225, 231, 238))
                textSize = 15f
                gravity = Gravity.CENTER
                setPadding(0, dp(10), 0, 0)
            })
            layoutParams = LinearLayout.LayoutParams(dp(92), ViewGroup.LayoutParams.WRAP_CONTENT)
        }
    }

    private fun callActionCircle(
        label: String,
        glyph: String,
        color: Int,
        onClick: () -> Unit,
    ): TextView {
        return TextView(this).apply {
            text = glyph
            contentDescription = label
            includeFontPadding = false
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 34f
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
            }
            minHeight = 0
            minWidth = 0
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(dp(76), dp(76))
            setOnClickListener { onClick() }
        }
    }

    private fun acceptCall() {
        IncomingCallAlertManager.stop()
        TelecomCallManager.answerIncomingConnection(data)
        TelecomCallManager.cancelIncomingCallNotification(this, data)
        TelecomCallManager.openCallActivity(this, data, "accept")
        finish()
    }

    private fun declineCall() {
        IncomingCallAlertManager.stop()
        TelecomCallManager.rejectIncomingConnection(this, data)
        finish()
    }

    @Deprecated("Use OnBackInvokedCallback on newer APIs")
    override fun onBackPressed() {
        declineCall()
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
