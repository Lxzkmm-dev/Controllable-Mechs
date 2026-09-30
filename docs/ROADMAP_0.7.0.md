# Mechs of Night City 0.7.0: roadmap and design

Status: draft for Omar's review (2026-09-30). Nothing below is built yet. Items marked **[spike]** are unknowns that a small test build settles before anything depends on them. Items marked **[decide]** need Omar's call.

## 1. Scope (Omar, 2026-09-30)

1. **Other Minotaur variants**, functionally the same, and smooth. An Arasaka Minotaur crashed the game after all its limbs were destroyed and it was piloted.
2. **Drone gameplay**:
   - aerial Bombus FPV drones;
   - combat drones.
   Both need simulated aerial physics and the wireframe localized damage model.
3. **Persistent damage.**
4. **Repairs.**

## 2. Phase 0: stability first

### What is known about the crash

- There are two crash dumps from 2026-09-30, at 17:12 and 17:44. Both are null reads (`EXCEPTION_ACCESS_VIOLATION` at 0x0) inside `Cyberpunk2077.exe`, at two different addresses (+0x1421e2 and +0xea950d). Neither is in a plugin DLL.
- **17:44:** the crash follows a disconnect by about a second. The last game log line is cut off mid-write.
- **17:12:** the crash was mid-fight, walking and firing.
- The part-damage lines only log with DIAGNOSTICS on, so the logs don't show which parts were broken.

### Suspects: new in 0.6.0, and touching engine objects in unusual ways

- Effects spawned and attached to slots (`FxSystem.SpawnEffect` + `AttachToSlot`) that outlive the thing they are attached to. Nothing kills them on disconnect, unlink or despawn. They are only killed on restore.
- Effect events sent to a weak spot after `ScriptedWeakspotObject.Kill` (the stage effects, `GunStage`).
- A variant missing a slot (`Chest`, `WeakspotLeft/Right`), a mesh component (`mch_003__minotaur_weapons_l_01`) or a named effect that the code assumes exists.
- HUD animations still running on part layers when the HUD is removed (the blink on break, the static bursts).

### Fixes (built before anything else)

- **FX lifetime:**
  - Every spawned effect is registered with its unit.
  - All are killed on disconnect, unlink, test despawn and the unit's death.
  - Re-attached on the next link if the part is still broken.
- **Dead weak spots:** a destroyed weak spot is never sent another event. The kill is recorded per side.
- **Variant profile checks:** at link time, each slot, component and effect the code uses is checked on that entity. Anything missing is skipped and logged, never called.
- **HUD:** stop all part-layer animations before the HUD is removed.
- **Breadcrumbs:** with DIAGNOSTICS on, a log line is written before each risky engine call ("fx attach Chest", "weakspot kill L", "effect start explode_death"). The next crash then names its last step.
- **Repro:** Omar's exact steps on the Arasaka mech (which one, how spawned, how broken, when it died), rerun with DIAGNOSTICS on.

## 3. Minotaur variants

### What exists in the game files

- `base\mechanical\mech\mch_003__minotaur.ent` has four appearances: militech_01, arasaka_01, police_01 and kurt. It is one body with different paint and parts, so the schematic, slots and weak spots are shared.
- `mch_004_arasaka.ent` and `mch_005__militech.ent` / `mch_005__militech_exo.ent` are separate templates. **[spike]** Are they Minotaur bodies with their own meshes, or different machines? Export and compare the rigs, slots, weak spots and weapon items.
- `mch_002__centaur` is the Centaur exo. It is out of scope for 0.7.0 unless Omar wants it.

### Design

- **A variant profile per template.** It records:
  - the gun mesh components;
  - the slots used for effects;
  - which named effects exist;
  - the weapon items;
  - the schematic atlas to show.
- **Variants on the Minotaur body** reuse its profile.
- **Distinct templates** get their own profile and, if their meshes differ, their own schematic, built by `tools/schematic` from their meshes.
- **Name and faction on the HUD** come from the variant ("ARASAKA MINOTAUR"), not a fixed string.
- **Test spawn:** MOTOR POOL can spawn each variant.

## 4. Drone gameplay

### What exists

- **The drones are AV-class puppets:**
  - `av_zetatech_bombus__basic`
  - `av_militech_griffin__basic_01`
  - `av_militech_wyvern__basic_01`
  - `av_zetatech_octant__basic_01`
  - Each has its own animation sets (idle, walk, jog and sprint flight blends).
- **Weapons:** `bombus_torch`, `griffin_rifle`, `wyvern_rifle` and `octant_autocannon`.
- **Damage and destruction effects are already made:**
  - bombus: damage smoke, destruction, hit, EMP, overload, taser and welder;
  - octant: damage smoke and sparks, thrusters, thruster break, explosion, engine explosion and fire;
  - griffin: destruction.

### Control model

- **Bombus FPV:**
  - **Camera:** first-person nose camera with roll. Throttle and attitude map to the keys and mouse (acro-lite):
    - W/S pitch forward/back;
    - A/D roll;
    - the mouse yaws and tilts the camera;
    - Space/Ctrl climb/descend.
  - **Weapon:** the torch/taser on LMB.
  - **[decide]** An optional kamikaze overload on G (the `bombus_hack_overload` effect plus an explosion).
