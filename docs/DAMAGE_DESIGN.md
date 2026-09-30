# Mechs of Night City: part damage and the HUD damage schematic

Status: draft for review (2026-09-30). Not built yet. Items marked **[spike]** are unknowns that a small test build settles before anything depends on them.

## 1. What Omar asked for

1. **Dynamic damage on the model.** Parts of the mech can be damaged and shot off, the way the game's own Minotaurs can lose both HMGs.
2. **A HUD sprite** showing which parts of the mech have taken damage.

## 2. What the game already gives us

Read from the game's files (WolvenKit) and the decompiled scripts; not yet tried in the mod.

### Weak spots (the vanilla "shoot the guns off")

- The Minotaur has **two weak spots**. The mod already finds them (`GetWeakspotComponent().GetWeakspots()`, logged as "weak spots: 2") and currently makes them invulnerable while piloting.
- The entity's animation setup has two parameters, `leftWeakspotVisibility` and `rightWeakspotVisibility`, so the two weak spots are almost certainly the left and right arm/gun mounts.
- Each weak spot is its own object (`ScriptedWeakspotObject`) with its own health pool (`WeakspotHealth`). It already does the following:
  - Plays damage-stage effects at 70% and 35% (`weakspot_damage_stage_01` / `_02`).
  - When destroyed (`DestroyWeakspot`):
    - switches to a "destroyed" appearance and hides mesh parts through the owner's animation parameters;
    - turns its collider off;
    - plays `weakspot_destroyed` / `weakspot_broken` effects;
    - sends the owner a `WeakspotOnDestroyEvent`.
  - `ScriptedWeakspotObject.Kill(weakspot)` destroys one on demand.
- **This is the vanilla mechanism for guns being shot off.** We can use it as it is instead of building our own.

### Knowing where a hit landed

- Every hit carries the collision shape it struck. `HitShapeUserDataBase.GetHitReactionZone(hitEvent.hitRepresentationResult.hitShapes[0].userData)` gives a zone (head, arms, legs, chest, "special"). The game's own boss scripts use exactly this call.
- The mod already sees every hit on the piloted mech (the `TargetTrackingExtension.OnHit` wrap, where it logs "AI kept out: a hit"). That is the natural place to read the zone.
- **[spike S1]** Which zones the Minotaur's hit shapes actually report. It may only use a few, since it is built on the Maelstrom exo rig.

### Effects and model parts

- An effect defined on the entity can be started with `entSpawnEffectEvent { effectName }`. Vanilla boss scripts do this (for example `death_head_explode`).
- **[spike S2]** List the effect names the Minotaur entity carries (smoke, sparks, fire, the `v_minotaur_weakspot` and `v_minotaur_explosion` effects exist in its folder).
- Every appearance of the Minotaur is built from separate mesh components: `body`, `legs`, `arm_l`, `arm_r`, `weapons_l`, `weapons_r`, `hands`, `bags`, `lights_glass`, plus lights. A component can be hidden from script. So small parts (bags, lights, a gun if the weak spot route fails) can be knocked off. We cannot show new broken geometry without making new meshes, which is out of scope.

## 3. Design

### 3.1 The damage model: zones on top of the hull

The hull (health pool × the HULL setting) stays the mech's life. On top of it, each **zone** has its own integrity from 0 to 100%. Zones only take damage from hits on them, and their effects are local.

| Zone | Where its damage comes from | Effect as it drops | At 0% |
|---|---|---|---|
| **MK.31 left / right** | The vanilla weak spot on that arm (its own health), scaled by the HULL setting | Stage effects at 70 / 35% (vanilla); more spread; the gun reticle on the HUD flickers | Weak spot destroyed: vanilla "gun shot off" look. That gun is offline; the fire modes use the other one; HUD shows it destroyed |
| **Sensor head** | Head-zone hits | Below 50%: HUD static bursts, rangefinder unreliable | Optics and rangefinder offline, heavy HUD noise |
| **Legs** | Leg-zone hits | Below 50%: slower walk, limp in the camera bob | Below 15%: crawl speed |
| **Launcher pods** | Hits on the back and shoulders (zone TBD, S1) | Missile reload slower | Missiles offline |
| **Torso** | Everything else | Nothing extra: this is the hull | Hull at 0% = mech destroyed (as now) |

