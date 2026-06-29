package com.typezero.cloudplayer.data

/** Saved Box account metadata. Passwords are never stored. */
data class BoxAccount(
    val id: String,
    val email: String,
    val label: String = email
)
