# Drone float analysis (0.7.0, builds a21–a30)

> **Correction after Omar's a28 test (2026-10-01).** The float had **two** independent causes. This doc first blamed only the second one, and that was wrong:
>
> 1. **The hover animation really does lift the drawn body.** The Bombus body bone sits 1.68 m above the entity origin. It is read correctly through the skeleton-bound `Item_Attachment_Slot/Center`.
>    - a28 lowered the origin by that amount, and the model sat right ("it works").
>    - a28 also anchored the cameras to the entity origin, so first person went 1.7 m under the road.
>    - a29 dropped the lift, which was wrong.
>    - **a30** keeps the lift for the entity and anchors both cameras (sight view and chase pivot) to the body's rest-pose origin, `Anchor()`.
> 2. **The sweep radius** (below) held the centre a radius up. Fixed in a29 and kept in a30.
>
> The `fx_slots` (a23–a26) and `Slot88444` readings remain as described in §3. Only the bound `Item_Attachment_Slot/Center` is trustworthy. Slot88444 gave the same 1.68 m and was dismissed wrongly in §3: its reading was correct.

**Symptom (Omar, all drone types):** at rest and level, the third-person model floats a hand's width (about 0.3 m) above the road, while the first-person view sits on the asphalt.

**Verdict:** the float came from the collision sweep, not from the model, the camera or the animation. Build a29 fixes it.

## 1. The pipeline, layer by layer

How a drone ends up on screen. "Verified" means checked against the log, WolvenKit or the clip.

| # | Layer | What it does | Status |
|---|-------|--------------|--------|
| 1 | Flight physics (`CMFlight`) | Integrates the centre of mass (`pos`), the velocity and the attitude quaternion. | Verified offline (`tools/flight/sixdof.py`). |
| 2 | Collision (`CMUDrone.Collide`, `PushOut`) | Keeps `pos` out of the world: the swept step along the motion, then the ground ray, then the horizontal push-out. | **This is the bug (see §2).** |
| 3 | Origin placement (`Root()`) | Origin = `pos` − body-up × `com`. | Verified. `com` and `bottom` match each mesh's real bounds (WolvenKit glTF export, §4). |
| 4 | Entity transform | `SetWorldTransform` every frame. | Verified: log "off by 0 m avg / 0 m max". |
| 5 | Animation | The `drone_humanoid` graph poses the skeleton; the meshes are skinned to `base`. | Readings unreliable (§3). Not needed for the fix. |
| 6 | Camera (`CMPilotRig`) | Sight view = origin + 0.1 m up, 0.35 m forward; chase is set per profile. | Verified: `simple_free_camera.ent`'s camera component has no local offset (WolvenKit). |

## 2. Root cause: the sweep used the radius in every direction

`Collide` swept each step from the old position to the new one, extended by `p.radius`. On a hit it put the centre at `hit − dir × radius`.

That treats every drone as a sphere of its *horizontal* radius. Moving down onto the road, the centre stopped a full radius above it. The belly is much closer to the centre than that:

| Drone | radius | belly below centre (`bottom`) | float |
|-------|--------|-------------------------------|-------|
| Bombus | 0.30 | 0.134 | **0.17 m** |
| Wyvern | 0.50 | 0.227 | **0.27 m** |
| Octant | 1.10 | 0.91 | **0.19 m** |
| Griffin | 0.50 | 0.474 | 0.03 m |

This matches Omar's "about 0.3 m, every drone".

**Proof in the a27 log (22:05:38–53, Bombus at rest, level):**
- Every second it reports "0.3 m up" and "ground 1.30 m below the ray start", so the centre is 0.30 m above the surface.
- Every second it also logs "touched the ground, base 0.02 m above the surface". That is the ground contact pulling the centre down to 0.134 + 0.02 m.
- The two collision rules were fighting. The ground contact used the real lowest point; the sweep pushed back up to a radius. The result was a constant flicker between them.

**Why first person looked fine:** the sight camera rides at the centre (origin + 0.1). Hovering 0.30 m up, the eye was about 0.27 m off the road, which looks like "on the asphalt" with a wide field of view. The model's belly at 0.17 m up looked like what it was: floating.

**Fix (a29):** the sweep reaches the body's real extent along the motion, using an ellipsoid:
- the radius sideways;
- the lowest-point reach at the real attitude (`bottom·|up.z| + span·sin(tilt)`) up and down.

The sweep and the ground contact now agree, so a landed drone rests with its belly on the road. The log's new "above the road" field gives the eye, body centre and body bottom heights.

## 3. Why builds a23–a28 chased the wrong thing

**a23–a26.** I assumed the hover animation lifted the body. I measured the lift through `fx_slots`, but the Bombus entity shows `fx_slots` has no `parentTransform`: it is not bound to the skeleton and reports the entity origin. Its "lift" of −0.13 m raised the drawn body by 0.13 m.

**a27.** The read moved to `Slot88444`, which is bound to the `root` animated component. It reported the body bone 1.67 m above the centre. That is the vanilla drone hover height:
- the appearance (`zetatech_bombus__basic.app`) puts its diode light 1.85 m above the origin;
- but the clip shows the body near the road, not 1.8 m up.

So that skeleton pose is not what the visible meshes follow while we drive the entity transform, or the slot is evaluated differently.

**a28** applied that reading and would have sunk the Bombus about 1.7 m. It was superseded by a29 before it was tested.

**Lesson:** slot readings on these NPCs don't reliably describe the drawn mesh. The fix didn't need them; it needed the collision to use the measured mesh size, which was already right.

## 4. Evidence used

**Logs.** `gamelog.log` per-second drone lines: build stamp, height above the ground ray, touch events, the slot readings.

**WolvenKit.**
- Entities: `av_zetatech_bombus__basic.ent`, `av_militech_griffin__basic_01.ent`, `av_militech_wyvern__basic_01.ent`, `av_zetatech_octant.ent`. These gave the slot components and what each is bound to.
- Appearance `zetatech_bombus__basic.app`: the skinned meshes and the diode light at 1.85 m.
- Rigs: base-bone rest heights. Bombus 0.127, Griffin 0, Wyvern 0, Octant 0.77.
- Meshes exported to glTF: the bounds in bind space. These match the profile `com` and `bottom`.
- `simple_free_camera.ent`: no camera offset.

**Clip frames (ffmpeg).**
- Chase versus sight view, sized against the Bombus's real 0.51 m width.
- The first-person eye was about 0.25 m up; the curb top showed just below the horizon.

## 5. Solutions, in order of preference

1. **(Done, a29) Correct collision extent.** The sweep uses the body's ellipsoid, so the physics and the drawn model agree for every type. This is the minimal, principled fix.
2. **Mesh contact points (planned).** Replace the ellipsoid with 8–12 points taken from each mesh: rotor and wing tips, nose, tail, belly and gun.
   - The body then rests on whatever part touches, so it can't tip nose-first into the road.
   - Off-centre hits torque it correctly.
   - The same points drive per-rotor damage.
3. **Sight camera on the sensor.** Mount the first-person eye at each drone's real camera location from its mesh, instead of 0.1 m above the centre, so both views share one reference.
4. **If a residual visual offset ever remains:** don't infer it from slots.
   - Calibrate once per type with a visible marker, an effect spawned at the physics centre and at the ground hit, and read the gap off a clip.
   - Or replace the NPC's visuals while piloting with our own static-mesh entity that uses the same `.mesh` files. That takes the animation graph out of the picture entirely.
