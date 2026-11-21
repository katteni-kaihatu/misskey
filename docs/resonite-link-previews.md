# Resonite link previews in GridSpace

Implemented from GridSpace `31.72` (`003b639fd4`). This integration belongs to the
GridSpace fork; it does not change the paired Resonite.love repository.

Supported HTTPS links:

- `https://go.resonite.com/world/<ownerId>/<recordId>`
- `https://go.resonite.com/record/<ownerId>/<recordId>` (world records only)
- `https://go.resonite.com/session/<sessionId>`
- The corresponding `https://api.resonite.com/open/world/...` and
  `https://api.resonite.com/open/session/...` links.

The primary action launches the installed Resonite client using `resrec:///` or
`ressession:///`. A separate Web link remains available at every card size.
Raw native-protocol URLs in note text are not automatically expanded by this change.

## Public metadata

The backend uses anonymous GET requests to the same API endpoints as the
[official link site](https://github.com/Yellow-Dog-Man/go.resonite.com/blob/main/routes/index.js):

- `/users/<ownerId>/records/<recordId>` for public world records.
- `/sessions/<sessionId>` for sessions with public access and `hideFromListing: false`.

World cards show the title, description, creator, visits, update date and featured
status when supplied. Session cards show the session description (or the saved
world description), host, start time and `joinedUsers / maxUsers`. `totalJoinedUsers`
includes nested sessions and is deliberately not compared against one session's
capacity. Participant avatars are omitted because they are not supplied in session metadata.

Full or explicitly ended sessions can open their saved world only after that
record has independently passed the public-world checks. A missing record/session
shows an unavailable state; transient API failures retain a Web action.

Provider data is cached for 60 seconds with concurrent requests coalesced. Upstream
requests are limited to five seconds and 4 MiB (records can contain large asset
manifests), and redirects are rejected. Only `assets.resonite.com` and
`thumbnails.resonite.com` images are accepted, then served through Misskey's image proxy.
Executable assets, session connection URLs and private records are never embedded.

Names are rendered as escaped text spans with allowlisted colors, not provider
HTML. Dark or transparent colors are brightened for readability on the card.
The supplied logo assets retain their original colors and proportions.

Resonite thumbnails use the full image-proxy URL without `preview=1`. Images
at least 512 pixels wide with a 2:1 aspect ratio are displayed as 360° panoramas,
rotating once every three minutes. The corner control pauses or resumes rotation;
dragging or the left/right arrow keys adjusts the view manually. Reduced-motion
and Misskey animation preferences start the view paused. Rendering stops and GPU
resources are released outside the viewport or while the page is hidden.
Other images and browsers without WebGL retain a static thumbnail. Panorama
textures are capped at 2048 pixels wide and rendering at 15 frames per second.

References checked on 2026-11-22:

- [Resonite API](https://wiki.resonite.com/API)
- [Official link-site preprocessing](https://github.com/Yellow-Dog-Man/go.resonite.com/blob/main/helpers/preprocessing.js)
- [Resonite branding](https://wiki.resonite.com/Branding)

API discovery was confirmed against these primary sources and live public
responses; the API catalog search did not return a relevant Resonite entry.

The API is documented as experimental, so unavailable fields are omitted and
errors never fall back to rendering arbitrary upstream HTML.

## Validation

Backend adapter and URL service tests cover public filtering, malformed links,
unsafe images, rich names, nested-session counts, failures, cache coalescing and
anonymous requests. Frontend tests cover native/Web actions, full/ended states,
privacy settings and integration through `MkUrlPreview`.
Panorama tests cover visibility, cleanup, motion preferences, controls and static
fallback. Browser checks also verify rotation, pause, offscreen recovery and
small-screen controls with a real equirectangular thumbnail.

`docs/screenshots/resonite-link-previews.png` uses explicit fixture data. Live
verification was performed against public worlds and sessions without credentials.
