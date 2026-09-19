# QuranPause

> **Name:** the app is shown to users as **QuranPause** (Arabic: **وقفة قرآن**). The original name, QuranTime, was already taken on the App Store. The product name, scheme, bundle IDs (`com.quranpause.app`, `com.quranpause.app.monitor`, `com.quranpause.app.shield`), and App Group (`group.com.quranpause.shared`) all use the new name. Only the Xcode project, target, and folder names and the Swift module stay `QuranTime`; users never see them. Family Controls (Distribution) must be requested from Apple for all three bundle IDs before TestFlight or App Store distribution.

A native iOS 17+ app for making time for the Quran. SwiftUI, Family Controls, Managed Settings, Device Activity, AVFoundation, and local notifications; no account, server of its own, or API key. Prayer calculations use the MIT-licensed Adhan Swift 1.4.0 package. Quran text, saved-location prayer calculations, and the bundled azan work offline. Recitations stream from Quran Foundation / EveryAyah; initial city lookup uses Apple geocoding.

## Included

- Prayer tab with six daily times (five prayers plus sunrise), next prayer, six calculation methods, standard/Hanafi Asr, and location/city selection with an explicit local time zone. Times are calculated offline after selecting a location. High-latitude dates that cannot be calculated show an unavailable state. Match the method to your local mosque.
- Qibla bearing from true north, plus a live compass when a sufficiently accurate true heading is available. No fabricated compass heading on Simulator or devices without a compass. Keep the phone flat and away from magnetic interference.
- Optional azan notifications, scheduled for the next seven calendar days within the shared pending-notification budget. A 28-second bundled azan excerpt plays as the notification sound; tapping it opens Prayer and plays the full bundled recording. Reopen the app weekly and update location after travel. Silent mode, Focus, and notification settings can silence alerts. Azan playback never earns Quran listening credit.
- One reading format: the printed Mushaf page. Surahs, Home’s continue card, and the Quran tab all open the page itself; there is no ayah-by-ayah list anywhere. Tap any word and that ayah is tinted in place on the page, with Copy, Listen, and buttons to add or remove the next ayah. Listening plays the selected ayahs in order with the chosen reciter and stops at the end of the selection. Copy always yields canonical Unicode Arabic with the reference, never QCF glyph codes, and covers an ayah continued from the previous printed page. Copying part of an ayah, the English translation of the meanings, and per-ayah bookmarks were removed with the list format.
- During every unfinished real lockdown, `ManagedSettingsStore.application.denyAppRemoval` requests device-wide deletion protection (including QuranPause). Pausing, disabling future schedules, or completing only one of several sessions does not release it. Finishing all real sessions clears this app’s restriction. Practice sessions do not apply it. Individual Screen Time access is still revocable; the app is not tamper-proof.

- An ivory, forest-green, and gold interface with a custom Quran-and-clock app icon.
- Calm motion and haptics throughout. Buttons and cards press softly and sections fade into place. The session ring fills and breathes while time is earned, and timers roll between values. The player bar slides in, onboarding steps glide, and completing a session gets a small celebration. Favorites, ayah selection, page turns, and saved routines give light haptic feedback. With Reduce Motion on, movement becomes simple fades.
- All 114 surahs and 6,236 ayahs bundled offline, surah search, favorite surahs, and saved Mushaf reading position.
- A fixed-layout 604-page Madinah Mushaf reader drawn with the King Fahd Complex’s page-specific QCF V2 glyph fonts on the printed 15-line layout. Every page is verified at build time, in tests, and again before it is displayed. Swipe between pages in Mushaf order (swipe right for the next page), or use surah/page selection. Also includes favorite-surah actions and saved last page.
- First-launch setup asks for Screen Time and notification access, with explicit skip choices. The simulator explains that Screen Time permission requires an iPhone.
- Complete English and Arabic interfaces, in-app language selection, right-to-left layouts, and System / Light / Dark appearance settings. User-written zikr text stays unchanged.
- A user-selected focus duration of 1–120 minutes.
- App-lock schedules: every day, twice a day, every hour, every 30 minutes, or 1–8 custom daily times.
- Apple's privacy-preserving app, category, and website picker.
- Read or listen to earn Quran time. Reading earns time while a Mushaf page or surah reading screen is visible. Opening another QuranPause tab, leaving the app, locking the phone, switching apps, or pausing stops reading time.
- A play button on every surah streams a full recitation by the reciter chosen in Settings (10 verified reciters). A player bar appears on every tab, with Lock Screen controls, and playback continues to the next surah. Listening earns time only while the recitation is playing and audible, including with the screen locked. Muted or paused audio earns nothing, and reading and listening at the same time count once.
- Separate queued commitments when more than one scheduled lock becomes due. Each must be completed before the selected apps are released.
- Custom zikr notifications: every day, twice a day, every hour, or every 30 minutes. Add, edit, enable, disable, delete, set delivery times, and preview the exact message.
- A clearly labeled simulator practice mode. It does not claim to block applications.

