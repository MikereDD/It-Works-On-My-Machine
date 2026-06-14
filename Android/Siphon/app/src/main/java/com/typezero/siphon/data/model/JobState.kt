package com.typezero.siphon.data.model

/** Live state of an extraction job for the UI. */
data class JobState(
    val id: String,
    val title: String,
    val status: Status,
    val progress: Float = -1f,         // 0..1, -1 = indeterminate
    val line: String = "",
    val outputPath: String? = null,
    val error: String? = null
) {
    enum class Status { QUEUED, RUNNING, DONE, FAILED, CANCELLED }
}
