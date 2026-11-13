# Audio sources

Only the 17 files used by the game are included. All are CC0 1.0 Universal. Original waveforms are unchanged; filenames are unchanged except the BGM filename. Runtime playback gain and looping are not edits to the source recordings.

## Music

- **Etirwer (Looped)** — Kistol. [Original page](https://opengameart.org/content/etirwer), [original download](https://opengameart.org/sites/default/files/Etirwer%20%28Looped%29_0.ogg).
- Original download filename: `Etirwer (Looped)_0.ogg`; included as `music/Etirwer_Looped.ogg`.
- [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/), as listed on the original page. Attribution is voluntary; credit is retained here.
- SHA256: `382c02bfb3d9abe1c9f432606dd95f27bcef28ac22097ccdcef12a8c608b421b`.
- One continuous 130.234-second loop across park, folding, inspection and flight.

## Sound effects

Created/distributed by **Kenney / Kenney Vleugels**. Each directory retains its pack's original `License.txt`. [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/); commercial use permitted and attribution not required.

| Official pack | Included original filenames | Game event |
|---|---|---|
| [RPG Audio](https://kenney.nl/assets/rpg-audio) | `kenney_rpg/bookFlip1.ogg`, `bookFlip2.ogg` | Committed fold, alternating variants |
| RPG Audio | `kenney_rpg/bookOpen.ogg` | Completed flip / unfold |
| [Casino Audio](https://kenney.nl/assets/casino-audio) | `kenney_casino/card-shove-1.ogg` | Actual aircraft release |
| Casino Audio | `kenney_casino/card-place-2.ogg` | First logical landing |
| Casino Audio | `kenney_casino/cards-pack-take-out-1.ogg` | Successful recovery / discovered item storage |
| Casino Audio | `kenney_casino/card-slide-2.ogg` | Inventory item taken into hand |
| [Impact Sounds](https://kenney.nl/assets/impact-sounds) | `kenney_impact/footstep_grass_000.ogg`, `footstep_grass_001.ogg` | Grounded actual walking, alternating variants |
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `kenney_interface/open_001.ogg`, `close_001.ogg` | Inventory, inspection, results, adjustment, tools and audio settings open/close |
| Interface Sounds | `kenney_interface/click_001.ogg` | Gauge starts |
| Interface Sounds | `kenney_interface/select_001.ogg` | Power chosen |
| Interface Sounds | `kenney_interface/tick_001.ogg` | Timing input producing an actual launch |
| Interface Sounds | `kenney_interface/confirmation_001.ogg` | Diagram save / workbench storage / clearing success; no currency reward implied |
| Interface Sounds | `kenney_interface/error_002.ogg` | Save validation failure / blocked launch |

No archives, pack previews, downloaded HTML, unused pack audio or generated music are included here. Download provenance and decoded measurements are retained under the ignored `build/hud_audio_review_20261028/` directory, outside shipped assets.

Initial playback: BGM −14dB before the Music bus; main effects −10dB before the SFX bus; footsteps −24dB. Default bus levels are Music 50% and SFX 75%, with separate mute controls. This leaves headroom for the originals whose decoded peaks slightly exceed 0dBFS.