## Open and run

Open `QuranTime.xcodeproj`, select the **QuranPause** scheme, and run on an iPhone simulator. The generated project is checked into the workspace; XcodeGen is only needed when changing `project.yml`.

```sh
xcodegen generate
xcodebuild -project QuranTime.xcodeproj -scheme QuranPause \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

For simulator reading/focus: tap **Begin Quran time**. To change duration or daily frequency, use **Routine** and save. Automatic locks stay off in the simulator because Screen Time authorization and app selection require a real device.

## Enable actual app blocking on an iPhone

1. In Xcode, assign your Apple Developer team to the QuranTime app target (shown as QuranPause) and both extension targets.
2. Register unique bundle identifiers for all three targets. If changing the App Group, update its string in `Shared/SharedStore.swift`, all three targets’ entitlements, and `project.yml`. All three targets must use the same registered App Group.
3. Enable **Family Controls** for the app, ActivityMonitor, and ShieldConfiguration. Enable the shared **App Groups** capability for all three targets (the shield extension reads language and appearance preferences). Xcode must use provisioning profiles containing these entitlements.
4. Build and run on your iPhone. Open QuranPause Settings → **Connect Screen Time** and authorize individual access.
5. Choose the apps/categories/websites you want to protect. Keep QuranPause itself out of the selection.
6. Save your duration, frequency, and daily times in **Routine**, with **Automatic daily locks** enabled. The new routine starts at its next occurrence, rather than creating retroactive sessions.

Apple controls the Family Controls distribution entitlement. Request distribution access for the app and each Screen Time extension before TestFlight or App Store distribution: https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement

A physical-device blocking test and Apple signing/distribution approval are still required. They cannot be verified by the simulator build.

## Timing behavior

The main app uses monotonic uptime and credits elapsed time only while a started session is in an active scene with a Mushaf page visible. Ticks longer than 2.5 seconds are discarded conservatively rather than treating suspension as reading. Time is checkpointed every second. A force-quit can lose a fraction of the last second, but never grants background time. Finishing a session cannot transfer surplus time to the next commitment.

Listening credit comes from the audio player, not the screen. Each second it credits the recitation time that actually advanced, but never more than the monotonic time that passed. It credits nothing while paused, stalled, buffering, or at zero output volume, and nothing across gaps longer than 2.5 seconds or backward jumps. Seeking and speed controls are not offered. Because of the `audio` background mode, credit continues with the screen locked, and a session that completes in the background releases its shields through the same shared-store transaction.

The monitor extension reconciles the current day's due occurrences and applies named Managed Settings shields. Daily/custom repeating intervals run for 23h59m to allow delivery when the device next wakes. Hourly schedules use twelve one-hour intervals, starting at even hours and ending at odd hours; their start/end callbacks cover all 24 hourly boundaries. Half-hourly schedules add 30-minute start/end warning callbacks to cover all 48 half-hour boundaries, staying below Apple’s limit of twenty monitored activities. Every callback runs the same idempotent reconciliation. Apple controls callback delivery, so validate this cadence on a real device before release. iOS controls callback delivery; callbacks occur when the device is used, not necessarily at an exact wall-clock instant. The app also reconciles due times whenever it becomes active. Previous completed occurrences are deduplicated. Entire days when the device was unused do not create historical backlogs. Already-created unfinished sessions remain pending across midnight and restarts.

The app and monitor use `NSFileCoordinator` around an atomic shared JSON file. Shield changes take place inside the same transaction. Interval end never clears a shield; for frequent routines it reconciles the next due commitment. Changing the duration does not shorten an existing session; disabling daily scheduling stops future locks while preserving existing commitments. Selection changes are disabled during an active commitment.

Individual Screen Time authorization remains revocable in iPhone Settings. This is a voluntary personal-focus app, not tamper-proof parental control. iOS does not verify that a person is actively reading; the timer measures foreground reading time and audible listening time in QuranPause.

## Zikr notifications

Daily zikr registers one repeating calendar trigger; twice-daily zikr registers two distinct times. Hourly zikr matches minute 0 of every hour. Half-hourly zikr uses two repeating minute-only calendar triggers (0 and 30), so it needs only two pending requests for the entire day. Editing cancels obsolete identifiers, including legacy identifiers; disabling/deleting cancels all of a reminder’s requests. Failed replacement attempts restore the previous requests. The app supports up to 50 saved reminders and caps enabled requests plus pending prayer alerts at 60, leaving headroom below iOS’s pending-notification limit. Permission denials and scheduling errors are shown in the UI. Focus modes, notification preferences, and the OS can silence or defer delivery.

## Validation

```sh
xcodebuild -project QuranTime.xcodeproj -scheme QuranPause \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' \
  -derivedDataPath build -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Simulator and unsigned physical-iPhone builds both passed with Xcode 26.6. The expanded simulator suite passed all 49 tests with zero failures.

