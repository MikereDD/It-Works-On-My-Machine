package com.example.tetblockris

import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var gameView: TetBlockRisView
    private lateinit var scoreText: TextView
    private lateinit var highScoreText: TextView
    private lateinit var levelText: TextView
    private lateinit var linesText: TextView
    private lateinit var gameOverText: TextView
    private lateinit var victoryText: TextView
    private lateinit var startButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        gameView = findViewById(R.id.gameView)
        scoreText = findViewById(R.id.scoreText)
        highScoreText = findViewById(R.id.highScoreText)
        levelText = findViewById(R.id.levelText)
        linesText = findViewById(R.id.linesText)
        gameOverText = findViewById(R.id.gameOverText)
        victoryText = findViewById(R.id.victoryText)
        startButton = findViewById(R.id.startButton)

        updateHighScoreDisplay()

        gameView.onScoreUpdate = { score, level, lines ->
            runOnUiThread {
                scoreText.text = score.toString()
                levelText.text = level.toString()
                linesText.text = lines.toString()
            }
        }

        gameView.onHoldUpdate = { hasHold ->
            runOnUiThread {
                // Visual feedback handled in game view
            }
        }

        gameView.onGameOver = { finalScore ->
            runOnUiThread {
                gameOverText.visibility = View.VISIBLE
                startButton.text = "Try Again"
                saveHighScore(finalScore)
                updateHighScoreDisplay()
            }
        }

        gameView.onVictory = { finalScore ->
            runOnUiThread {
                victoryText.visibility = View.VISIBLE
                startButton.text = "Play Again"
                saveHighScore(finalScore)
                updateHighScoreDisplay()
            }
        }

        startButton.setOnClickListener {
            gameOverText.visibility = View.GONE
            victoryText.visibility = View.GONE
            gameView.startGame()
            startButton.text = "Restart"
        }
    }

    private fun saveHighScore(score: Int) {
        val prefs = getSharedPreferences("TetBlockRisPrefs", Context.MODE_PRIVATE)
        val currentHigh = prefs.getInt("high_score", 0)
        if (score > currentHigh) {
            prefs.edit().putInt("high_score", score).apply()
        }
    }

    private fun updateHighScoreDisplay() {
        val prefs = getSharedPreferences("TetBlockRisPrefs", Context.MODE_PRIVATE)
        val highScore = prefs.getInt("high_score", 0)
        highScoreText.text = highScore.toString()
    }

    override fun onPause() {
        super.onPause()
        gameView.pauseGame()
    }
}