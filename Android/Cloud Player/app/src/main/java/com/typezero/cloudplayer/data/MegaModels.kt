package com.typezero.cloudplayer.data

/** Saved MEGA account metadata. Passwords are never stored. */
data class MegaAccount(
    val id: String,
    val email: String,
    val label: String = email
)

/** Result placeholder for MEGA authentication wiring. */
data class MegaAuthSession(
    val email: String,
    val sessionId: String
)
