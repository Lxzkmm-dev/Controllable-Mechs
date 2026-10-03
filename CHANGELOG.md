# Changelog

## 0.9.0 Alpha (branch 0.9.0-alpha, in progress)

- Opened from 0.8.0.
- **0.9.0-a3: the mech body, steadier** (Omar's a2 test: brushing a parked car read as a 5.9 m/s ram; the body threw the mech over a barrier into the canal, landed at 15.7 m/s and fell through the floor to z -130).
  - Following now sets the body's velocity every frame instead of pulling with a force spring. It still shoves what it walks into, but contacts can't throw it.
  - Knocks and blockages no longer make the body lead. Only blasts, drops and falls do.
  - The leading body's ground ray starts at the box top, so a hard landing that sinks it still finds the floor.
  - Nothing under it for 0.6 s: the mech goes back to where it last stood, and the body is asked for again.
- **0.9.0-a2: the Minotaur on a physics body** (CONFIG > CHASSIS > MECH PHYSICS, on by default; needs MNC Physics; the body is mnc\physics\proxy_minotaur.ent in archive\pc\mod\MechsOfNightCity_MechPhysics.archive).
  - A 6 t PhysX box rides with the mech, its bottom 0.6 m above the feet so kerbs and steps pass under it. The mech's own colliders and physical meshes are off while it's there.
  - **Following:** the walk and the turning are unchanged (the same AI orders and turn values). A stiff spring pulls the body onto the mech every physics step, so it shoves cars, props and bodies aside.
  - **Leading:** the body takes over and the mech is placed on it every frame when it's:
    - knocked (more than 2.5 m/s sideways in one frame: a ram)
    - shoved by a blast within 12 m
    - held more than 1.2 m off by something it can't push
    - left with nothing under its feet (a real fall now, instead of the old set-down)
    - walked into a drop for half a second (it steps off)
  - It falls under gravity and lands on spring legs. A landing shakes the view; past 7 m/s it costs hull, and past 12 m/s it wears the legs too. Once settled for 0.45 s it hands back to the walk (an AI teleport to where the body put it).
  - HUD: AIRBORNE - BRACE / STAGGERED - STABILIZING / HARD LANDING.
  - If its own movement keeps pulling it off the body, its AI goes off while the body leads (the drones' way). No body within 10 s: the mech walks without one and gets its collisions back.

## 0.8.0 (main)

The 0.7.0 alpha line, released. Next: the 0.9.0 alpha branch.

- **Drones you can fly:** the Bombus, Griffin, Wyvern and Octant, linked and piloted like the Minotaur.
- **HOVERCORE flight physics:** every drone is a real PhysX rigid body, flown by MNC Physics (the mod's own RED4ext plugin), with:
  - rotor-by-rotor thrust and spool
  - ANGLE / HORIZON / ACRO modes
  - rotor damage that limps or spins out
  - real collisions and crash damage
  - ground effect, downwash and weather wind
  - the Octant's gunship station hold
  - a frame-accurate camera with an optional STABILIZE gimbal
- **A display for each drone's role**, drawn with a smooth anti-aliased shape kit (tools/hud/uikit.py), full width on any screen:
  - **Bombus FPV OSD:** target brackets, blast ring (declutter key), arming strip with impact countdown, motor bars.
  - **Octant gunship display:** sensor and target blocks, mortar spread on the ground, situation map, stores page, airframe panel.
  - **Wyvern ISR feed:** contact tagging and ping, radar, signature and detection.
  - **Griffin hunter HUD:** weapons free/hold, hostile brackets, lock with a lead pip, kills and streaks.
- **Drone weapons:**
  - Octant: LMGs, Hydra rocket pods and a mortar, with a part-damage model.
  - Griffin: SMGs and a laser-guided rocket pod.
  - Wyvern: SMGs.
  - Bombus: four payloads.
- **The world reacts:**
  - A sensor sweep tracks the NPCs around the drone.
  - Enemies notice drones by how loud they are, and turn on whatever shoots them.
  - A destroyed drone's feed shows SIGNAL LOST until the pilot key returns you to V.
- **Diagnostics:** MNC Physics 6 has a hang watchdog (%LOCALAPPDATA%\MNCPhysics\watchdog.log).
- **0.8.0 cleanup:**
  - The drone frame log, a debugging tool for a fixed camera bug, is removed.
  - Dead helpers are gone.
  - The sensor sweep runs one targeting search instead of two.
  - The drone HUDs no longer re-set text that hasn't changed.

The round-by-round log of the alpha follows.
## 0.7.0 Alpha (the 0.8.0 release's development log)

Plan: docs/ROADMAP_0.7.0.md.

- **Phase 0, stability** (after two engine crashes on 2026-09-30, one soon after a disconnect):
  - **Attached effects:** they are killed when a unit leaves the link (unlink, the test mech despawned) or dies, so none outlives what it is attached to. They come back when the mech is next linked.
  - **Weak spots:** a destroyed vanilla weak spot is never sent another event.
  - **Missing slots:** an attached effect is skipped, and logged, if the unit lacks the slot.
  - **HUD removal:** every HUD animation is stopped first, including the schematic's blinks and hit flashes, the warning panel, the hit flash and the direction markers.
  - **Breadcrumbs:** with DIAGNOSTICS on, a log line is written before each effect start, attach, weak spot kill and explosion, so a crash names its last step.
- **Minotaur liveries:** MOTOR POOL spawns the Minotaur as Militech, Arasaka, NCPD or Kurt's, and the HUD names it by livery. `SpawnTestMech()` still takes no argument, for Night City Empires.
- **Drone flight, round 9** (Omar's a19 test with VAXIS disabled: the drone stopped at a wall, flew through a fence, and "freaked out" afterwards):
  - **Not VAXIS:** with VAXIS off, every collision-preset query ("World Static", "World Dynamic", the 8d130e5 control) still returned nothing. The same rays by collision group hit every frame.
  - **Rays use collision groups only:**
    - Static and Terrain for the world;
    - Destructible for fences and breakables (the fence it flew through);
    - Dynamic for movable props;
    - Vehicle for cars.
  - **Settles on the ground:** the "freaking out" was the drone sitting on the ground. The altitude hold pressed it down and the contacts kicked back, so it wobbled ±15 deg indefinitely. Now, on the ground with no climb input, it settles: the hold takes the ground height, and rotation is damped hard.
  - **The mech gets the same safety net:** the pilot's aim and rangefinder, the MK.31 own-target ray and the ground check still try the preset first, then fall back to collision groups. That's Static/Terrain for the world (CMGround.World), and AI/Dynamic/Vehicle for movers (CMGround.Movers).
  - **Down onto the road** (Omar: he could not get low enough to touch the floor): the ground contact is only the model's base, not its rotor or wing tips, which held it a rotor's reach up. The Bombus and Wyvern bases are re-measured to their origin. Each touch-down is logged with how far the base sits above the surface. A hard dive into the road is a crash.
  - **The drone is no longer run as an NPC while flown** (Omar's idea: the game still treats it as an AI and holds the model up).
    - Its AI controller is switched off for the flight, and the once-a-second AI sync is skipped.
    - Its animation's hover height (the ActionAltitudeOffset input) is held at zero.
    - Both are restored when you disconnect. DIAGNOSTICS has DRONE AI OFF WHILE FLYING (on by default) to compare.
  - **Build:** 0.7.0-a22.
- **Drone flight, round 8** (Omar's a18 test: jitter, phasing and V jumping all persist):
  - **Every ray fails, the control too.** The exact 8d130e5 ground ray found nothing at the drone's normal world position, so it isn't the code.
    - The suspect is VAXIS's ULTRA Physics Overhaul, enabled in the active MO2 profile since about the time the rays stopped. It rewrites engine\physics\collision_presets.json; its "World Static" and "World Dynamic" add names such as "Player Collision" that aren't collision groups.
    - The rays now also query the world by collision group (Static, Terrain) rather than preset, and log those hits separately.
  - **Jitter at speed:** the camera moved before the frame's flight step, so it anchored to the drone's last placement, a frame behind and swinging with frame time. The anchor is now led by a frame of velocity.
  - **V's jump:** no jump decision ever fired, so the Space press reaches V another way.
    - Swallowed actions are now consumed at the input listener.
    - Climb and vault (Space at a ledge or low wall) are refused too.
  - **Build:** 0.7.0-a19.
- **Drone flight, round 7** (Omar's a17 test: the model lean limit feels great, and V no longer crouches, but V still jumps, drones still phase through everything, and there is jitter at speed):
  - **The rays still find nothing:** a17 logged 0 hits out of about 300 rays a second.
    - Each query type (static, dynamic, vehicle) is now counted separately.
    - The exact ground ray of the last build that worked (8d130e5) runs alongside as a control, and the drone's position is logged, to pin down why.
  - **Cyberware jumps blocked too:** the charge, double and hover jumps (Reinforced Tendons, Lynx Paws). Only the plain jump had been blocked.
  - **Jitter at speed:** the movement-component sync teleport landed late and snapped a fast drone back four times a second. It now goes once a second, sent to where the drone will be.
  - **Build:** 0.7.0-a18.
- **Drone flight, round 6** (Omar: "none of the fixes worked"):
  - **Collision rays never counted** from the 6-DOF build on. The log shows "-1 m up" (no ground found) on every line since 20:14, and no hits at all, so drones phased through everything.
    - The ray helper is rewritten: each query has its own result, and the nearest is picked by plain X/Y/Z distance.
    - With DIAGNOSTICS on, each second now logs how many rays hit or missed and what the ground ray found.
  - **Model lean limit:** the physics is never capped; only how far the model is drawn leaning is. MODEL LEAN LIMIT per drone is 25 deg for the Bombus and 90 (as flown) for the others. At 75 deg of real pitch the Bombus model shows 25. The camera still shows the true attitude.
  - **Saved Bombus sliders:** Omar's settings file had tilt 61, rate 45, self-levelling 65 from earlier slider moves. Those override the new defaults until RESET.
  - **Diagnostics:** refused jumps and crouches are now logged (to confirm the block), and the session-begin line names the build, so a game started before a push shows it is running old scripts.
  - **Version:** 0.7.0 ALPHA.
- **Drone flight, round 5** (Omar: "flying feels much better"):
  - **Ground:** drones sank into the ground. Contact now uses each type's measured lowest point as it is tilted (the belly when level, a rotor or wing tip when banked), and the ground ray starts a metre above the drone, so one already part-way in still finds the surface.
  - **Bombus defaults:** it pitched forward far too hard and too fast. The defaults are now tilt 25 deg (was 35), rate 140 deg/s (was 220), self-levelling 75% (was 65%), and a slower attitude response. Holding W now leans it about 30 deg instead of about 48. Saved slider values still win; RESET applies the new defaults.
  - **Push-out:** four rays out from the drone's centre, against the world, movable props and vehicles. Anything closer than its radius pushes it out and is a contact, so a car driving into it, or a wall it ended up in, moves it instead of passing through. Characters aren't queried, since the rays start inside the drone.
  - **Stick ramp and expo:** keys are on or off, so each one now ramps a virtual stick in over the type's ramp time, and expo softens the start. The Bombus has a 0.3 s ramp with 0.6 expo; the others 0.2 s and 0.3. W eases it over instead of slamming it to full tilt.
  - **V no longer jumps or crouches** while piloting. Space and Ctrl climb and descend; NoJump alone hadn't stopped it, so the jump and crouch decisions are refused at the source while a session runs.
- **Drone flight, round 4: a full 6-DOF rigid-body model** (CMFlight rewritten; Omar's go-ahead, 2026-10-01). Nothing is kinematic any more.
  - **Rigid body:** a quaternion orientation (no angle limits), angular velocity in the body frame, inertia per axis and per type, and Euler's equations with the gyroscopic term.
  - **Rotors:** four in an X at their real positions, each with spool lag and an efficiency (for damage). Yaw comes from their counter-torque.
  - **Drag:** quadratic per body axis, plus a little linear drag. The top speed is simply where drag meets thrust (no cap).
  - **Airflow and damping:** blade-flapping moments, angular damping and gravity.
  - **Flight controller:** it only commands the rotors.
    - An attitude loop and a rate loop, blended by SELF-LEVELLING.
    - The yaw follows the view, and the collective holds altitude.
    - A mixer with air mode keeps attitude authority when it saturates.
  - **Collisions are rigid-body impulses** at the point that touched, with bounce on walls and friction on floors, so off-centre and glancing hits spin it. Spin is capped at about 1,150 deg/s. The checks cover the static world, dynamic objects and vehicles (static-only rays let it pass through cars and loose props).
  - **Placement:** the drone takes the body's quaternion directly.
  - **Offline check:** tools/flight/sixdof.py mirrors the model. All three weight classes are stable, with tilt, flare, turns, acro flips, ground skids and wall hits.
- **Drone flight, round 3: physics-based tilt** (Omar: the tilt felt like a fixed axis; bobbing near the ground):
  - **Centre of mass:** the body turns about its centre of mass, and the model's origin hangs below it. On the Bombus and Wyvern the origin is at the base, so they swung like a see-saw.
  - **Rotational inertia per type** (agility):
    - the Bombus snaps;
    - the Griffin and Wyvern swing slower;
    - the Octant is slow and heavy (about 1 s to reach its tilt).
    - Before, all four answered identically.
  - **Airflow:** moving through the air pushes the nose up and the tilt back, harder with speed. A tilt must be held into the wind, and letting go flares the drone and brakes it.
  - **Yaw with inertia:** the body winds into turns and can run a little past, while the velocity keeps its direction, so it drifts wide.
  - **Ground contacts slide instead of bouncing,** and the altitude hold adopts the new height. It used to pull the drone back down into rising ground after each bump, which was the bobbing.
  - Checked offline for all three weight classes: stable, with a small overshoot into the tilt and a flare on release.
- **Drone flight, round 2** (Omar's flights, 2026-09-30):
  - **ENTITY TRANSFORM is the move method.** The drone's own transform is set each frame through Codeware, with an AI teleport 4 times a second to keep its movement component in step. It lands exactly where the physics says, and the body really tilts (pitch and roll match).
  - **No minimum altitude:** a floor held the drone half a metre up and bounced it over every curb (the "speed bumps"). The ground is now only a real collision, sized per type.
  - **Skill expression:** each drone type has SELF-LEVELLING (0% = pure acro, 100% = angle mode, blended between), TILT LIMIT and ROLL / PITCH RATE. The defaults are Bombus 65%, Griffin/Wyvern 85% and Octant 95%. This replaces the ACRO MODE switch.
  - **CONFIG > PROFILE:** MECH, BOMBUS, GRIFFIN, WYVERN or OCTANT, each showing its dedicated settings, including its own chase camera (drones default closer and centred). Operator, view and display stay shared.
  - **Full flips:** there is no tilt limit in the physics any more. At low self-levelling a drone loops and rolls right over, and inverted, its thrust drives it down.
- **Drone flight model** (CMFlight), built on what the spikes found:
  - **What the spikes found:** a drone is an NPC puppet, the facility teleport does not move it, an AI teleport each frame lands within centimetres, and its body can't be tilted.
  - **The model:** four rotors with spool lag and a per-rotor efficiency (for damage), and lift along the body's up axis, so tilting is what moves it. It has gravity, split drag and a top speed.
  - **Angle mode** (default): the keys set a wanted tilt that a PD loop reaches, and with no climb input a damped spring holds the altitude.
  - **Acro mode:** CONFIG > DRONES > ACRO MODE switches to rate control with no self-levelling.
  - **Profiles per type:** Bombus (light and quick, 35 degree tilt, 18 m/s), Griffin/Wyvern, and Octant (heavy, 20 degrees, 10 m/s).
  - **Collisions:** the step is swept against the world. The velocity into a surface is removed with a small bounce, and a hit past the type's impact speed costs health, so a crash can destroy it.
  - **Camera:** it rides the real drone and shows its tilt, all of it in the sensor view and a third in chase. No footfall bob on drones.
  - **Title line:** mode, altitude above ground and rotor spool.
  - Checked offline: stable hover, forward flight and climb for all three profiles.
- **Drone test build** (docs/DRONES_TECHNICAL_DESIGN.md, spikes S0-S2):
  - MOTOR POOL spawns a Bombus, Griffin, Wyvern or Octant, and UNIT CONTROL has FLY THE DRONE.
  - **Flight:** a first angle-mode model. WASD tilt it (up to 25 degrees) and the tilt moves it, Space/Ctrl climb and descend, and the mouse turns. It has drag, a top speed of 15 m/s, a wall stop and a ground floor.
  - **Move method:** CONFIG > DIAGNOSTICS > DRONE MOVE METHOD picks how the drone is placed each frame (facility teleport, AI teleport, or AI move carrot).
  - **Test log:** once a second with DIAGNOSTICS on, it logs how far off the drone lands and the tilt sent versus the real tilt. At Begin it logs the drone's class, record and type.
## 0.6.0 Alpha (branch 0.6.0-alpha)

Part damage, per docs/DAMAGE_DESIGN.md. Untested in game.

- **Seven parts** on top of the hull:
  - sensor head;
  - torso (this is the hull);
  - MK.31 left and right arms;
  - left and right legs;
  - missile pods.
- **How a hit lands.** A hit on the piloted mech wears down the part it lands on. The game's hit zone decides the part when it names a limb or the head. Otherwise the part is worked out from where the hit landed on the body. A part breaks once the hits on it add up to its share of the hull (sensor 30%, arms 35%, legs 40%, pods 30%).
- **What a broken part does:**
  - **MK.31 arm:** that gun is shot off the vanilla way (the weak spot on that arm destroyed, with the game's own smoke, sparks and destroyed look) and goes offline. The fire modes use the other gun. With both guns gone you keep walking.
  - **Sensor:** optics (RMB zoom), the rangefinder, the compass tape and pitch ladder, the heading and the hit-direction markers go offline, and the display throws static bursts. Below 50% the rangefinder drops out and static bursts come now and then.
  - **Legs:** a slower walk (the walk animation runs at 60% with one leg broken, 40% with both, 85% with a leg under half) in halting strides, with the view sagging onto the bad leg. The Minotaur has no limping walk of its own, and the game's crippled-leg status did nothing on it.
  - **Pods:** missiles offline. Below 50%, the reload is 1.5x slower.
- **Broken parts stay broken** for the game session until repaired. Repair is a planned mechanic.
- **HUD damage schematic** above the chassis plate. It is the Minotaur's own model, wireframed in a straight front view at 689 x 768 (shown about 430 x 475 in 4K units) (flipped, so its left gun is on the left) and cut into its seven parts, which are tinted by damage and put back together small. The pods on its back show through the torso. It ships as `archive/pc/mod/MechsOfNightCity.archive`, the mod's first non-script file; `tools/schematic` rebuilds it from the game's meshes.
  - each part is green, amber (below 70%) or red (below 35%);
  - a broken part is greyed out and blinks as it breaks;
  - the part just hit flashes;
  - a broken gun reads "MK.31 OFFLINE", and a warning names the part that broke.
- **Damage effects**, started when a part breaks and stopped when it's restored:
  - guns: the Minotaur's smoke at the gun port, and the Centaur boss's weak spot sparks attached to the port;
  - gun warnings: the weak spot's own damage stages at 70% and 35%, before it breaks off;
  - legs: malfunction sparks and generator smoke;
  - sensor: optics malfunction;
  - pods: Minotaur smoke on both pods and the q003 boss's fuel leak, attached to the upper body;
  - hull under 30%: smoke from every vent;
  - destroyed while piloted: the Minotaur's own explosion.
  - Effect files the mech doesn't name are spawned through the FX system (Codeware's `ResourceAsyncRef.SetPath`) and attached to its slots.
- **Hit mapping re-measured** from the meshes. The Minotaur is about 2.7 m tall, and the first guesses were for a much bigger mech.
- **CONFIG > CHASSIS > PART DAMAGE** switch, on by default.
- **Dev tools** (MOTOR POOL, with DIAGNOSTICS on and a mech linked):
  - DAMAGE TEST: shoot the linked mech yourself (it is made neutral to V for the test, since the game drops V's hits on a friendly). It can't die, doesn't turn hostile, its vanilla weak spots can't be destroyed, and each hit names the part it wore on screen.
  - RESTORE MECH PARTS: also refills the hull.
  - BREAK A PART (TEST).
- With DIAGNOSTICS on, every hit logs its zone, its position on the body and the part it was given, so the mapping can be tuned.
## 0.5.0 Beta

The mod is now **Mechs of Night City** (MNC). The folder, the redscript modules and the settings file keep the old name, so nothing needs reinstalling.

- **Tested and settled since 0.2.0:**
  - smooth chassis turning (AI turn orders, one at a time) with CONFIG > CHASSIS > TURN SPEED;
  - the mech's AI kept out of the fight (threats, alerts and combat refused at the source);
  - enemies turning on the mech instead of V;
  - HIDE V WHILE LINKED;
  - the HUD art, the red hit flash and direction markers;
  - the louder low-hull alarm;
  - ledge checks, and a hanging mech set down on the ground;
  - taking over a mech mid-fight.
- **Cleanup:**
  - Removed the finished investigation code: the rotation-teleport fallback and its reports, the aim and fire-result logs, the stray-movement watch, the hidden hint and debug lines on the HUD, the unused launcher path (the Minotaur's launchers are never live weapon objects, so the missile strike is the mod's own), and the old settings fields kept in saves.
  - Merged duplicates: one set-down routine, one signal range, one weapon lookup, one HUD message helper.
- **Performance:** the camera and sensor settings are read once per session instead of every frame. The mech is looked up once instead of several times a frame. The "fired by the pilot" marks on the guns are set on link-in instead of every frame.
- **Mod Settings:** the key bindings are listed under "Mechs of Night City". Keys you rebound under the old name may need rebinding once.
## 0.2.0

The control framework (`ControllableMechs.Control`) is now the mod's pilot mode. The alpha's Pilot Mode is removed.

- **Aim:** the Minotaur's own arms follow the reticle (look-at requests on its weapon parts), and a gun fires only when its barrel is within 4 degrees of it.
- **Damage and credit:** rounds are fired by the mech at the reticle point, and a damage pipeline hook credits the hits to V.
- **Feel:** a heavy camera, a weighted chassis turn, barrel spin-up, optics (RMB), rounds four times as fast, footfall weight, gun and servo audio, and a missile strike (G).
- **The mech's AI is held off** while piloting, and the hull is multiplied (4 by default) with a low-integrity beep.
- **HUD:** a Militech overlay with the keys built in as tags.
- **Terminal:** UNIT, CONFIG and TOOLS tabs with a military style, font and palette. CONFIG holds every setting, in feet and inches, including a CHASE CAMERA section (distance, height, side offset, shoulder).
- **Removed:** the alpha's Pilot Mode and its settings (aim mode, traverse speed, arm tracking, MK.31 damage, debug readout), the SPIKES tab and all spike code. The hit trace stays behind CONFIG > DIAGNOSTICS, off by default; with it off the mod writes nothing to the game log.
- **AI takeover fixed at the source:** the piloted mech kept waking up because gunfire, explosions and nearby hits are stimuli, and its reaction component put it in the Alerted state, where it turns to the noise and walks over. That component is now off while piloted, the threat list is cleared, and the state is checked ten times a second.
- **Recoil:** a camera-only shake that never moves the aim, about a sixth of the old kick, capped at 1.5 degrees up. CONFIG > RECOIL, 0-200%.
- **HUD art:** plates, frames, rulers and hatches from the game's own tank and turret HUD atlases; cell bars; a deeper phosphor green; idle flicker, a damage jolt with tearing lines, a pulsing warning panel. The HUD is scaled to the screen height (it drew 1.5 times too large on 1440-high screens).
- **Settings moved out of the save** into `r6/storages/ControllableMechs/settings.txt`, so loading an older save no longer changes them. Values found in a save are copied over once.
- **Chassis turn:** the standing turn owns the body's heading every frame: a jump back to an old heading is undone the same frame, so it no longer needs the AI's stepped turn. No hold order any more. CONFIG > CHASSIS > TURN SPEED (50-300%, 175% by default) scales the view's traverse and the chassis turn.
- **Threats:** the game's threat functions skip the piloted mech, its weak spots take no damage while piloted, and a lost gun is looked up again.
- **Test spawn** lands on the ground, on the navigation mesh where it can.
- **Aggro:** enemies hit by the piloted mech turn on the mech, not on V; the kill, XP and heat stay V's. CONFIG > OPERATOR > HIDE V WHILE LINKED (off by default) takes V out of enemy senses while piloting.
- **Needs** TweakXL for the missile's attack record.
## 0.1.0 Alpha

The first playable build: the proof of concept works in game.

- **Robot Link:** link any mech, android, drone or spiderbot you look at (J, or from the terminal). Quest NPCs are refused. Orders: follow, hold, move to target.
- **Pilot Mode (Militech Minotaur):** take the mech's sensor feed with \\ (was L).
  - WASD walks the mech, relative to where the torso looks.
  - The mouse turns the torso with weight.
  - LMB/RMB fire the two MK.31 HMGs. Fire modes: staggered (default), linked salvo, split.
  - Militech HUD.
  - V is locked in place while piloting, and a save lock is held.
- **Camera:**
  - The position rides a ring around the mech's centre, placed by the view's facing and not the chassis's. The chassis turns in jerky AI steps, and tying the camera to it made the view lurch and hitch during 360s.
  - The weight is in the torso turn, footfall jolts and recoil.
  - The default mount is lower and further forward: 2.3 m up, 2.6 m ahead.
  - Height, forward offset and mouse sensitivity can be tuned live in SETTINGS.
- **Terminal:** built on the standalone TerminalKit. It has LINK, SETTINGS and TOOLS (TerminalKit Tools) tabs, and the palette is saved.
- **Guns and chassis:** the MK.31s are fixed to the body, so the body now keeps turning toward where the torso aims. It follows lazily: turn orders go out when it's 20 degrees off (6 with a trigger held), no more than every 0.8 s. It faces the aim point while walking. The guns only fire once the chassis is within 15 degrees of the reticle, so the muzzle flash and the rounds agree. Until then the HUD shows ALIGNING CHASSIS.
- **Test tools:** spawn a Militech Minotaur from the terminal.
- **Diagnostics:** an optional DBG readout on the pilot HUD (SETTINGS > DEBUG READOUT). Log lines, including a note when the mech jumps more than 3 m in one frame, go to TOOLS > LOG.

### Since the first alpha build
- **Gimballed aim (new default):** rounds go to what the reticle is on, including characters and vehicles (the reticle raycast now checks dynamic objects as well as world geometry), within each gun's travel around its mount: 12 degrees side to side, 40 down and 25 up. You can shoot down at targets again. Beyond that travel, a round stops at the edge of the cone. The HUD pips show where each gun's rounds will land.
- **Aim along the barrels (now an option):** each round now flies along its own MK.31 barrel, so the rounds always leave the way the muzzle flash does. Two diamond pips on the HUD show where the barrels point. SETTINGS > AIM MODE: GIMBALLED, TO THE RETICLE (the guns wait for the chassis to line up) or ALONG THE BARRELS.
- **Traverse:** the torso turns slower and heavier by default, 40 deg/s with a softer start. There's a TRAVERSE SPEED slider in SETTINGS.
- **Sound:**
  - the game's own sensor-camera servo loops while the view traverses;
  - a heavy servo thunk marks each start;
  - the chassis plays the Minotaur's own turn-in-place sound when it swings round.
- **No run:** Shift no longer does anything, because the Minotaur's "run" came out slower than its walk.
- **Walls:** walk orders stop 2.5 m short of walls and buildings instead of targeting through them. An unreachable target seems to be what made the game teleport the mech.
- **Third-person chase camera:** V while piloting, or SETTINGS > VIEW. The camera sits behind and above the mech, 8.5 m back and 4.2 m up by default, with sliders for both. Aiming starts past the mech so it can't hit itself.
- **New default keys:** ] opens the Robot Link, [ links the robot you look at, \\ pilots and disconnects. The old K, J and L clashed: K is vanilla crafting, J the journal, and L opens Night City Empires' Fixer Link, which is why pressing it brought up the Fixer Link. All three can be rebound in Mod Settings.
- **Robot Link in combat:** the keys now live in the Exploration, Combat and Locomotion input contexts, not just Items, which isn't active while fighting. A 0.25 s debounce stops one press from firing twice. The terminal's own combat block is gone too; only menus, pause and photo mode block it.
- **Arm tracking (experimental, on by default):** the mech gets the game's look-at requests for its hands and chest, aimed at an invisible marker on the aim point. The goal is for the arms, and the MK.31 barrel effects, to follow the reticle instead of pointing straight ahead. SETTINGS > ARM TRACKING. Which parts the Minotaur's rig answers to is unknown.
- **MK.31 damage:** a slider in SETTINGS, 100-300% with 150% by default, offsets the aim mismatch. It's a multiplier on the guns' BaseDamage stat while piloting. Whether NPC weapons use that stat is unverified; TOOLS > LOG shows the before and after values.
- **Chase view:** it's closer by default, 6 m back and 3.2 m up. Turning is critically damped (no snap), and the camera's orbit trails the aim so it swings round the mech smoothly.
- **Aim fix:** the reticle ray no longer misses the ground when looking steeply down in the chase view.
- **No camera clipping:** in both views, when geometry is between the mech and the camera, the camera snaps in to just short of it, then eases back out once the way is clear.
- **Diagnostics:** each trigger pull logs how far each barrel and the chassis are off the view (TOOLS > LOG).

Known issues:
- **Mech jumps:** the mech has been seen jumping away while piloted. That's now logged so the cause can be found.
- **Jump key:** Space can still make V jump if the game's NoJump restriction doesn't hold.
- **Guns:** they fire in game. Whether the flash and the rounds now line up is still to be confirmed.
- **Gamepad:** not supported yet.
- **Backing up (S):** on builds before 4e54241 the camera followed the chassis's facing, so when the Minotaur turned round to back up, the view ended up behind and in front of it. The camera now follows the view's facing; still to confirm in game.