- **Damage split:** a hit always lowers the hull as the game already does. Our zone numbers come from the same hit's damage, scaled per zone so a zone can be broken long before the hull fails.
- **Default: on.** A CONFIG switch, PART DAMAGE ON/OFF, for anyone who wants only the hull.
- **Recovery:** zones don't heal while linked. With the planned "own mech", they are repaired at the carrier truck. Until then they reset when a new test mech spawns.
- **Gun shot off in practice:**
  - The weak spots stop being invulnerable (the current shield goes). Their health is multiplied by the HULL setting so they last proportionally.
  - When one is destroyed, `WeakspotOnDestroyEvent` tells us which side. The mod already survives a gun disappearing (the weapon watch added today), and gains a "destroyed" state so it doesn't keep looking for it.
  - **[spike S3]** Confirm what destroying a Minotaur weak spot really does: does the gun mesh disappear, does its weapon object go, and can the other gun still fire? This decides whether we lean on vanilla or hide the `weapons_l/r` component ourselves.

### 3.2 Visual damage

1. **Vanilla weak spot visuals** for the guns: stage smoke and sparks, then the destroyed look.
2. **Zone effects** at 50% and 20% on the other zones, played on the mech: smoke from the torso, sparks at the legs, a flickering sensor light. Started with `entSpawnEffectEvent` where the entity defines a fitting effect (S2), otherwise with the effect system at the zone's position.
3. **Knocked-off small parts:** the bags or a light cluster hidden when the torso or head zone breaks, for a visible change.
4. **The hull alarm and hit flash** stay as they are.

### 3.3 HUD: the damage schematic

A small wireframe of the Minotaur on the chassis plate, beside the HULL bar, in the HUD's existing style.

- **Shape:** built from the HUD's own primitives, as bars and plates arranged as a front view: sensor head, torso, both arms with their guns, both legs, launcher pods. No new texture files, so the mod stays script-only. If it looks too simple, the follow-up is a custom silhouette texture shipped as an archive (ArchiveXL), a larger change.
- **Colour per zone:**
  - green: above 70%
  - amber: 70 to 35%
  - red: below 35%
  - destroyed: dark with a red cross or hatch, and the label "OFFLINE"
- **Behaviour:**
  - The zone that just took a hit flashes briefly, so you can see what's being hit.
  - A destroyed part blinks for two seconds, then stays marked.
  - Labels are small and only on destroyed parts ("MK.31 L OFFLINE"), to keep the HUD sparse.
- **Size:** about 180 × 220 design units, left of the HULL text. It's only redrawn when a zone changes, using the same event-only approach as the rest of the HUD.

### 3.4 Performance

- Zone bookkeeping runs only on hits taken by the piloted mech: a few reads and one table update per hit.
- Effects are started only when a zone crosses a threshold.
- The schematic is about 12 widgets, touched only when a zone changes. No per-frame cost.
- Nothing runs when not piloting. The weak spot shield and the zones are removed at disconnect, as the hull multiplier is today.

## 4. Build order

1. **Spike build** (S1–S3):
   - log the hit zone of every hit on the piloted mech;
   - list the mech's effect names;
   - with a DIAGNOSTICS-only terminal button, destroy one weak spot on the piloted mech and log what happens to the gun.
   - One test session from Omar answers all three.
2. **Guns:** the weak spot route (or component hiding if S3 says so), the "destroyed" gun state in the gun logic and the HUD.
3. **Zones:** head, legs, pods, with their effects and thresholds.
4. **HUD schematic.**
5. **Visual extras:** zone effects, knocked-off small parts.
6. **CONFIG:** PART DAMAGE switch, and its line in the mod description.

## 5. Risks

- **Hit zones may be coarse on this rig (S1).** If most hits report one zone, zones fall back to the direction of the hit relative to the mech (front/back/left/right, high/low). That is still good enough for arms, legs and head.
- **Destroying a weak spot might do more than we want (S3):** kill the mech, drop both guns, or trigger a boss phase. We only use it if the spike shows the right behaviour, otherwise we hide components ourselves.
- **No new broken meshes:** "shot off" means hidden, not a mangled stump, unless someone makes new meshes later.
- **Mechs not being piloted are untouched.** Enemy Minotaurs keep their vanilla weak spots and nothing else changes for them.
