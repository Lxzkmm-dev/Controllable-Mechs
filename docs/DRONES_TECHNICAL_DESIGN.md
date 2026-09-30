# Mechs of Night City: drones technical design (0.7.0)

Status: agreed (2026-09-30). Nothing is built yet.

Omar's decisions:

- **Bombus control:** angle mode by default, acro as a setting.
- **Kamikaze overload on G:** yes.
- **Left open to keep the focus narrow:** the schematic view for quads and crash loss. The defaults are a front view, and a crashed drone is lost until respawned.
- **Range:** the mech's 250 m uplink. **[spike]** marks an unknown that a small test build settles first. **[decide]** marks a call for Omar.

## 1. Goals (Omar)

- Pilot **aerial drones**:
  - the **Bombus as an FPV drone**;
  - the **combat drones** (Griffin, Wyvern, Octant).
- A real **physics model** for flight, not scripted movement.
- The **wireframe localized damage model** the Minotaur has: parts, the HUD schematic and effects.
- Built on the control framework, with the Minotaur's standards: nothing runs unless piloting, stable, performant.

## 2. What the game gives us

- **Templates:**
  - `base\vehicles\special\av_zetatech_bombus__basic.ent`
  - `av_militech_griffin__basic_01.ent`
  - `av_militech_wyvern__basic_01.ent`
  - `av_zetatech_octant__basic_01.ent`
  - Each has its own animation sets (idle, walk, jog and sprint flight blends, and turn transitions).
