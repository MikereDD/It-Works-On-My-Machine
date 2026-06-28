package com.typezero.cloudplayer.mega

import com.typezero.cloudplayer.data.ApiResult
import com.typezero.cloudplayer.data.MegaAuthSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Boundary for MEGA account login.
 *
 * MEGA uses client-side encrypted storage, so Cloud Player must authenticate
 * through a MEGA SDK-backed implementation here before it can browse or stream
 * account files. The app UI talks to this interface rather than directly to
 * SDK/native code.
 */
interface MegaAuthRepository {
    suspend fun signIn(email: String, password: String): ApiResult<MegaAuthSession>
}

/**
 * Safe default used until the official MEGA SDK/JNI layer is bundled.
 * It validates the form path without pretending account login is working.
 */
class MissingMegaSdkAuthRepository : MegaAuthRepository {
    override suspend fun signIn(email: String, password: String): ApiResult<MegaAuthSession> =
        withContext(Dispatchers.IO) {
            if (email.isBlank()) return@withContext ApiResult.Error("Enter your MEGA email.")
            if (!email.contains("@")) return@withContext ApiResult.Error("That does not look like a valid email address.")
            if (password.isBlank()) return@withContext ApiResult.Error("Enter your MEGA password.")
            ApiResult.Error(
                "MEGA sign-in screen is ready, but the MEGA SDK is not bundled in this build yet. " +
                    "Add the official MEGA SDK/JNI provider before enabling account browsing."
            )
        }
}
