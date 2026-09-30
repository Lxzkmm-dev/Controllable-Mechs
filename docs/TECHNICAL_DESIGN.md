# Controllable Mechs: control framework technical design

Status: **rev 3 (2026-09-30), after spike batches 1-3.** The plan is now the Minotaur first (M1), then the emplacement through the vanilla turret takeover (M2), then a feel pass (M3). Section 14 has what the spikes showed; sections 10, 11 and 13 carry the revised plan. Where older sections below conflict with section 14, section 14 wins.

Rev 2 (agreed with changes). Omar's review asked for four changes, all folded in below:
1. Every unit is a **body + skin**.
2. **S4/S5 move into the first spike batch.**
3. S2 **prefers real projectiles with V as the instigator**.
4. A new **S0** tries the vanilla turret takeover.

His answers to the open questions are in section 13.
Baseline: 0.1 alpha (d397dab) stays as it is. The framework replaces its Pilot Mode rather than patching it.
Research behind every API named here: `docs/MODDER_RESOURCES.md`. Tags follow that file: **[proven]** worked in game in this mod; **[used by X]** another installed mod does it; **[decl]** declared but not tried; **[spike]** needs a small test build before we rely on it.

---

## 1. Why a framework

The alpha drove a live AI mech with AI orders and bent its rounds toward the reticle. Each problem Omar hit came from that:

- The camera fought the chassis, because the AI turns it in jerky steps.
- The rounds and the muzzle flash disagreed: the visible MK.31s are skinned to the mech's arm bones and only its animation moves them (WolvenKit, `MODDER_RESOURCES.md`).
- It teleported near walls, and "running" was slower than walking.

We don't control those parts, so we can only work around them.

The framework flips this. **We own every moving part that matters**: the aim, the gun's pose, where rounds leave, the camera, the input and the HUD. The game's systems are used only where they're reliable: spawning, rendering, damage, sound and effects. One controller drives any "unit" (an emplacement first, then mechs) through the same code.

**Goals**
1. **Reticle control:** a unit's guns traverse (yaw) and tilt (pitch) to follow the reticle, at a speed and within limits the unit defines. Heavy things feel heavy.
2. **One origin:** rounds, tracers and muzzle flash all come from the gun you see, along its barrel.
3. **Performance:** nothing runs when no unit is controlled. Per-frame work while controlling stays small and bounded (section 8).
4. **Stability:** one teardown for every exit path, with no stuck controls, cameras, restrictions or spawned leftovers.
5. **Reuse:** the MG emplacement, then the Minotaur, then other mechs share one core. A new unit is a small class plus data.

**Not goals for now:** a published framework; controller support (later); multiplayer; saving a spawned emplacement across loads (later).

---

## 2. Architecture

The framework lives in its own folder and module inside this mod, with no knowledge of any specific unit (the TerminalKit pattern: abstract classes the units subclass).

```
r6/scripts/ControllableMechs/
  Control/                     module ControllableMechs.Control   (the framework)
    CMCSession.reds            the one controller: begin/end, frame loop, exits
    CMCInput.reds              raw input + game actions -> one input state per frame
    CMCUnit.reds               abstract CMCUnit: what every controllable implements
    CMCAim.reds                reticle -> desired aim; gun traverse (rate, limits, inertia)
    CMCParts.reds              spawned part entities and their per-frame transforms
    CMCCamera.reds             camera entity: sight view / chase view, clipping
    CMCWeapon.reds             a gun: cadence, heat/ammo, muzzle, firing, effects
    CMCRay.reds                aim ray (world + dynamic, hit entity)
    CMCHud.reds                reticle, gun pips, status; built once, values only
    CMCLock.reds               V's restrictions, save lock, vanilla HUD fade
  Units/
    CMUEmplacement.reds        first unit: spawned MG emplacement
    CMUMinotaur.reds           later: the Minotaur on the same core
  UI/, Core/, Mech/            existing terminal, keys, link (kept; link feeds units later)
```