49 XCTest tests cover inactive-time exclusion, prayer times against the published Adhan reference, Qibla bearing and compass wrap, azan audio assets, ayah copy/listen selection on Mushaf pages, all 604 pages split into their ayahs without changing a printed glyph, rejection of an ayah map that does not match its page, distribution metadata, suspended/reversed clocks, exact completion, multiple commitments, repeated callbacks, persisted progress, invalid credit, daily reconciliation, future-only activation, disabling future locks, duration changes, all 114 surahs / 6,236 ayahs across 604 pages, all 604 Mushaf pages against their verified checksums and glyph runs, rejection of altered layouts, print-checked pages (76, 77, 534, 589), page-index agreement with the Mushaf, audible-only listening credit (stalls, silence, backward jumps), listening that credits only during a running session and never double-counts with reading, the verified reciter catalogue, legacy-state migration, favorites, page persistence, all 24/48 frequent lock boundaries, notification recurrence/identifiers/content, and Arabic resources. Simulator UI checks include routine editing and saving, Arabic/English reading, timer controls, relaunch persistence, and unchanged stored remaining time while backgrounded. The first-launch notification prompt, Arabic RTL/dark appearance, favorite toggles, and page navigation were also exercised in the simulator. Actual notification delivery and app-blocking enforcement still need a device check.

Before release, test on a signed physical device: app/category/domain shields, lock start while QuranPause is closed, returning from background and screen lock, queued sessions, restarting the phone, midnight/time-zone changes, revoking authorization, completion unlock, notification delivery, and distribution entitlements. No physical-device enforcement or App Store deployment was performed here.

## Project layout

