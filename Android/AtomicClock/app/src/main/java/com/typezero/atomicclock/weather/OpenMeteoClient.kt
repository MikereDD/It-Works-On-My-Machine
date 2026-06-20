package com.typezero.atomicclock.weather

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Fetches current conditions from Open-Meteo (https://open-meteo.com).
 * Free, keyless, and HTTPS — no account or token required.
 */
class OpenMeteoClient(
    private val timeoutMs: Int = 6_000,
) {
    fun current(latitude: Double, longitude: Double): RawWeather? {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(
                "https://api.open-meteo.com/v1/forecast" +
                    "?latitude=$latitude&longitude=$longitude" +
                    "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,wind_direction_10m" +
                    "&timezone=auto",
            )
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = timeoutMs
                readTimeout = timeoutMs
            }
            if (conn.responseCode != HttpURLConnection.HTTP_OK) return null

            val body = conn.inputStream.bufferedReader().use { it.readText() }
            val current = JSONObject(body).getJSONObject("current")
            RawWeather(
                tempC = current.getDouble("temperature_2m"),
                apparentC = current.optDouble("apparent_temperature", current.getDouble("temperature_2m")),
                humidity = current.optInt("relative_humidity_2m", -1),
                windKmh = current.optDouble("wind_speed_10m", -1.0),
                windDir = current.optInt("wind_direction_10m", -1),
                code = current.getInt("weather_code"),
                isDay = current.optInt("is_day", 1) == 1,
            )
        } catch (_: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }
}
