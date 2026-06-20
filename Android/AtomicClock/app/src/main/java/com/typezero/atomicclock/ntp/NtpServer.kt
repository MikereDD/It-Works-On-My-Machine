package com.typezero.atomicclock.ntp

/** User-selectable NTP time sources. */
enum class NtpServer(val displayName: String, val host: String) {
    GOOGLE("Google", "time.google.com"),
    CLOUDFLARE("Cloudflare", "time.cloudflare.com"),
    POOL("NTP Pool", "pool.ntp.org"),
    APPLE("Apple", "time.apple.com"),
    NIST("NIST (US)", "time.nist.gov");

    companion object {
        val DEFAULT = GOOGLE
        fun fromNameOrDefault(name: String?): NtpServer =
            entries.firstOrNull { it.name == name } ?: DEFAULT
    }
}