- `QuranTime/App`: app shell, theme, and brand mark.
- `QuranTime/Core`: focus lifecycle, schedule/notification services, offline Quran loader.
- `QuranTime/Features`: Today, Quran surah list and Mushaf reader, Routine, Zikr, and Settings.
- `Shared`: persisted models and coordinated App Group storage.
- `Extensions/ActivityMonitor`: scheduled app shields.
- `Extensions/ShieldConfiguration`: branded lock screen message.
- `QuranTimeTests`: behavioral tests.
- `scripts/generate-icon.swift`: reproducible vector drawing of the app icon.
- `scripts/generate-localizations.py`: generates English/Arabic resources from reviewed `translations.json`.
- `scripts/download-mushaf.py`: builds and verifies the Mushaf pages, fonts, manifest, and page index.
- `scripts/download-recitations.py`: builds and verifies the bundled reciter catalogue.
- `screenshots`: simulator captures.

## Quran content and license

The bundled, unmodified `quran_en.json` is from Quran JSON 3.1.2 by Risan Bagja Pradana, which attributes its Uthmani text to The Noble Qur’an Encyclopedia. Content attribution is also available in the app Settings. The upstream `LICENSE.txt` is bundled as `Quran-LICENSE.txt` and specifies **CC BY-SA 4.0**. The content retains that license; this is separate from the original app source code. English text is a translation of the meanings, not the Arabic Quran itself.

- https://github.com/risan/quran-json
- https://cdn.jsdelivr.net/npm/quran-json@3.1.2/dist/quran_en.json
- https://quranenc.com/en/home
- https://creativecommons.org/licenses/by-sa/4.0/

### Recitations

`recitations.json` lists full-surah recordings from Quran Foundation's recitation catalogue (`api.quran.com`), streamed from `download.quranicaudio.com`. Only the addresses are bundled. `scripts/download-recitations.py` includes a reciter only if all 114 surahs pass these checks:

- exactly one recording per surah;
- all files in one folder on Quran Foundation's audio host;
- every file answers over HTTPS as `audio/mpeg`;
- every file's real duration, read from its MP3 header, is in proportion to its surah (0.5×–2× of that reciter's median seconds per word), which catches truncated files or files attached to the wrong surah.

The catalogue's own file sizes proved unreliable and are not used. Two catalogue entries fail and are excluded with the reason recorded in the script: Mohamed Siddiq al-Minshawi (Mujawwad), whose files return HTTP 404, and Mohamed al-Tablawi, whose catalogue lists 128 files including another reciter's recordings. A sample of 50 recordings (5 surahs × 10 reciters) was also loaded with AVFoundation: all were playable, and durations matched the verified values within 0.65%. The app re-checks the catalogue at launch (114 HTTPS tracks on that host per reciter).

- https://quranicaudio.com/
- https://api-docs.quran.com/

### Mushaf pages

The reader shows the 604-page, 15-line Madinah Mushaf (Hafs an Asim). No Quran text is typeset by the app:

- **Glyphs:** the King Fahd Glorious Quran Printing Complex (KFGQPC) QCF V2 page fonts (`QCF2001`–`QCF2604`, © KFGQPC). Each font holds the word shapes printed on its page. The fonts are delivered through Quran Foundation’s font CDN. Basmala lines use the Complex’s own glyphs from Al-Fatihah 1:1.
- **Placement:** Quran Foundation’s word-level V2 page and line data, fetched surah by surah so no word can be dropped or borrowed from a neighbouring page.
- **Ayah ownership:** `Mushaf/Ayahs/ayahs-N.json` records how many of page N's glyphs belong to each ayah, in printed order, built from the same verified word data. A tap resolves to an ayah through that list, so no boundary is inferred from the glyphs, and each file has its own checksum in the manifest. If it fails verification the page still prints, without on-page selection. Splitting a line into per-ayah spans was measured to leave every printed line's width unchanged.

