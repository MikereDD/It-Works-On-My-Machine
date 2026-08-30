package com.example.tetblockris

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

class MainActivity : AppCompatActivity() {

    private lateinit var gameView: TetBlockRisView
    private lateinit var scoreText: TextView
    private lateinit var highScoreText: TextView
    private lateinit var levelText: TextView
    private lateinit var linesText: TextView
    private lateinit var gameOverText: TextView
    private lateinit var victoryText: TextView
    private lateinit var startButton: Button
    private lateinit var pauseButton: Button
    private lateinit var btnLeft: Button
    private lateinit var btnRight: Button
    private lateinit var btnDown: Button
    private lateinit var btnRotate: Button
    private lateinit var btnDrop: Button
    private lateinit var btnHold: Button

    // Auto-repeat handler for held directional buttons
    private val repeatHandler = Handler(Looper.getMainLooper())
    private var repeatAction: Runnable? = null
    private val initialDelay = 180L
    private val repeatDelay = 75L

    private var isPaused = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen on while playing
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Full-screen immersive
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val insetsController = WindowInsetsControllerCompat(window, window.decorView)
        insetsController.hide(WindowInsetsCompat.Type.systemBars())
        insetsController.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

        setContentView(R.layout.activity_main)

        gameView       = findViewById(R.id.gameView)
        scoreText      = findViewById(R.id.scoreText)
        highScoreText  = findViewById(R.id.highScoreText)
        levelText      = findViewById(R.id.levelText)
        linesText      = findViewById(R.id.linesText)
        gameOverText   = findViewById(R.id.gameOverText)
        victoryText    = findViewById(R.id.victoryText)
        startButton    = findViewById(R.id.startButton)
        pauseButton    = findViewById(R.id.pauseButton)
        btnLeft        = findViewById(R.id.btnLeft)
        btnRight       = findViewById(R.id.btnRight)
        btnDown        = findViewById(R.id.btnDown)
        btnRotate      = findViewById(R.id.btnRotate)
        btnDrop        = findViewById(R.id.btnDrop)
        btnHold        = findViewById(R.id.btnHold)

        updateHighScoreDisplay()
        wireGameCallbacks()
        wireButtons()
    }

    private fun wireGameCallbacks() {
        gameView.onScoreUpdate = { score, level, lines ->
            runOnUiThread {
                scoreText.text  = score.toString()
                levelText.text  = level.toString()
                linesText.text  = lines.toString()
            }
        }

        gameView.onGameOver = { finalScore ->
            runOnUiThread {
                gameOverText.visibility = View.VISIBLE
                startButton.text = "TRY AGAIN"
                pauseButton.isEnabled = false
                saveHighScore(finalScore)
                updateHighScoreDisplay()
            }
        }

        gameView.onVictory = { finalScore ->
            runOnUiThread {
                victoryText.visibility = View.VISIBLE
                startButton.text = "PLAY AGAIN"
                pauseButton.isEnabled = false
                saveHighScore(finalScore)
                updateHighScoreDisplay()
            }
        }
    }

    private fun wireButtons() {
        startButton.setOnClickListener {
            gameOverText.visibility = View.GONE
            victoryText.visibility  = View.GONE
            isPaused = false
            pauseButton.text = "⏸"
            pauseButton.isEnabled = true
            gameView.startGame()
            startButton.text = "RESTART"
        }

        pauseButton.setOnClickListener {
            if (!gameView.isRunning) return@setOnClickListener
            isPaused = !isPaused
            if (isPaused) {
                gameView.pauseGame()
                pauseButton.text = "▶"
            } else {
                gameView.resumeGame()
                pauseButton.text = "⏸"
            }
        }

        // ── Directional buttons with auto-repeat ──────────────────────────
        setupRepeatButton(btnLeft)  { gameView.moveLeft() }
        setupRepeatButton(btnRight) { gameView.moveRight() }
        setupRepeatButton(btnDown)  { gameView.softDrop() }

        btnRotate.setOnClickListener { gameView.doRotate() }
        btnDrop.setOnClickListener   { gameView.doHardDrop() }
        btnHold.setOnClickListener   { gameView.doHold() }
    }

    /** Fires action immediately on press, then repeats after a short delay while held. */
    private fun setupRepeatButton(btn: Button, action: () -> Unit) {
        btn.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    btn.isPressed = true
                    action()
                    repeatAction = object : Runnable {
                        override fun run() {
                            action()
                            repeatHandler.postDelayed(this, repeatDelay)
                        }
                    }
                    repeatHandler.postDelayed(repeatAction!!, initialDelay)
                    true
                }
                android.view.MotionEvent.ACTION_UP,
                android.view.MotionEvent.ACTION_CANCEL -> {
                    btn.isPressed = false
                    repeatHandler.removeCallbacks(repeatAction ?: return@setOnTouchListener false)
                    repeatAction = null
                    true
                }
                else -> false
            }
        }
    }

    private fun saveHighScore(score: Int) {
        val prefs = getSharedPreferences("TetBlockRisPrefs", Context.MODE_PRIVATE)
        val current = prefs.getInt("high_score", 0)
        if (score > current) prefs.edit().putInt("high_score", score).apply()
    }

    private fun updateHighScoreDisplay() {
        val prefs = getSharedPreferences("TetBlockRisPrefs", Context.MODE_PRIVATE)
        highScoreText.text = prefs.getInt("high_score", 0).toString()
    }

    override fun onPause() {
        super.onPause()
        if (gameView.isRunning && !isPaused) {
            gameView.pauseGame()
            isPaused = true
            pauseButton.text = "▶"
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        repeatHandler.removeCallbacksAndMessages(null)
    }
}
