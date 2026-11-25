# v0.4.81 visual acceptance correction

## What was actually wrong in v0.4.80

The prior “shipped” report established functional tests and identity conservation, not the requested visual scale/readability. That was insufficient visual acceptance.

- The live HUD was connected: five initial icons did change to three, one, zero in the mixed-effect case. But 13px icons with 1px gaps, a 450px-wide movie and brief holds made this difficult to read.
- Persistent fire existed as seven small sparse squares per group (roughly a thin 50px-long strand), not BIG obvious layered fire. The reviewer was right that it did not satisfy the visual brief.
- The outlet clip was spatial, not a spawn/visibility toggle. However, the payload had accelerated inside the opaque neck and crossed the reveal in only a couple of 30fps frames. That looked like a pop. The old native movie was 450x800 although the saved stills were 720x1280.

## Corrections

- Filled, animated nested flame silhouettes use exact status colors. At five layers the nominal envelope is 184x74 canvas units, then 160x64,136x54,112x44,88x34,zero as one effect consumes layers. The actual default-450px window still is included, not only zoomed evidence.
- Icons remain individually small, now 18px with 5px gaps; each actual layer has its own icon. No timer bars or charge-model logic changes.
- Enhanced projectiles have a rounded burning head and animated forked flame tails rather than only colored lines. Visual size is bounded independently from damage-scaled line width; at most eight color shells, no particle physics nodes.
- The same physical hopper payload is speed-limited to 120 canvas units/second by the metering throat until the complete sphere clears the outlet lip. This is an explicit narrow physical pacing change, not a visibility animation or position tween. Existing gravity, restitution, air drag, identity, pointer-drag lever and reward/cost path are unchanged. Reveal starts inside the actual opaque opening (-42 rather than -36 machine units).
- Capture no longer inserts two frame waits for hopper milestone stills. Native movies start at 720x1280; temporary recording-only window overrides are restored and NOT shipped.

## Evidence to review

All paths are under `docs/shots/`.

1. `rr_v0481_default450_wait_five.png`: real default shipping-window size, persistent green inner/gold outer fire after waiting two seconds.
2. `rr_v0481_muzzle_before_after.png`: same-canvas actual stills showing the prior thin strand versus the corrected persistent flame.
3. `rr_v0481_flames_single_closeup.mp4` and `_single_native.mp4`: explicitly seeded Transfer +1 effect with five layers. Wait and zero damage keep five. Actual manual positive shots do 8,7,6,5,4 and leave 4,3,2,1,0 icons; the flame visibly shrinks and extinguishes. `rr_v0481_single_consumption_sequence.png` gives actual 5/4/3/0 stills.
4. `rr_v0481_flames_mixed_closeup.mp4` and `_mixed_native.mp4`: explicitly seeded three green +50% layers followed by two gold +1 layers. Damage12,8,5 leaves3,1,0 icons, because EACH effect type consumes one. `rr_v0481_mixed_consumption_sequence.png` gives actual frames. This is not the global-one-layer interpretation.
5. `rr_v0481_enhanced_tracer_frame.png` and `rr_v0481_tracer_closeup.png`: frames extracted from the actual moving projectile movie, not composed projectile artwork.
6. `rr_v0481_gumball_native.mp4`: uncut 1x pointer-drag scenario, same ball moving through the opaque neck and exiting to the tray.
7. `rr_v0481_gumball_closeup_1x.mp4`: crop/zoom of native7.5–12.0s. No time change.
8. `rr_v0481_gumball_replay_025x.mp4`: explicitly labeled quarter-speed replay of the SAME frames from native9.45–10.70s; no interpolated positions or gameplay time changes.
9. `rr_v0481_gumball_outlet_sequence.png`: consecutive native frames287–302. Blank at9.600s, first painted sliver9.633s, increasingly exposed sphere through9.8s, cleared around10.0s, then falling. `first_sliver`, `half_emerged`, `fully_emerged` full-frame PNGs also included.
10. `rr_v0481_gumball_trace.json`: actual per-tick positions. Payload array index4/ammo41 throughout; all12 bodies retained. Twelve partial-exposure simulation frames288–299 (9.600–9.967s), followed by free fall. Movie paint and simulation counters differ by approximately one frame; visual frame labels use actual movie frame numbers.

These clips demonstrate seeded effects honestly; they are not a randomly earned run. No browser capture or human-owner acceptance is claimed. Pixel inspection of the stills/contact sheet supplements, rather than substitutes for, reviewing the movies.

## Validation

Four new tests cover large shrinking persistent geometry, live HUD icon5→4→3→2→1→0/zero retention, physically progressive multi-frame emergence with identity conservation, and non-self-intersecting animated muzzle/projectile contours. Existing latest-damage, Transfer, editor/PIN and hopper reward tests remain. Final counts and deployed revision are in the parent handoff.

## Exact movie review points

Frame-pixel counts (not only state logs), in both native and unchanged-time close-up flame clips:

- Single type: five icons from0.317s, four at5.200s, three at7.067s, two at8.933s, one at10.800s, zero at12.667s. The wait and zero shot retain five until the first positive shot.
- Mixed types: five from0.317s, three at5.200s, one at7.067s, zero at8.933s.
- Flaming projectile still is native frame319 /5.317s.
- `rr_v0481_flames_frame_review.json` records these decoded-frame observations; `rr_v0481_evidence_manifest.json` records native/crop dimensions, FPS and duration.

Validation completed: GUT709/709,88 scripts,16,594 assertions; focused4/4. Python24, editor color504, overview/export regression, JS syntax, pre-push and font1414 coverage pass. Final single/mixed capture logs contain zero engine errors; known pre-existing full-suite warmup/resource-leak warnings remain. PIN/editor source files are unchanged by v0.4.81.
