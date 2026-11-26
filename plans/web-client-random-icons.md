# Random artwork for the Gridspace web client

2026-11-26, Asia/Tokyo. The owner selected the five submissions listed in [artwork credits](../assets/gridspace/web-client-icons/README.md) and requested random icons in both the main web navigation and browser tab.

The frontend chooses one of the five artists' icons once per document load. Vertical/horizontal navigation, the title bar and visitor header/dashboard share that module choice. SPA navigation and layout changes keep the same choice; reloading or opening another document makes a new independent choice, which may repeat the previous icon. No preference or account data stores the selection.

The tab uses the matching 64px PNG through `link rel="icon"`. The navigation uses a 128px PNG of the same complete artwork. These derivatives preserve transparency and aspect ratio, and the downloaded originals remain unchanged with source attribution. The PNG sizes follow the browser icon declaration mechanism described in [MDN's link reference](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/link).

Only the G frontend changes. Instance metadata, ActivityPub, the canonical `/favicon.ico`, Apple touch icons, the web app manifest, the R deployment and third-party clients keep their existing sources. The HTML server response retains its configured icon; the main web client changes the current document's icon after boot. Embed entry points do not call this main boot routine.

Validation includes a DOM regression suite for a shared document choice, a new choice after reload, missing/multiple favicon declarations, and preservation of server metadata, touch icons, manifests and pinned-tab declarations. Generated PNG dimensions/signatures and original byte checksums are checked separately. The two icon-only navigation buttons have existing localized accessible names.

Changelog candidate: Randomize the Gridspace web navigation and tab icon among five selected community artworks on each page load.