`scripts/download-mushaf.py` writes nothing unless the whole Mushaf verifies. It checks 114 surahs and 6,236 ayahs in order, and one ayah marker per ayah. Every word must sit on a valid page and line in reading order. Each page must place exactly its own font’s word glyphs, in order, with none missing, repeated, or taken from another page. Pages 1–2 must have 8 lines and the rest 15, with 114 headings and 112 separate basmalas (Al-Fatihah includes it as its first ayah; At-Tawbah has none). It then writes `Mushaf/manifest.json` with SHA-256 checksums of every layout and font. The app re-checks those checksums and the glyph run before showing any page; a page that fails shows an error instead of text.

Upstream data was checked against the King Saud University scans of the printed KFGQPC Mushaf. The script lists each exception it found and pins it to the upstream value, so a future source change fails the build:

- 84:21’s ayah marker is on page 589, line 14 (the source says line 13).
- The fonts for pages 256 and 270 contain a few unused trailing glyphs; the printed pages end exactly where the layout does.

`page_index.json` (surah → page navigation and saved progress) is regenerated from the same verified pages, so the index and reader always agree. The previous Al Quran Cloud boundaries followed a different printing and put 56 ayahs on the wrong page for this Mushaf (for example 55:68–69 on page 534 and 87:11–15 on page 591). All 56 were checked against the printed pages. Juz references are still from Al Quran Cloud’s `quran-uthmani` metadata; only page/juz/ayah references are used, and the licensed Quran text remains the original unmodified Quran JSON resource.

Refresh before a release with `python3 -m pip install fonttools brotli`, then `python3 scripts/download-mushaf.py` (downloads are cached in `build/mushaf-cache`; add `--offline` to rebuild from that cache).

- https://qurancomplex.gov.sa/
- https://quran.ksu.edu.sa/
- https://alquran.cloud/api

- https://api-docs.quran.com/legal/mushaf-fonts-and-images/
- https://api-docs.quran.com/docs/tutorials/fonts/page-layout/

Arabic is available in Settings → Language and in the first-launch menu. Appearance follows the phone by default, with explicit Light and Dark overrides. The shield reads the same language/appearance preferences through the App Group. Existing routine, sessions, reminders, and saved positions are migrated without resetting user data when new fields are missing. Bookmarks saved by earlier versions stay in storage, unused, rather than being deleted.

Apple references:
- https://developer.apple.com/documentation/screentimeapidocumentation
- https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter
- https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement

- https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/warningtime
- https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/excessiveactivities

## September 18 update: validation and new features

The project specification and generated project now include all four iPad orientations, display names for both extensions, the location usage description, and the explicit Combine import used by the app timer. Developer team XA5BVJ88VD is preserved. Open `QuranTime.xcodeproj` and create a fresh archive; old archives do not incorporate these fixes.

Prayer and zikr scheduling serialize their writes to avoid spending the same notification capacity concurrently. Prayer alerts are nonrepeating absolute-time requests, recalculated per local date (including DST), and only this app’s prayer identifiers are replaced. The Prayer screen shows the scheduled-through time. With many zikr reminders, prayer coverage may be shorter than seven days. New city selection and prayer-method changes replace old prayer alerts. Umm al-Qura Isha uses a 120-minute interval during Ramadan.

Azan source: [Azan.ogg by Andrewler](https://commons.wikimedia.org/wiki/File:Azan.ogg), CC BY-SA 4.0. Bundled MP3 conversion and 28-second PCM WAV excerpt remain under that license; attribution appears in Prayer and `Azan-LICENSE.txt`. Adhan's MIT license is bundled in `Adhan-LICENSE.txt`. Ayah audio paths are mapped to all ten selected-reciter styles from [EveryAyah’s catalogue](https://everyayah.com/data/recitations.js).

Physical-device release checks: deletion denied during lockdown and restored after all commitments; authorization revocation behavior; scheduled monitor enforcement while the app is closed; true-heading compass calibration and rotation; location permission denial; azan delivery with the screen locked; travel/time-zone updates. Simulator tests cannot establish device enforcement or App Store acceptance.
