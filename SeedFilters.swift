import Foundation

/// A small built-in list so blocking works on first launch, offline, before any list is downloaded.
/// Deliberately conservative: nothing here is needed for logins (no gstatic, accounts.google.com, etc.).
public enum SeedFilters {
    public static let text = """
    ! Veil essentials
    ||doubleclick.net^
    ||googlesyndication.com^
    ||googleadservices.com^
    ||adservice.google.com^
    ||google-analytics.com^
    ||analytics.google.com^
    ||amazon-adsystem.com^
    ||adnxs.com^
    ||criteo.com^
    ||criteo.net^
    ||taboola.com^
    ||outbrain.com^
    ||pubmatic.com^
    ||rubiconproject.com^
    ||openx.net^
    ||scorecardresearch.com^
    ||quantserve.com^
    ||hotjar.com^
    ||mixpanel.com^$third-party
    ||connect.facebook.net/*/fbevents.js
    ||facebook.com/tr^
    ||ads.twitter.com^
    ||analytics.twitter.com^
    ||ads.linkedin.com^
    ||analytics.tiktok.com^
    ||bat.bing.com^
    ||adsrvr.org^
    ||moatads.com^
    ||zedo.com^
    ||popads.net^
    ||popcash.net^
    ||propellerads.com^
    ||exoclick.com^
    ||trafficjunky.net^
    ##.adsbygoogle
    ##ins.adsbygoogle
    ##[id^="google_ads_iframe"]
    """
}
