# Gridspace web client artwork

Five submissions selected by the server owner on 2026-11-26 for randomized web client branding. Original downloaded attachments are retained without modification; this attribution record does not assign a new license to the artwork.

| File | Author | Original post | Attachment ID |
| --- | --- | --- | --- |
| sakami.webp | @sakami | https://misskey.grid-space.io/notes/atvijvp1ib528b9d | atvijv49ib528b95 |
| tekerets.png | @tekerets | https://misskey.grid-space.io/notes/attffkta1pfl157c | attes3qp1pfl14fb |
| sharuya.webp | @SHaruya | https://misskey.grid-space.io/notes/atocfvum8iek132s | atocftw98iek132m |
| machiyoh.webp | @machiyoh | https://misskey.grid-space.io/notes/atlfsu8clg29065a | atlfsthslg290658 |
| ningen.webp | @ningen | https://misskey.grid-space.io/notes/atkv1uqkox3n0flx | atkv1tz9ox3n0flw |

The tekerets submission uses its square icon attachment rather than the separate landscape wordmark. Its source post credits the Anton font under the SIL Open Font License.

`node scripts/build-gridspace-client-icons.mjs` generates transparent-preserving PNG derivatives at 128px for the navigation and 64px for the tab icon in `packages/frontend/assets/gridspace/client-icons/`. It only scales the complete square images; it does not crop or redraw the artwork. Generated files are committed so normal application builds do not need this additional step.

The choices apply inside the main web client only. Server metadata, ActivityPub, the canonical `/favicon.ico`, Apple touch icons and the web app manifest keep their existing configuration.