**Body + skin: the rule for every unit.** A unit is **a vanilla gameplay entity (the body) wearing our parts (the skin)**:
- **Body:** it provides everything spawned meshes can't: health and damage, attitude (friendly to V), and being targeted and shot by enemies, plus save and streaming behaviour.
  - Emplacement: a spawned vanilla turret device (e.g. `security_turret_1.ent`, which Night City Empires already spawns and befriends).
  - Mech: the Minotaur NPC itself.
- **Skin:** our moving parts (gun, cradle), attached to the body as components wherever possible (S4/S5), or as separate entities placed every frame where not (a static emplacement tolerates that).
- **Hidden body guns:** the body's own guns are hidden (`Toggle(false)` on their mesh components, S5), so the only guns you see are ours.
- **Health:** unit health, "destroyed" and "friendly" all come from the body. The session ends when the body dies.

**One session, one unit.** `CMCSession` is a `ScriptableSystem`. It holds `m_unit: ref<CMCUnit>` and is either idle or controlling. Everything per-frame hangs off the session and stops when the session ends.

### 2.1 The unit contract

```redscript
public abstract class CMCUnit extends IScriptable {
  // lifecycle (the session calls these; a unit never starts its own loops)
  public func Begin(s: ref<CMCSession>) -> Bool      // spawn/find parts, weapons; false = abort cleanly
  public func End(hard: Bool) -> Void                // despawn/restore everything it made
  public func IsAlive() -> Bool                      // false = session ends ("UNIT LOST")

  // every frame, in this order
  public func Tick(dt: Float, input: ref<CMCInputState>, aim: ref<CMCAim>) -> Void  // move parts, fire
  public func CameraMount() -> WorldTransform        // where the sight camera sits this frame (e.g. on the pitch part)
  public func ChaseAnchor() -> Vector4               // centre for the chase view

  // ten times a second
  public func SlowTick(now: Float) -> Void           // HUD values, sanity checks
  public func Hud(state: ref<CMCHudState>) -> Void

  // description
  public func Name() -> String
  public func AimLimits() -> ref<CMCAimLimits>       // yaw/pitch limits and rates (data, not code)
}
```

The session owns the *when*. Units own the *what*.

---

## 3. The session (`CMCSession`)

### 3.1 Begin / end

**Begin(unit):**
1. Check we can: not in a menu, pause or photo mode, and the unit's own `Begin` returns true. Combat is allowed.
2. Apply V's lock (`CMCLock`): the gameplay restrictions **[proven]**, a save lock **[proven]**, and the vanilla HUD faded **[proven]**.
3. Spawn the camera entity `base\entities\cameras\simple_free_camera.ent` **[proven]**. When `Entity/Attached` fires, activate it.
4. Build the HUD once **[proven pattern]** and start the frame loop.

**End(reason, hard):** this is the only teardown, used by every exit path (key, unit lost, V hit, distance, session end, a timeout while spawning).
1. Bump the generation counter, which kills any queued frame and timer.
2. `unit.End(hard)`.
3. Hand the camera back to V (`Deactivate`, FPP `Activate` + `ResetPitch`) **[proven]**, then despawn the camera after the blend.
4. Remove the HUD, V's restrictions, the save lock and the input state.

**Hard end** (session end, load): no blends; despawn everything immediately.

### 3.2 The frame loop **[proven]**

Each frame, `DelayEventNextFrame(player, CMCTickEvent)` queues an event on V, and `@addMethod(PlayerPuppet) cb OnCMCTick` forwards it to the session. A 0.5 s watchdog restarts the loop on a `DelayCallback` timer if frames stop. Both are generation-guarded. `dt` comes from engine time, clamped to 0..0.1.

The order within a frame is fixed:
1. `input.Sample()`, which consumes the deltas accumulated since the last frame.
2. `aim.Update(dt, input)`, the desired aim from the reticle.
3. `unit.Tick(dt, input, aim)`, which moves parts and fires.
4. `camera.Update(dt, unit)`, placed from the unit's *new* pose, so there's no one-frame lag.
5. `hud.Frame()`: only the markers that changed.