- **Combat drones (Griffin, Wyvern, Octant):**
  - **Camera:** chase camera or gun camera, reusing the Minotaur's rig.
  - **Keys:** WASD strafe on the horizontal plane, Space/Ctrl altitude, the mouse aims and yaws.
  - **Weapons:** fired with `AIWeapon.Fire`, as for the MK.31s, with the same fire gate and V credit.

### Aerial physics (simulated by the mod)

- **Per frame, only while piloting:**
  - velocity integration with mass;
  - thrust toward the input direction;
  - hover thrust against gravity;
  - linear and angular drag;
  - a top speed per type;
  - the body tilts with acceleration (bank into turns, nose down to accelerate).
- **Collision:**
  - ray and sphere checks along the step, as the Minotaur's wall and ledge checks do;
  - bounce and scrape on contact, with damage above an impact speed;
  - the ground cushions the landing.
- **Moving the drone:** **[spike S1]** how to move a flying puppet every frame. The candidates:
  - `TeleportationFacility.Teleport`: it did not move the Minotaur, but drones are a different class;
  - `AITeleportCommand` per frame;
  - an `AIMoveToCommand` carrot a short way ahead, with the physics only deciding where the carrot goes.
  - We pick whichever gives smooth motion at 60 fps and keeps the drone's own animation.
- **Thrust cut-off:**
  - When a rotor or thruster breaks, thrust on that side drops.
  - The drone yaws and drifts toward the broken side, needs countering, and loses its ceiling.
  - With all thrust gone it falls.

### Localized damage

- **Parts per drone** (from their meshes, [spike S2]):
  - body;
  - sensor/camera;
  - the rotor or thruster pods (two or four);
  - the weapon.
- **Breaking them:**
  - broken thrusters cut thrust (above);
  - a broken weapon goes offline;
  - a broken sensor loses the optics, as on the Minotaur.
- **HUD:** the same wireframe schematic pipeline (`tools/schematic`), one atlas per drone type, shown in the same place.
- **Effects:** the drones' own damage smoke and sparks at the part, and their destruction effect at 0.

## 5. Persistent damage

- **Now:** part damage lives only for the game session (`CMCParts`, keyed by EntityID).
- **Persistence needs an identity that survives a save:**
  - **World units** that the game itself saves (quest or placed NPCs) keep their EntityID. Their state can be kept in a persistent scriptable system.
  - **Units the mod spawns** (the test mech, future owned units) are not saved by the game. They need an **owned unit** record, a mod-side save entry (template, appearance, part damage, hull, where it was left), re-spawned from that record on load.
- **[decide]** Is 0.7.0 persistence for:
  - (a) owned units only, one owned mech and one owned drone, which brings in the "own a mech" feature from the earlier list; or
  - (b) any linked unit, best effort, lost when the game unloads it?

## 6. Repairs

- **Repair restores:**
  - the part integrity and the hull;
  - the guns re-shown (a destroyed vanilla weak spot can't be revived, so re-linking a fresh unit may be needed for its look);
  - effects stopped.
- **[decide]** Where and how:
  - (a) a repair action in the terminal, costing eddies, parts or time;
  - (b) a repair kit item (TweakXL is needed for a new item; otherwise a vanilla consumable is reused);
  - (c) a place: the planned carrier truck, a Militech terminal, or V's garage.
- **Partial repairs** (field patch-ups to 50%) versus full repairs at a place.

## 7. Performance and stability budget

- **Drones:** the physics and collision checks run per frame only while piloting a drone, with a fixed number of rays per frame.
- **Idle cost:** nothing runs for units that are not linked.
- **Effects:** started on events only.
- **Crash gate:** every new engine call is guarded by the profile checks and logged under DIAGNOSTICS.

## 8. Build order

1. **Phase 0 (stability):** FX lifetime, dead weak spots, profile checks, HUD animation cleanup and breadcrumbs, then Omar's Arasaka repro.
2. **Minotaur variants:** profiles, the template spike, MOTOR POOL spawns for each variant, and the variant name on the HUD.
3. **Drone spikes (S1, S2):**
   - movement method;
   - part and mesh layout for each type;
   - a first drone flying with the physics and no weapons.
4. **Bombus FPV:**
   - the FPV camera, physics tuning and weapon;
   - schematic and damage.
5. **Combat drones:** the Griffin, Wyvern and Octant on the same code, each with its weapon, schematic and damage.
6. **Persistence** (per Omar's decision).
7. **Repairs** (per Omar's decision).

## 9. Open questions for Omar

1. The Arasaka crash repro: which mech, how it was spawned, how the limbs were broken, and when the game died.
2. Bombus FPV: the full acro control scheme (roll with A/D), or a stabilized "angle mode"? And a kamikaze overload: yes or no?
3. Persistence: (a) owned units or (b) any linked unit?
4. Repairs: where and what cost (section 6)?
5. Are `mch_004_arasaka` / `mch_005__militech` in scope if they turn out to be different machines?
