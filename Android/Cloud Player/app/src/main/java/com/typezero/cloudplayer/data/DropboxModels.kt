package com.typezero.cloudplayer.data

/** Saved Dropbox account metadata. Passwords are never stored. */
data class DropboxAccount(
    val id: String,
    val email: String,
    val label: String = email
)