Every ~0.1 s: `unit.SlowTick`, `hud.Refresh`, and the exit checks.

### 3.3 Exits

Each check runs at 10 Hz:
- the key (the Pilot key, rebindable; `\` by default);
- the unit is gone or destroyed;
- V leaves range;
- V is hit (optional, as now);
- V is dead or in a vehicle;
- a menu opens (pause, not exit: the loop idles while the game is paused).

`Session/BeforeEnd` and `OnPlayerAttach` → hard end.

---

## 4. Input (`CMCInput`) **[proven]**

- **Mouse:** Codeware `Input/Axis` for mouse X/Y and `Input/Key` for buttons and keys. Both are registered once at attach (`Forever`) and return straight away when idle.
- **Game actions:** a `PlayerPuppet.OnAction` wrap takes rebind-aware actions (Forward/Back/Left/Right, attack, aim, the camera mouse). Returning true swallows them while controlling.
- **One state per frame:** everything feeds one `CMCInputState`: accumulated `lookX/lookY` (degrees, scaled by the game's mouse sensitivity and ours), `move` (a 2D vector), `fire`, `fireAlt`, `zoom`, `view`, `exit`. Units read this state and never touch input directly.
- **Keys:** the framework's keys go in the Exploration, Combat and Locomotion contexts, with a debounce **[proven]**.

---

## 5. Aim (`CMCAim`)

The aim separates **where the pilot is looking** from **where the gun points**:

- **Look:** the reticle direction, straight from the mouse. It's what the camera shows in the chase view and what the gun is chasing.
- **Gun:** its yaw and pitch, which follow the look at the unit's traverse rate, with inertia (the spring-and-damper from the alpha rig, now applied to the *gun*, not the camera).
- **Limits** come from the unit's `CMCAimLimits` (data):

```
yawMin/yawMax (deg, relative to the base; 360 = unlimited), pitchMin/pitchMax,
yawRate, pitchRate (deg/s max), stiffness, damping (spring), recoilKick
```

- **Sight view:** the camera rides the **gun**, so the view is the gun's pose. The pilot's mouse sets the look target and the gun (and view) swings toward it with weight. The reticle is always where the barrel points, so the rounds, tracer and flash line up by construction.
- **Chase view:** the camera orbits behind the unit and follows the *look*. The gun lags toward it. A second marker on the HUD (the "gun pip") shows where the barrel points now, projected into the screen, and it settles onto the reticle as the gun catches up.

This is where the heft lives: turret traverse rates and inertia, not camera smoothing.

---

## 6. Parts and transforms (`CMCParts`)

A unit is made of **parts**. Each part is its own spawned entity, and the framework places each part every frame from a small transform tree it computes itself:

```
base (static)      = unit origin + base rotation
yaw part           = base  * rotZ(gunYaw)            (pivot: yaw axis offset)
pitch part         = yaw   * offset(trunnion) * rotX(gunPitch)
muzzle(s)          = pitch * offset(muzzle_i)        (not an entity, just a transform)
camera (sight)     = pitch * offset(sight)
```

- **Preferred for anything that moves with an animated body (mechs): components on the body.** The skin's meshes go on the body as components bound to its root or a bone (`entHardTransformBinding` with `bindName`/`slotName`) and are rotated with `IPlacedComponent.SetLocalOrientation`, so they ride the animated pose natively, with no trailing or jitter. That's **[decl]**, and spikes **S4/S5 (first batch)** decide it.
- **Otherwise (static bodies such as the emplacement): separate part entities.** `Entity.SetWorldTransform(WorldTransform)` per moving part per frame. It's **[proven]** on our camera entity every frame and **[used by XUtils]** for the same purpose. For the emplacement that's 2 calls per frame (the yaw and pitch parts), and only when their pose changed (a dirty check, as XUtils does).
- **Why separate entities, not one entity with bone control:** we have no script API that sets arbitrary bone rotations on a rig, and the per-component parenting route (`entHardTransformBinding` + `SetLocalOrientation`) is only **[decl]**. Separate entities use only proven calls. If the component route proves out later (spike S4), a unit can switch to it without the rest of the framework changing.
- **Where part entities come from**, in order of preference:
  1. **Existing `.ent` files** that already contain the right mesh. The **MaxTac turret** has separate meshes for the ground base, rotating base, arm and guns, but they're components of one `.ent`, so this needs spike S1 to split them.
  2. **Runtime assembly:** spawn an empty entity and add an `entMeshComponent` with the part's mesh at build time, through the Codeware `EntityBuilder` assemble event (`...AddComponent`) **[used by XUtils]** **[spike S1]**.
  3. **Our own tiny `.ent` files**, one per part, built with WolvenKit and loaded with ArchiveXL. It's reliable and fully under our control, but it's an asset pipeline. It's the fallback if (2) fails.

The design doesn't care which: a part is "a template path + a mesh + a pivot offset" in the unit's data.

---

## 7. Weapons (`CMCWeapon`)

A weapon is **data plus a muzzle transform from the part tree**:
- cadence (rounds/s), spread (deg), heat per shot, cool rate, overheat lockout;
- damage per round, range, the tracer and muzzle effect resources, the sound events.

Every shot:
1. Take the muzzle transform. The origin is the muzzle; the direction is the barrel plus spread.
2. **Aim ray along the barrel:** `SyncRaycastByQueryFilter(origin, origin + dir*range, QueryFilter.ALL(), out hit, ...)` + Codeware `TraceResult.GetHitEntity` **[used by Nitrous]**. That gives the impact point and the entity hit.
3. **Visuals from the muzzle:** a muzzle flash at the muzzle and a tracer along origin → impact with `FxSystem.SpawnEffect(FxResource, WorldTransform)` **[used by XUtils]**, plus the gun sound on the part entity **[proven: PlaySoundEvent]**. The effect paths get picked from the game's files with WolvenKit (spike S3).
4. **Damage: real projectiles preferred, with V as the instigator (owner).** One route then gives tracers, hit reactions, armour and damage together, and crediting V keeps aggro, kills, XP and NCPD behaviour sane. Hitscan would mean hand-building tracers and the damage pipeline, so it's the last resort. **Spike S2** confirms the route:
   - **(a) real projectiles:** `gameprojectileSpawnerLaunchEvent` queued on a weapon *item* with a projectile spawner, position and orientation from our muzzle **[used by Doctrine Hydra, Missile Rain]**. Real bullets, real hit reactions.
   - **(b) `AIWeapon.Fire`** from a spawned weapon item owned by the unit **[proven with an NPC owner]**. Needs a weapon object without an NPC.
   - **(c) hitscan:** apply the hit ourselves to `GetHitEntity` through the game's damage pipeline (an attack record via TweakXL). This needs the most research.

   The emplacement starts with whichever of these S2 shows working. The weapon class hides the choice, so the rest of the framework doesn't change.

**Result:** rounds, tracer and flash all start at the barrel you see, go the way it points, and land where the gun pip says.

---

## 8. Performance budget

| When | Work |
|---|---|
| Idle (no unit) | Nothing per frame. Input hooks return after one check; the game-action wrap does one null check. |
| Controlling, per frame | Input sample; aim spring math; ≤ 2 `SetWorldTransform` for parts (dirty-checked); 1 camera transform; weapon cooldowns; while a trigger is held, 1 query-filter raycast per shot fired (not per frame) plus 2 FX spawns per shot; HUD marker moves only when they change. |
| Controlling, 10 Hz | HUD text and bars; chase-camera clipping ray (moved from per-frame); exit checks. |
| Spawning | Part and camera entities once at Begin; despawned at End. |

Hard caps:
- **FX:** at most 1 tracer + 1 flash per round.
- **Rate of fire:** capped per weapon at 20 rounds/s.
- **Effects:** no FX keeps running after its round.

---

## 9. Stability

- **One teardown path**, generation counters on every callback, and weak back-references (`wref`) from callbacks.
- **Spawned entities:** tracked by `EntityID`, despawned at End, and on `Session/BeforeEnd`. Nothing persists in the save (`persistState/persistSpawn = false`).
- **V's lock:** every restriction applied is removed at End, and a hard end also clears them.
- **Save lock:** held only while controlling.
- **No `@replaceMethod`.** Only `@wrapMethod` on `PlayerPuppet.OnAction` / attach / detach (already in the alpha).
- **Diagnostics:** an optional debug line and TerminalKit log lines at each stage (proven useful in the alpha), off by default.

---

## 10. The emplacement (`CMUEmplacement`), now M2

**Rev 3:** S0/S0b passed. A spawned vanilla turret taken over the game's own way already has a matching barrel, flash and rounds, V-credited damage, and a clean exit. So the emplacement is **M2: spawn the Arasaka floor turret (the Minotaur's HMG look) or Security 1 from the terminal, enter with the Pilot key, V stays visible**. The framework adds the session, keys, HUD and weight on top of the vanilla takeover where it can. The custom skin plan below is kept only as the fallback.

- **S0 first:** if a spawned vanilla security turret accepts the game's own turret takeover (the quickhack route), the emplacement is nearly free: the barrel, flash and rounds already match. The framework then only adds the session, weight, HUD and exits, and its main effort goes to the Minotaur. The rest of this section is the plan if S0 fails or feels too limited.
- **Spawn:** from the Robot Link terminal (TEST → SPAWN EMPLACEMENT), 4 m ahead of V. It's placed on the ground with a downward raycast **[proven pattern]** and faces V's forward.
- **Body:** a spawned vanilla turret device (Night City Empires' `security_turret_1.ent` pattern: spawned through the DynamicEntitySystem and made friendly through its device state), with its own gun meshes hidden. It gives the emplacement health, "friendly to V" and enemy targeting.
- **Skin parts:**
  - **Base:** the MaxTac turret's ground base (`w_turret__maxtac_turret__base1_g_base.mesh`).
  - **Yaw part:** its rotating base (`..._r_base.mesh`).
  - **Pitch part:** the arm with the guns (`..._arm.mesh` + `..._guns.mesh`).
  - Fallback if S1 can't split meshes: the portable turret (real `yaw`/`pitch` bones) driven as one entity, or a static HMG prop on our own two-part mount.
- **Limits (data):**
  - yaw: unlimited, 70°/s;
  - pitch: −15° to +40°, 50°/s;
  - a moderate spring;
  - recoil kick 0.8°.
- **Weapon:** twin barrels, alternating ("staggered", as the alpha default); cadence 12 rounds/s total; heat lockout.
- **Enter / exit:** look at the emplacement within 3 m and press the Pilot key, or use the terminal. The same key exits. V stays beside it, locked, like using a vanilla turret.
- **View:** the sight camera on the pitch part, just behind the guns; V toggles the chase view.
- **HUD:** reticle, gun pips, heat per barrel, traverse indicator (yaw relative to base), range.

**Test milestones (rev 3)**

Each milestone is a small build, or a short series of builds, that Omar checks in game:

| # | Build | Omar checks |
|---|---|---|
| M1 | The framework core (`ControllableMechs.Control`) with the Minotaur: session, input, sight and chase views, HUD, heat, look-at aim (section 11), V-credited fire. It replaces the alpha's Pilot Mode once it passes. | Enter/exit restores everything; the guns follow the reticle while walking and turning; rounds, tracers and flash come from the barrels and land on the reticle; damage lands and is credited to V. |
| M2 | The emplacement through the vanilla turret takeover: spawn the Arasaka floor HMG or Security 1 from the terminal, enter with the Pilot key, V visible. | Spawn, enter, fire, damage, exit; V back to normal. |
| M3 | A feel pass on both: traverse weight, camera, sounds, HUD readability. | Feel. |

---

## 11. The Minotaur on the framework (`CMUMinotaur`), now M1

**Rev 3: route (B) won.** Look-at events on **RightWeapon + LeftWeapon + Weapon + Chassis** at a target that moves with the reticle turn the mech's real MK.31s onto it (S6: 45° → under 1° in 1.5 s; S7: mostly 0-5° while piloting). So:
- **No skin on the Minotaur.** Its own guns stay visible and aim through its own animation; route (A) failed to attach anything (S5/S5b) and isn't needed.
- **Aim:** the session moves one marker entity to the aim point every frame; the four look-ats follow it. Each gun fires only while its barrel is within a few degrees of the reticle (S7 gate), so the rounds leave along the barrel you see and land on the reticle.
- **Fire and damage:** `AIWeapon.Fire` on the mech's weapon items. The mech as owner deals damage (proven). V-credited damage uses the call a V-controlled vanilla turret makes (`AIWeapon.Fire(player, weapon, simTime, 1.0, triggerMode)`); which V variant works is being settled by the S7 retest (section 14).
- **Driving:** unchanged from the alpha (AI walk orders with clipped targets).

The original two-route plan, kept for reference:

- **(A) Our own guns, spike S5:**
  - Hide the skinned MK.31 meshes on the live mech (`FindComponentByName(n"mch_003__minotaur_weapons_l_01" / "_r_01")` + `Toggle(false)`) **[decl]**.
  - Attach two HMG mesh components to the mech body, bound to its `l/r_weapon_jnt` (or `upper_body_01`) through `parentTransform`, and turn them with `SetLocalOrientation` within their own yaw/pitch limits (S4/S5). They then ride the walk animation natively. The fallback is part entities placed every frame at the shoulder transforms, which will likely trail the animated pose.
  - The rounds, tracers and flash then come from our guns, exactly like the emplacement.
  - The mech's legs keep using AI move orders (walking already works).
- **(B) The mech's own arms, spike S6:** look-at requests with the anim graph's real part names (**LeftWeapon / RightWeapon / Weapon / Chassis**; the alpha tried the hands and chest) or arm IK (`ikLeftArm` / `ikRightArm`). If the arms follow, the framework reads the barrel transform off the `l/r_weapon_jnt` bones' effect.
- **Driving:** stays as in the alpha (AI walk orders, with obstacle-clipped targets) until something better is found. The framework's aim and camera replace the alpha's rig.

(A) uses only the building blocks the emplacement proves, so it's the likely path.

---

## 12. Spikes: small test builds that settle the unknowns

| # | Question | Test build | Decides |
|---|---|---|---|
| S0 | Does a spawned vanilla security turret accept the game's own takeover (the quickhack route: `TakeOverControlSystem` / the turret's take-control action)? | Spawn a turret, friendly it, request takeover from the dev page. The log reports each step. | Whether the emplacement is nearly free (section 10) |
| S1 | Can we spawn a single mesh as a movable entity? | Spawn an empty entity and `AddComponent(entMeshComponent)` with the MaxTac gun mesh at build time; also try spawning the whole MaxTac `.ent`. Move each with `SetWorldTransform`. | How parts are built (section 6) |
| S2 | Which firing route deals damage from our muzzle? | Three buttons: projectile launch event on a spawned HMG item; `AIWeapon.Fire` from a spawned item; hitscan + damage. The log records what hit and what damage landed. | The weapon backend (section 7) |
| S3 | Which vanilla effects make a good HMG flash and tracer? | Cycle 3-4 candidate `.effect` paths from WolvenKit at a test muzzle. | The effect resources |
| S4 | Does a component parented to another component follow `SetLocalOrientation`? | One entity, two mesh components, rotate one. | An optional one-entity unit route |
| S5 | Do the Minotaur's gun meshes hide with `Toggle(false)`? | Toggle on a linked mech. | Minotaur route A |
| S6 | Do LeftWeapon/RightWeapon look-ats or arm IK move the Minotaur's arms? | A look-at on each part name toward a marker. | Minotaur route B |

**The first batch is S0, S1, S2, S4 and S5**, all before M1. S4 and S5 decide how skins attach to an animated body, which is the end goal for mechs, so they're learned first. S3 (effect picks) and S6 (arm look-ats) follow. Each spike is a dev-only terminal page (TOOLS-style), compile-checked against the full load order and pushed like any build. Each asks Omar one clear question.

---

## 13. Decisions (Omar, 2026-09-30)

1. **Enter an emplacement:** the Pilot key while looking at it, **and** from the terminal. **V stays visible** beside it.
2. **Damage model:** **real bullets** (projectiles), with V as the instigator.
3. **Ammo:** **heat only**.
4. **Chase view:** **kept** for emplacements too.
5. **The alpha's Pilot Mode:** **kept** until M5, when the framework's Minotaur replaces it. *(Rev 3: until M1 passes, since the Minotaur is now M1.)*
6. **Rev 3 plan (2026-09-30, after the batch 2 review):** the S0 takeover makes the emplacement nearly free, so the effort goes to the Minotaur. M1 = Minotaur on the framework, M2 = emplacement via takeover, M3 = feel pass.

---

## 14. Spike results (batches 1-3, 2026-09-30)

Logs: `overwrite\bin\x64\plugins\cyber_engine_tweaks\gamelog.log` (tag `CM-SPIKE`).

| # | Result | Decides |
|---|---|---|
| S0 | Passed. Security turret 1 spawned, befriended and taken over by both routes (the Take Control action queued on it, and `TakeOverControlSystem.RequestTakeControl`). Aim, fire, barrel/flash/rounds line up; Esc exits. | Emplacement via takeover (M2) |
| S0b | Security 1, the Arasaka floor turret (the Minotaur's HMG, real damage, NPCs react) and the car-mounted turret work fully. Security 2 has no gun and a fixed view; the big turret is invisible and deals no damage; the vehicle turret's view can't move. After exit, V's camera and restrictions are back to normal. | M2 body: Arasaka floor or Security 1 |
| S1 | Passed. The MaxTac turret entity and a lone HMG mesh on a host entity spawn and spin smoothly (per-frame `SetWorldTransform`). | Part entities work (fallback skins) |
| S2 / S2b | No route fired by script with V as the owner dealt damage: the weapon's player or NPC attack record, and a V-instigated area hit from a TweakXL attack record (loaded, but never applied). Mech-owned rounds can hurt (one burst: 29 damage). | V-credited damage needed another route |
| S2c / S7 | The vanilla turret call. The log and the report disagree: the one kill logged under "V + target point", while "V, no point" in S7 gave slow rounds that vanish after about a foot. The S7 retest (build 3be8ac5, three selectable calls, each logged) settles it. | M1 fire call |
| S4 | Passed. A mesh component bound to another rotates on its own with `SetLocalOrientation`. | Component skins on static bodies |
| S5 / S5b | The MK.31 meshes hide and show with `Toggle`. No HMG attached to the Minotaur ever showed: `Entity/Assemble` with a record filter never fired for the spawned mech, and no slot component resolves `r_weapon_jnt`. | Route (A) dropped |
| S6 | All four look-ats (RightWeapon, LeftWeapon, Weapon, Chassis) together brought both guns to the target (45° → 0.6°). RightWeapon alone and Chassis alone help; Weapon alone and arm IK (`ikRightArm`/`ikLeftArm`) do nothing. | Route (B): the Minotaur's own guns aim |
| S7 | Piloting with the four look-ats on the moving aim marker: aim error mostly 0-5°, "a bit off but far far improved"; spikes of 40-100° while turning hard. Mech-owned rounds deal damage. Build 3be8ac5 adds the 4° fire gate. | M1 aim |