- **Weapons:** `base\weapons\drone\bombus_torch.ent`, `griffin_rifle.ent`, `wyvern_rifle.ent` and `octant_autocannon.ent`.
- **Effects already made** (`base\fx\vehicles\drone\`):
  - bombus: damage smoke, destruction, hit, EMP, overload, taser, welder flame and beam;
  - octant: damage smoke and sparks, thrusters, thruster break, explosion, engine explosion, fire after explosion and EMP;
  - griffin: destruction and after-explosion.
- **In game** these are NPC puppets (the Drone NPC type), driven by the AI's flight movement. They are not vehicles with a rigid body. **[spike S0]** Confirm from the records (`Character.*Drone*` entity templates) and one linked drone's class.

## 3. What we learn from Drive an Aerial Vehicle (DAV)

Omar has the author's permission for analysis. No code is taken; these are the ideas worth reusing, restated for our case.

### How DAV flies

- **It moves real vehicle physics.** A native RED4ext plugin (`FlyAVSystem`) adds force and torque, or sets the linear and angular velocity, on the AV's rigid body every frame. It turns gravity and the vanilla vehicle physics on and off. **We can't do this:** our drones are puppets, not rigid bodies, and we don't ship native code.
- **Two flight models:**
  - **AV mode:** thrust along the body's forward vector, a separate vertical acceleration, and yaw, roll and pitch commands.
  - **Helicopter mode:** lift along the body's **up** vector. Tilting the body is what makes it move sideways or forward. This is the quadcopter model, and the one we want.
- **Self-levelling:**
  - Each frame, roll and pitch get a correction back toward level, limited to a "restore amount" per frame.
  - There is a hard cap (30 degrees), and a forced reset beyond 70 degrees.
  - The command to tilt fades as the tilt approaches the cap (`(max - current) / max`), so it eases into the limit instead of hitting it.
- **Drag:** linear air resistance on velocity, with separate horizontal and vertical constants (vertical is stiffer).
- **Top speed:** once over the limit, thrust is dropped for that frame, rather than clamping the velocity.
- **Spool-up:** a rotor "RPM" counter rises while thrusting and decays otherwise. It gives thrust a lag, and the engine sound follows it.
- **Hover hold at idle:** a damped spring toward a target height above ground (height gain 0.5, velocity damping 0.2).
- **Orientation math:** euler angles are turned into rotation matrices to convert local roll/pitch commands into world angular rates.
- **Collision:** a precomputed obstacle and height grid of the whole map, shipped as data, plus the vehicle's own physics collision.

### What we take (the ideas, re-implemented in redscript)

- The helicopter lift-along-up model with tilt-to-move.
- Self-levelling with an eased cap, and a hard safety reset.
- Separate horizontal and vertical drag.
- Thrust spool lag.
- The PD hover hold.

### What we don't take

- The native plugin (and so real rigid-body forces).
- The map grid (tens of MB of data; our drones are small and fly low, so live ray checks are enough).
- The Lua/CET structure.

## 4. Architecture

- **`CMUDrone`**, a new `CMCUnit` like `CMUMinotaur`. It has the same session hooks (Begin, Tick, Hud, TakeHit, End), AI suppression (`Pacify`, the `m_cmPiloted` flag and the threat wraps), V credit and aggro.
- **`CMDroneProfile`**, one per drone type (Bombus, Griffin, Wyvern, Octant). It holds:
  - mass;
  - rotor or thruster layout (count and positions);
  - maximum thrust, top speed and drag constants;
  - tilt limits, and yaw and tilt rates;
  - camera mounts (FPV nose and chase);
  - weapon items;
  - parts and hit zones;
  - the schematic atlas;
  - the effect names.
- **`CMFlight`**: the flight model. It is pure maths on a small state struct, has no engine calls, and can be unit-tested with a probe.
- **`CMFlightBody`**: applies the flight state to the puppet (S1), and runs the collision checks.
- **Shared with the Minotaur:**
  - the pilot camera rig (chase view);
  - input;
  - the HUD shell;
  - part damage (`CMCParts`, generalised to a per-type part list);
  - `tools/schematic`, run on each drone's meshes.

## 5. Flight model (`CMFlight`)

### State

- position `p`;
- velocity `v`;
- orientation (yaw, pitch, roll);
- body rates;
- per-rotor spool `s[i]` (0..1);
- per-rotor efficiency `e[i]` (0..1, from damage).

### Forces, each substep (dt no more than 1/120 s; a frame runs 1 to 4 substeps)

- **Thrust:** `T = sum(maxThrust_i * s[i] * e[i])`, along body up.
  - Asymmetric thrust also gives a torque, `sum(r_i x T_i)`. This is what makes a damaged drone roll and yaw by itself.
- **Gravity:** `-g * mass` on Z.
- **Drag:**
  - linear and quadratic;
  - separate horizontal (`kh`) and vertical (`kv`) coefficients;
  - a small angular damping on the body rates.
- **Ground effect:** below about one rotor diameter above ground, thrust is multiplied by up to 1.15, a soft cushion for landing.

### Spool

`s[i]` moves toward its command with a time constant of 0.08 s (Bombus) to 0.15 s (Octant). That gives weight to the throttle and to recoveries.

### Control modes

**Angle mode** (the default; all drones):
- The keys set a target pitch and roll, up to the profile's tilt limit (about 30 degrees for the Bombus, about 20 for combat drones).
- The command is eased near the limit, as in DAV.
- The keys:
  - WASD: move;
  - Space/Ctrl: climb/descend, as a target vertical speed with hover thrust fed forward;
  - the mouse: yaw rate and camera or gun pitch.
- A PD controller turns the angle error into rotor differentials.
- **Keys released:** it levels, and a damped spring holds the current altitude (the PD hover hold).
- **Rotor damage:** the controller spends thrust margin to compensate. Past the margin the drone drifts, spins and sinks. That is "localized damage you can feel".

**Acro mode** (Bombus FPV, **[decide]**):
- W/S and A/D set pitch and roll **rates**, and the mouse sets the yaw rate.
- Throttle is direct collective, with no self-levelling. It keeps the hard safety reset beyond 70 degrees only as an option.
- This is the real FPV feel: much harder, and much more skill expressive.

**Assist for combat drones:**
- The gun is on the mouse, and the body yaws to follow the gun, like the Minotaur chassis.
- Strafing is a tilt, so a hard stop is a visible flare-back.

### Limits and feel

- **Top speed:** thrust is cut when over the limit (DAV's approach), so a drone can still fall or be pushed past it.
- **Suggested numbers** (tuned in game):
  - Bombus: top speed 18 m/s, tilt 35 degrees;
  - Griffin/Wyvern: 14 m/s;
  - Octant: 10 m/s.

## 6. Moving the puppet (`CMFlightBody`)

### [spike S1] How to put a flying puppet at our position every frame

Ranked by what the Minotaur taught us:

1. `TeleportationFacility.Teleport(puppet, p, rotation)` every frame. It didn't move the Minotaur, but drones use a different movement component and may honour it. Smooth if it lands every frame.
2. `AITeleportCommand` every frame (it moved the Minotaur). Cost and smoothness are unknown at 60 Hz.
3. **Carrot steering:** an `AIMoveToCommand` fly order to a point our physics picks a short way ahead, re-sent as the Minotaur's walk orders are. Our simulated state drives the target, and the AI's own flight does the moving. It's smoothest, but the least exact.

- **Decision:** the first option that lands each frame within 5 cm at 60 fps in the spike wins.
- **Visual tilt:** **[spike S2]** can pitch and roll be set on a puppet through the teleport's full quaternion? If only yaw is honoured, the tilt comes from the drones' own flight animation lean (their walk, jog and sprint blends with direction), driven by our velocity. The camera shows the true tilt either way.

### Collision

Collision checks run each frame, only while piloting:
- **Rays per frame:** a sphere-ish sweep from 4 rays, along the move and at the four body corners, against the "World Static" and "Static" presets (the Minotaur's ground lessons), plus one ray down for the height above ground.
- **On contact:**
  - the velocity's normal component is removed and bounced with restitution 0.2 to 0.35;
  - the drone slides along the surface;
  - above an impact speed (for example 6 m/s for the Bombus), the hit damages the part on that side and the body, scaled with speed squared.
- **Landing:** below 1.5 m/s the drone settles and the rotors idle.
- **Budget:** at most 6 ray casts per frame while flying.

## 7. Cameras

- **Bombus FPV:**
  - a camera entity at the nose mount, with the drone's full orientation **including roll**;
  - a wide FOV (95 to 105);
  - a slight camera uptilt setting (0 to 30 degrees, as real FPV pilots use);
  - a tiny latency and rotor vibration (the shake from the Minotaur's recoil work, scaled with rotor spool).
- **Combat drones:** the chase rig (distance, height and offset settings, and the wall pull-in), plus a gun camera option.
- **Operator range:** the Minotaur's uplink rules (250 m signal, with the signal bar).

## 8. Weapons

- **Fired like the MK.31s:** `AIWeapon.Fire` from the drone's own weapon object, with V credit, the fire gate and the own-target ray.
- **Bombus:** the torch/taser on LMB (short range, a beam effect).
  - **[decide]** An optional kamikaze overload on G: the `bombus_hack_overload` effect, then an explosion, and the drone is lost.
- **Griffin / Wyvern:** a rifle on LMB.
- **Octant:** the autocannon on LMB, with heat.
- **Recoil:** a small impulse into the flight model (not just the camera), so firing pushes a light drone.

## 9. Localized damage and the schematic

- **Parts per type** (final list from the meshes in spike S3):
  - Bombus: body, sensor, 4 rotors, torch;
  - Griffin / Wyvern: body, sensor, 2 to 4 thrusters, rifle;
  - Octant: body, sensor, 4 thruster pods, autocannon.
- **Hit mapping:** as the Minotaur's. The game's hit zone first. Otherwise the nearest part, from the hit position in the drone's frame, measured on its meshes.
- **Effects of damage:**
  - A rotor or thruster's efficiency `e[i]` falls with its integrity. At 0 its thrust is gone (flight model, section 5).
  - The weapon goes offline at 0.
  - The sensor at 0 costs the optics and HUD data, as on the Minotaur.
  - The body is the hull.
- **Schematic:**
  - `tools/schematic` renders each type's meshes into a wireframe atlas: a top-down view for quads (it shows every rotor), front for the rest (**[decide]**).
  - Tinted and greyed out as on the Minotaur, and flashed on hit.
- **Effects:** the types' own damage smoke and sparks at a part, thruster break on a lost thruster, and destruction at 0. These attach through the FX system the Minotaur work proved (Codeware `ResourceAsyncRef.SetPath` plus `AttachToSlot`), with the phase-0 lifetime rules.

## 10. HUD

The drone HUD reuses the shell:
- an artificial horizon (pitch ladder with roll);
- altitude above ground and vertical speed;
- throttle and rotor spool;
- speed;
- signal;
- the weapon state;
- the part schematic.
- **The Bombus FPV HUD** is sparse: horizon, altitude, speed and signal only.

## 11. Stability and performance

- **Nothing runs** unless a drone is piloted.
- **Per frame while flying:** the flight maths (tens of float operations per substep), at most 6 ray casts, and one move call (S1). No allocations in the loop.
- **Phase-0 rules apply:**
  - every attached effect is killed on disconnect, unlink or death;
  - slot and effect checks per profile;
  - HUD animations are stopped before removal;
  - breadcrumbs under DIAGNOSTICS.
- **Guards:**
  - the drone's AI is suppressed as the Minotaur's is (threats, alerts and states refused);
  - ground checks at link and unlink, so a released drone isn't left stuck in the air (**[spike]**: does its own AI resume flight?).

## 12. Build order

1. **S0/S1/S2 spikes:** link a drone, find its class, the move method and whether tilt can be set. One test session.
2. **`CMFlight`:** the maths, with a probe test; the angle mode first.
3. **Bombus FPV flying:** camera, collision, hover and landing.
4. **Damage:** rotor efficiency in the flight model, parts and hits, schematic (spike S3 for the meshes), and effects.
5. **Bombus weapon** (and overload, if wanted); acro mode (if wanted).
6. **Combat drones:** Griffin, Wyvern and Octant profiles, chase and gun camera, and weapons.
7. **MOTOR POOL:** spawn each drone for testing.

## 13. Open questions for Omar

1. **Bombus control:** angle mode only, acro only, or both (a setting)?
2. **Bombus kamikaze overload on G:** yes or no?
3. **Schematic view** for the quad drones: top-down (shows all rotors) or front, like the Minotaur?
4. **Crashes:** is a hard crash lost for good (a new drone must be spawned) or repairable?
5. **Range:** the same 250 m uplink as the mech, or longer for drones?
