package com.typezero.siphon.data.model

/**
 * Which client yt-dlp pretends to be when talking to YouTube. Switching this is
 * the common workaround for "HTTP Error 403" — YouTube blocks some clients but
 * not others, and which ones work shifts over time, so we expose a few.
 * DEFAULT = let yt-dlp choose (value null = no override).
 */
enum class YouTubeClient(val label: String, val value: String?) {
    DEFAULT("Default", null),
    TV("TV", "tv"),
    WEB("Web", "web_safari"),
    IOS("iOS", "ios"),
    MWEB("Mobile", "mweb")
}
