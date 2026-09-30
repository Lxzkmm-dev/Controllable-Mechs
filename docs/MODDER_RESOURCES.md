# Modder resources for the Controllable Mechs control framework

This is research for the control framework: a module inside Controllable Mechs for mechs and machine-gun emplacements that traverse (yaw) and tilt (pitch) with the reticle. It covers what the modder resources in Omar's MO2 load order provide, what WolvenKit shows about the Minotaur's guns, and which assets could become an emplacement we rotate ourselves. No mod code changed for this.

Tags:
- **[proven]**: it worked in game in Controllable Mechs (Omar's tests, 2026-09-30).
- **[used by X]**: an enabled mod in the load order calls it, and I read the call site.
- **[decl]**: read in a declaration file, not tried in game.
- **[unverified]**: inferred, or not yet tested.

Research method: I read the declaration files (Codeware.Global.reds and the rest), grepped the enabled mods for working examples, and unpacked the game archives with WolvenKit CLI 8.17.1 (see below). Night City Empires and TerminalKIT were only read, never modified.

---

## Proven in Controllable Mechs (0.1 alpha, in game)

- **Frame loop in pure redscript** [proven]:
  - `GameInstance.GetDelaySystem(game).DelayEventNextFrame(player, evt)` queues an `Event` subclass on V each frame, and `@addMethod(PlayerPuppet) protected cb func OnCMPilotTick(evt)` handles it. This is the pattern Anti-Theft Measures uses.
  - It ran at about 60 fps (DT 0.016-0.023, 2000+ frames per session) and costs nothing when not queued.
  - A timer fallback is `DelayCallback(cb, 0.016, false)`.
- **Camera entity** [proven]:
  - `StaticEntitySystem.SpawnEntity` of `base\entities\cameras\simple_free_camera.ent` (vanilla, so no XUtils archive is needed), with `spec.orientation` set to identity. A default `Quaternion` is all zeros.
  - Then `Entity/Attached` → `FindComponentByName(n"camera") as CameraComponent` → `Activate(0.35, true)`.
  - Per frame: `Entity.SetWorldTransform` (position only, identity rotation) plus `CameraComponent.SetLocalOrientation(EulerAngles.ToQuat(yaw/pitch/roll))` and `SetFOV`.
  - Back to V: `Deactivate(0.3, true)`, then the player's `GetFPPCameraComponent().Activate(0.3, true)` and `ResetPitch()`.
  - Yaw 0 faces +Y and positive yaw turns left. `AtanF(y, x)` is atan2.
- **Input** [proven]:
  - Codeware `RegisterCallback(n"Input/Key" / n"Input/Axis")`, registered once at system attach with `SetLifetime(CallbackLifetime.Forever)`, with handlers that return straight away when idle. Mouse deltas come from `AxisInputEvent.GetValue()` scaled by the game's `/controls/fppcameramouse` `FPP_MouseX/Y` / 100.
  - The game's own actions (`Forward`/`Back`/`Left`/`Right` etc.) arrive through `@wrapMethod(PlayerPuppet) OnAction`; returning `true` swallows them.
  - Input Loader actions must be in the Exploration, Combat and Locomotion contexts. Items alone isn't active in combat.
- **V lock** [proven]: `GameplayRestriction.NoMovement` / `NoJump` / `NoCombat` / … via `StatusEffectSystem.ApplyStatusEffect(pid, id, player.GetRecordID(), pid)`. The DBG line showed MOVE-LOCK Y and JUMP-LOCK Y.
- **HUD on the game's HUD layer** [proven]: `GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer").GetVirtualWindow()`, with a canvas reparented to it. Fading the vanilla children's opacity hides the vanilla HUD, and the old opacities are restored on exit.
- **NPC weapon fire** [proven]:
  - `AIWeapon.Fire(owner, weapon, simTime, 0.0, gamedataTriggerMode.FullAuto, targetPosition)`, where the weapon is `ScriptedPuppet.GetWeaponLeft/Right(npc)`. Signature (probed): `(wref<GameObject>, wref<WeaponObject>, Float, Float, gamedataTriggerMode, Vector4, ref<GameObject>, TweakDBID, Float, Float, Vector4, Bool, Float, ref<IPositionProvider>, Vector4, CName)`.
  - Rounds go to the target position, but the muzzle flash and tracer follow the model's barrels.
- **AI orders on a mech** [proven: it walks and turns]: `AIMoveToCommand` (with `facingTarget` and `rotateEntityTowardsFacingTarget`) and `AIRotateToCommand`, through `GetAIControllerComponent().SendCommand` / `CancelCommand`, after `SetAIRole(new AINoRole())` + `OnAttach()`. Orders into walls seem to trigger teleports, so walk targets are raycast-clipped.
- **Sounds** [proven: they play]: `GameObject.PlaySoundEvent(mech, n"...")` with names from WolvenKit's `soundEvents.json`:
  - `dev_surveillance_camera_rotating` (+ `_stop`)
  - `nme_boss_smasher_lcm_servo_short`
  - `enm_mech_minotaur_loco_idle_to_idle_90`
- **Raycast** [proven for world geometry]: `SyncRaycastByCollisionPreset(from, to, n"World Static" | n"World Dynamic", out TraceResult, true)` and `SyncRaycastByCollisionGroup(from, to, n"Static", out hit, true, false)`, read with `Cast<Vector4>(hit.position)`.
- **Look-at requests on the Minotaur's hands and chest** [proven: no visible effect]: `LookAtAddEvent` with `SetEntityTarget(marker, n"", zero)` and `bodyPart` = RightHand / LeftHand / Chest did not move its arms. See the anim graph findings below for the part names it does use.

---

## WolvenKit: what the game files show

Tool: WolvenKit CLI 8.17.1 at `D:\Downloads\WolvenKit.Console-8.17.1\WolvenKit.CLI.exe`, the official release. It runs on the installed .NET 8. The 9.0.1 CLI needs .NET 10, which isn't installed.
- `archive <content dir> -l -r <regex>` lists files.
- `extract <dir> -o <out> -r <regex>` extracts them.
- `convert serialize <in> -o <existing dir>` converts to JSON.

Game archives: `G:\SteamLibrary\steamapps\common\Cyberpunk 2077\archive\pc\content`. Everything was extracted to a temp folder; no game or MO2 file was written.

### The Minotaur (Character.q003_militech_mech)

- **Entity:** `base\mechanical\mech\mch_003__minotaur.ent` and `...\mch_003__minotaur\mch_003__minotaur.ent` / `.app`.
  - The appearances are default, militech_01, arasaka_01, police_01 and kurt.
  - Each is built from part entities: body, legs, arm_l/r, hands, bags, weapons_l/r and lights.
  - Animation uses the rig `base\mechanical\mech\mch_003__minotaur\rig\mch_003__minotaur.rig` (68 bones) and the anim graph `base\gameplay\anim_graphs\maelstrom_exo.animgraph`. The animation sets are `cr_minotaur_hmg_action_combat` / `_locomotion_combat` / `_reprimands`.
- **How the MK.31s attach** [read in the files]:
  - The guns are **not separate objects**. `mch_003__minotaur_weapons_l_01.ent` / `_r_01.ent` each hold an `entSkinnedMeshComponent` of the same name (mesh `...\meshes\mch_003__minotaur_weapons_l_01.mesh` / `_r_01.mesh`). They're skinned through an `entExternalComponent` (`External5108`) to the mech's root `entAnimatedComponent`.
  - The gun meshes are weighted to the bones `l_weapon_jnt` / `r_weapon_jnt`, the ends of the arm chains `l_arm_01 → 02 → 03 → 04 → l_weapon_jnt` (right the same) under `upper_body_01`.
  - So the visible barrels move **only** with the rig's animation. That's why bending the rounds (the gimbal) can't turn the muzzle flash.
  - The `WeaponObject`s that `AIWeapon.Fire` uses are separate items that the NPC record equips. Their visuals aren't what you see.
- **Can the guns be hidden or replaced?**
  - The gun meshes are named components in every appearance (`mch_003__minotaur_weapons_l_01` / `_r_01`, alongside `mch_003__minotaur_arm_l_01` etc.). At runtime, `mech.FindComponentByName(n"mch_003__minotaur_weapons_l_01")` + `IComponent.Toggle(false)`, or a `chunkMask` change, should hide one gun [unverified].
  - A replacement gun we rotate ourselves could then sit where the barrel was, as a separate spawned entity moved every frame, or as a component bound to `r_weapon_jnt` [unverified].
- **Anim graph** (`maelstrom_exo.animgraph`, 310 MB as JSON):
  - Node counts: 6 `LookAtController`, 24 `AimConstraint` (+25 `_ObjectUp`), 90 `OrientConstraint` variants, 251 `RotateBone`, 8 `SetBoneOrientation`.
  - **Look-at part names:** `LeftWeapon`, `RightWeapon`, `Weapon`, `Chassis`, `Chest`, `Head`, `Eyes`, `LeftHand`, `RightHand`. The Minotaur likely aims its guns through the **LeftWeapon / RightWeapon / Weapon / Chassis** look-at parts, which I haven't tried (I sent RightHand/LeftHand/Chest) [unverified; the cheapest next experiment].
  - **IK input groups** `ikLeftArm` / `ikRightArm` (and legs), each with `position`, `rotation`, `weightPosition`, `weightRotation`, `poleVector`, `isEnabled`. These could pose the arms directly from script IK requests [unverified].
  - Graph variables: `weapon_off` (bool), `shield_lookat_active`, `disable_horizontal_lookat` (int), `attack`, `move`, `direction`, `pose`.

### Assets for an emplacement we rotate ourselves

| Asset | Path | What it has | Use |
|---|---|---|---|
| Portable turret | `base\weapons\turrets\portable_turret\w_turret__portable_turret__base1.ent` (+ `entities\w_turret__portable_turret__base1_01.ent`, mesh `..._base1_01.mesh`) | Rig bones `Root, Trajectory, base, yaw, pitch, snapping_point`; animated + anim-controller components | A turret with real yaw/pitch joints, driven through its graph or look-ats [unverified] |
| MaxTac turret | `base\weapons\turrets\maxtac_turret\w_turret__maxtac_turret__base1.ent` | Rig `base, base_rotation, turret_a, turret_b, turret_guns`; separate meshes `..._g_base`, `_r_base`, `_arm`, `_guns`, `_cam`; collider, targeting, sound, slot components | **Best split-mesh candidate**: static ground base, a yaw part (`r_base`) and a pitch part (`arm`/`guns`), each a mesh we can place and rotate |
| Militech HMG (the MK.31 weapon) | `base\weapons\firearms\special\militech_hmg\w_special__militech_hmg__rcv1.ent` (rig `rig\w_special__militech_hmg__rcv1.rig`) | Bones incl. `barrel`, `fx_muzzle`; `entEffectSpawnerComponent` (its muzzle effects), `entSlotComponent`, lights | The gun itself on a mount; `fx_muzzle` / its slots give a muzzle point and flash for our own effects |
| Static HMG prop | `base\environment\decoration\weapons\hmg\hmg_a.mesh` | Mesh only (no .ent) | A static gun to add as a mesh component to an empty entity |
| Security turrets (reference) | `base\gameplay\devices\security_systems\security_turret\security_turret_1.ent` | Full device logic | Night City Empires spawns and moves these [used by NCE]; heavy for our use |

**How a gun can be spawned and turned every frame** (see the resource sections below for signatures):
1. **Whole-entity parts, the simplest:** spawn each moving part as its own entity with `StaticEntitySystem.SpawnEntity` (template path) or `DynamicEntitySystem.CreateEntity`. Every frame, set the yaw part's and the pitch part's `Entity.SetWorldTransform` from the reticle yaw/pitch [SetWorldTransform proven on our camera entity].
   - Needs one `.ent` per part. The turret and HMG `.ent`s above work as-is. For single meshes (e.g. `maxtac_turret__base1_guns.mesh`), either ship tiny `.ent`s in our own archive (WolvenKit/ArchiveXL), or add an `entMeshComponent` at build time to an empty entity (Codeware `EntityBuilderWrapper...AddComponent`, used by XUtils Lua).
2. **One entity with a component hierarchy:** give the gun `entMeshComponent`s a `parentTransform` (`entHardTransformBinding` with `bindName` / `slotName`) and rotate them with `IPlacedComponent.SetLocalOrientation` [decl; creating a binding from script is unverified].
3. **Graph-driven turret:** spawn the portable or MaxTac turret and aim it through look-ats or `AnimFeature_DeviceCameraControlled.currentRotation` [unverified].

For the MG emplacement test unit, option 1 with the MaxTac turret's split meshes, or the portable turret, is the lowest-risk start. Fire through `AIWeapon.Fire` on a spawned weapon item, or `gameprojectileSpawnerLaunchEvent` (Doctrine Hydra pattern), and play effects at the pitch part's muzzle.

---

## Resource survey (all enabled resources)

## Summary table

| Resource | Version (meta.ini) | Provides | Framework-relevant |
|---|---|---|---|
| Codeware | 1.20.5.0 | Entity systems (Dynamic/Static), CallbackSystem (entity lifecycle, input key/axis), component fields (localTransform/parentTransform/chunkMask), TraceResult.GetHitEntity, ink/HUD layer access, custom popups, reflection | **yes (core)** |
| ArchiveXL | 1.27.3.0 | Archive/resource loading; dynamic appearance helpers (script side is tiny) | yes (asset side: .xl, dynamic appearances); minimal script API |
| TweakXL | 1.11.4.0 | YAML tweaks + runtime TweakDBManager/TweakDBBatch (create/clone records) | yes (weapon/attack/projectile records for turrets) |
| RedFunctions | 0.13.0.0 | Resource checks, raw mouse hook deltas, script-input blocking, JSON, ModStorage, console vars | yes (input) |
| RedFileSystem | 0.15.1.0 | Sandboxed file storage (sync + async) | persistence only |
| RedData | 0.10.1.0 | UUID + JSON (ParseJson/ToJson) | persistence only |
| RedLogger | 1.4.1.0 | Per-mod session logs | logging only |
| Audioware | 1.9.9.0 | Audio playback incl. per-entity emitters | minor (gun/servo SFX on turret entity) |
| Mod Settings | 0.2.21.0 | Native settings menu vars incl. key bindings | yes (config/keybinds) |
| Input Loader | 0.2.3.0 | Merges `r6/input/*.xml` into input contexts | yes (custom actions) |
| re INPUT Mod Loader - v2.31 | 2.0.0.0 (meta) | a_input_loader.dll only, no script API | no (unverified) |
| Redscript Configuration Framework | 3.0.1.0 | Config hub, schema/presets; RCFInput key overrides | minor (config, key override) |
| XUtils | 1.0.2.0 | Camera entity (spawn/activate/FOV/DOF), free-fly, raycast helpers, FX helpers, input hooks, HUD helpers; Lua CET layer | **yes (best working reference)** |
| PhotoMode-EX | 1.4.1.0 | Photo mode extensions; script API is only Require/Version | no |
| Doctrine Hydra | 1.2.0.0 | Smart missile arm; native SmartGun UI bridge; **projectile launch via gameprojectileSpawnerLaunchEvent** | **yes (projectiles)** |
| RedIMGRetriever | 0.3.0.0 | Remote/local images in ink | no (UI nicety) |
| TerminalKIT | no meta.ini (version unknown) | Redscript terminal UI framework; TKHud strips/toasts on inkHUDLayer; dev tools (spawn tester, look-at inspector) | yes (UI/HUD) |
| Cyber Engine Tweaks | 1.37.1.0 | Lua runtime (onUpdate per frame, Observe/Override); no library API files | yes (per-frame tick option, prototyping) |
| Anti-Theft Measures / CustomHackingSystem | 2.1.2.0 | Custom quickhack minigames (reds + Lua) | no |
| Native Interactions Framework | 1.1.3.0 | Lua workspot/interaction definitions | no |
| RedProfiler (extra) | 1.0.1.0 | Script CPU profiler natives | dev only |
| RedWindows (extra) | 2.2.0.0 | Uses RedFunctions mouse hook + input block (reference usage) | reference only |
| Night City Empires (extra, enabled) | - | Spawns real security turret .ent via DynamicEntitySystem | reference usage |
| Missile Rain (extra, enabled) | - | gameprojectileSpawnerLaunchEvent usage | reference usage |
| Immersive Third Person BOBW / TCOC (extra, enabled) | - | LookAtAddEvent, AnimationControllerComponent.ApplyFeature/SetInputFloat usage | reference usage (anim) |
| Nitrous (extra, enabled) | - | SyncRaycastByQueryFilter + TraceResult.GetHitEntity usage | reference usage (raycast) |
| General Shadows Fixes (extra, enabled) | - | Writes component `parentTransform.bindName`/`skinning.bindName` at runtime | reference usage (binding) |

Note: `Appearance Menu Mod` is **disabled** (`-Appearance Menu Mod`), so AMM's use of `simple_free_camera.ent` is not available as a live reference in this profile.

---

## Codeware 1.20.5

Files: `Codeware\red4ext\plugins\Codeware\Scripts\Codeware.Global.reds` (43,654 lines). Lines 1 to about 41,800 are RTTI dumps (`@addField` on vanilla classes plus `native class` declarations for engine types not otherwise exposed). The hand-written API starts at about line 41,810. Other files: `Codeware.UI.reds`, `Codeware.UI.TextInput.reds`, `Codeware.Localization.reds`, and `Codeware.reds` (37 bytes, module stub).

### 1. Entity spawning / attaching
- [decl] `Codeware.Global.reds:43419` `public native class DynamicEntitySpec {` with fields (43420-43430):
  `recordID: TweakDBID; templatePath: ResRef; appearanceName: CName; position: Vector4; orientation: Quaternion; persistState: Bool; persistSpawn: Bool; alwaysSpawned: Bool; spawnInView: Bool; active: Bool; tags: array<CName>;`
- [decl] `:43436` `public native func CreateEntity(spec: ref<DynamicEntitySpec>) -> EntityID`
- [decl] `:43437` `public native func DeleteEntity(id: EntityID) -> Bool`; `:43438/43439` `EnableEntity` / `DisableEntity`
- [decl] `:43444` `public native func GetEntity(id: EntityID) -> ref<Entity>`; `:43442` `IsSpawned`; `:43449` `GetTagged(tag: CName) -> array<ref<Entity>>`
- [decl] `:43455` `public native func RegisterListener(tag: CName, target: ref<IScriptable>, function: CName)`, which gets a `DynamicEntityEvent` (`:43413`) with `GetEventType()` returning `Created/Deleted/Spawned/Despawned/Dead` (`:43405-43411`).
- [decl] `:43460` `public static native func GetDynamicEntitySystem() -> ref<DynamicEntitySystem>`
- [decl] `:43511` `public native class StaticEntitySpec {` with `templatePath, appearanceName, position, orientation, attached: Bool, tags` (43512-43517)
- [decl] `:43522` `public native func SpawnEntity(spec: ref<StaticEntitySpec>) -> EntityID`; `:43523` `DespawnEntity`; `:43524` `AttachEntity(id: EntityID) -> Bool`; `:43525` `DetachEntity`. "Attach" here means attach to the world, not to a parent.
- [decl] `:43543` `public static native func GetStaticEntitySystem() -> ref<StaticEntitySystem>`
- [decl] Entity building hooks: `:41854` `EntityBuilderEvent.GetEntityBuilder() -> ref<EntityBuilderWrapper>`; `:42173-42199` EntityBuilderWrapper / TemplateWrapper / AppearanceWrapper each have `AddComponent(component: ref<IComponent>)`. These let you inject components into an entity or appearance before it is built.
- [decl] `:42167` `@addMethod(Entity) public native func AddComponent(component: ref<IComponent>)`; `:42163` `GetComponents()`; `:42165` `FindComponentByType(type: CName)`
- [decl] Lifecycle callback targets: `:41862` `EntityLifecycleEvent.GetEntity() -> wref<Entity>`; `:41906-41912` `EntityTarget.ID(entityID) / Type / RecordID / Template(templatePath) / Appearance / Definition`; `:41901` `DynamicEntityTarget.Tag(tag)`; `:41930` `StaticEntityTarget.Tag(tag)`; `:41896` `ComponentTarget.Name(name)`
- Event names are registered natively and do not appear in the .reds. The names I saw in working code are `n"Entity/Initialize"` and `n"Entity/Attached"` [used by XUtils `XUtilsEntityBuilder.reds:7-8`, `XUtilsCameraSystem.reds:706`], plus `Session/Ready`, `Session/BeforeEnd` and `Resource/PostLoad` [used by XUtils].
- **Parenting / slot binding (the key finding for a turret hierarchy):**
  - [decl] `:1863-1866` `@addField(IPlacedComponent) public native let localTransform: WorldTransform;` and `public native let parentTransform: ref<entITransformBinding>;`
  - [decl] `:42232-42233` `@addField(IPlacedComponent) public native let worldTransform: WorldTransform;`
  - [decl] `:15763-15767` `public abstract native class entIBinding extends ISerializable { enabled: Bool; enableMask: entTagMask; bindName: CName; }`
  - [decl] `:15800` `public abstract native class entITransformBinding extends entISourceBinding {}`
  - [decl] `:15748-15749` `public native class entHardTransformBinding extends entITransformBinding { public native let slotName: CName; }`. You bind a component to another component (`bindName`) and, optionally, to a slot or bone of it (`slotName`).
  - [decl] `:15787-15788` `entISkinTargetComponent { skinning: ref<entSkinningBinding>; ... }`
  - [decl] `:16073-16077` `public native struct entSlot { slotName: CName; relativePosition: Vector3; relativeRotation: Quaternion; boneName: CName; }`
  - [decl] `:2893-2896` `@addField(SlotComponent) public native let slots: array<entSlot>;` / `fallbackSlots`
  - [decl] `:15758-15761` `entIAttachment { source: wref<IComponent>; destination: wref<IComponent>; }`; `:15746` `entHardAttachment`; `:16080` `entSlotAttachment`
  - [used by General Shadows Fixes `GeneralShadowsFixes.reds:7158-7160`] `skinnedMesh.parentTransform.bindName = n"root"; skinnedMesh.skinning.bindName = n"root"; skinnedMesh.LoadAppearance(true);`. This rewrites an existing binding at runtime. Creating a new `entHardTransformBinding` from script and assigning it before attach is [unverified].
  - [decl] `:15286` `entAnimEntityToEntityAttachmentEvent extends Event {}`: an empty event (no script fields), so entity-to-entity attachment from script is [unverified].

### 2. Per-frame transforms
- [decl] `:42170-42171` `@addMethod(Entity) public native func SetWorldTransform(transform: WorldTransform)` [used by XUtils `XUtilsCamera.reds:152` on its camera entity, driven every frame from CET onUpdate → `XUtilsCameraSystem.FrameTick` (`XUtilsCameraSystem.reds:1224`, `init.lua:473/483`); also used every update in XUtils Lua `ShapeEntity.lua:183`, `Subscription.lua:640`]
- [decl] `IPlacedComponent.localTransform` (see above). Writing it directly is [unverified] for live effect; XUtils sets it only before `AddComponent` (`ShapeEntity.lua:73-79`).
- Vanilla `IPlacedComponent.SetLocalOrientation(Quaternion)` / `SetLocalPosition` [used by XUtils `XUtilsCamera.reds:165` `this.m_component.SetLocalOrientation(EulerAngles.ToQuat(euler));`; declaration not in scanned files].
- Vanilla `TeleportationFacility.Teleport(obj, pos, EulerAngles)` [used by Night City Empires `NCETurretSystem.reds:127` to move a spawned turret; used by XUtils `XUtilsTeleport.reds:22` every 0.05 s on the player].
- Per-frame tick in pure redscript: Codeware adds `DelaySystem.DelayEventNextFrame(controller, event)` (`:42507-42527`, built on vanilla `DelayCallbackNextFrame`). Vanilla `DelaySystem.DelayCallbackNextFrame(cb)` [used by DigitalVixen Core `DVCore_Explosions.reds:82`]. A self-rescheduling next-frame event is **[proven]** as a per-frame loop in Controllable Mechs (`DelayEventNextFrame(player, evt)` handled by a `PlayerPuppet` cb). XUtils instead ticks from CET `onUpdate`.

### 3. Mesh / appearance
- [decl] `:42221-42230` `@addMethod(IComponent)`: `ChangeResource(path: ResRef, opt wait: Bool) -> Bool`, `ChangeAppearance(name: CName, opt wait: Bool) -> Bool`, `LoadAppearance(opt wait: Bool) -> Bool`, `RefreshAppearance() -> Bool`, `ResetMaterialCache()`
- [decl] `:42217-42220` `@addField(IComponent) appearanceName: CName; appearancePath: ResRef;`
- [decl] `:2359-2396` `@addField(MeshComponent)`: `mesh: ResourceAsyncRef`, `meshAppearance: CName`, `visualScale: Vector3`, **`chunkMask: Uint64`** (`:2381-2382`), `isEnabled: Bool`, `castShadows`, `renderingPlane`, ...
- [decl] `:16052-16068` `entSkinnedMeshComponent { mesh; meshAppearance; chunkMask: Uint64; visibilityAnimationParam: CName; isEnabled; ... }`
- [decl] `:42235-42236` `@addField(MeshComponent) meshResource: ref<CMesh>`; `:42275-42281` `meshMeshAppearance.SetMesh / ResetMaterialCache`
- [decl] `:1883-1888` `@addField(IVisualComponent) autoHideDistance; renderSceneLayerMask; forceLODLevel`
- Hiding meshes: vanilla `IComponent.Toggle(Bool)` [used by XUtils `XUtilsCameraSystem.reds:893-894`, which toggles every `entIVisualComponent` on the player off and on; used by XUtils Lua `ShapeEntity.lua:130-131` to force a visualScale refresh].
- Runtime mesh assembly: [used by XUtils Lua `ShapeEntity.lua:65-80`] `entMeshComponent.new()`, set `name`, `mesh`, `visualScale`, `meshAppearance`, `localTransform`, `isEnabled`, then `entity:AddComponent(component)`, inside the Codeware assemble callback of a StaticEntitySystem-spawned `empty_entity.ent`.

### 4. Camera
- [decl] `:16656` `public native class FreeCameraComponent extends CameraComponent {}`
- [decl] `:19513-19520` `gameFreeCamera extends GameObject { baseSpeed; analogTurnRate; mouseTurnRate; activationBlendTime; deactivationBlendTime; usePhysicalCollision }`
- [decl] `:432-469` `@addField(CameraComponent)` anim params (`animParamFovOverrideValue`, zoom, DOF, `weaponPlane`)
- [decl] `:615-616` `@addField(Entity) customCameraTarget: ECustomCameraTarget;`
- Vanilla `CameraComponent.Activate(blendTime, bool)`, `Deactivate`, `SetFOV`, `GetFOV`, and `FPPCameraComponent.ResetPitch()` [used by XUtils `XUtilsCamera.reds:186, 204, 218-219, 255, 261`; declarations not scanned].

### 5. Weapons / projectiles
- [decl] `:2647-2674` `@addField(ProjectileComponent)`: `onCollisionAction`, `useSweepCollision`, `sweepCollisionRadius`, `rotationOffset`, `deriveOwnerVelocity`, `filterData`, `queryPreset: QueryPreset`, `gameEffectRef: EffectRef`, ...
- [decl] `:3116-3117` `@addField(WeaponObject) effect: ResourceRef; // rRef<gameEffectSet>`
- [decl] `:15810-15817` `EntitySpawnerComponent { slotDataArray: array<EntitySpawnerSlotData> }`, `EntitySpawnerSlotData { slotName; spawnableObject: TweakDBID }`
- No Codeware firing helper. See Doctrine Hydra and Missile Rain for projectile launching.

### 6. Effects
- [decl] `:678-679` `@addField(FxResource) effect: ResourceAsyncRef; // raRef<worldEffect>`
- Vanilla `FxSystem.SpawnEffect(FxResource, WorldTransform) -> FxInstance` [used by XUtils `ParticleEffects.reds:100,121`] and `GameObjectEffectHelper.StartEffectEvent(entity, effectName, bool, worldEffectBlackboard)` [used by XUtils `ParticleEffects.reds:165`].

### 7. Raycasts / spatial queries
- [decl] `:42283-42286` `@addMethod(TraceResult) public final static native func GetHitObject(self: script_ref<TraceResult>) -> ref<ISerializable>` and **`GetHitEntity(self: script_ref<TraceResult>) -> ref<Entity>`** [used by Nitrous `nitro.reds:2078-2082`: `sqs.SyncRaycastByQueryFilter(rayStartPos, rayEndPos, QueryFilter.ALL(), traceResult, false, false)` then `TraceResult.GetHitEntity(traceResult)`]
- [decl] `:474-497` `@addField(ColliderComponent) colliders; simulationType; filterData: ref<physicsFilterData>; isEnabled ...`; `:2881-2886` `SimpleColliderComponent { isEnabled; colliders; filter }`; `:3030-3033` `TriggerComponent { includeMask; excludeMask }`
- Vanilla `SpatialQueriesSystem.SyncRaycastByCollisionGroup(start, end, group: CName, out TraceResult, bool, bool)` [used by XUtils `XUtilsRaycast.reds:113` etc.; XUtils lists group names at `XUtilsRaycast.reds:3-22`: Player, AI, Static, Dynamic, Vehicle, Tank, Destructible, Terrain, ... PlayerBlocker, NPCBlocker]
- Vanilla `SpatialQueriesSystem.Overlap(boxDims, pos, orientation, group, out result)` [used by Gone in 2077 Seconds `GoneIn2077Seconds_System.reds:707-709`]
- Vanilla `TargetingSystem.GetLookAtObject(player)` [used by TerminalKIT `TKToolsWorld.reds:125`]; `CameraSystem.GetActiveCameraForward()` [used by XUtils `Target.reds:45`]

### 8. Input
- [decl] `:41848-41851` `AxisInputEvent extends KeyInputEvent { GetValue() -> Float; GetMouseX(); GetMouseY() }`
- [decl] `:41877-41882` `KeyInputEvent { GetAction() -> EInputAction; GetKey() -> EInputKey; IsShiftDown(); IsControlDown(); IsAltDown() }`
- [decl] `:41920-41922` `InputTarget.Key(key: EInputKey, opt action: EInputAction)`, `InputTarget.Axis(axis: EInputKey, opt threshold: Float)`
- [decl] `:41821-41828` `CallbackSystem.RegisterCallback(eventName: CName, target, function: CName, opt sticky) -> ref<CallbackSystemHandler>`; `:41837-41843` `CallbackSystemHandler.AddTarget / SetRunMode / SetLifetime / Unregister`
- [used by XUtils `XUtilsCameraSystem.reds:128-138`] `RegisterCallback(n"Input/Axis", this, n"OnMouseAxis").AddTarget(InputTarget.Axis(EInputKey.IK_MouseX)).AddTarget(InputTarget.Axis(EInputKey.IK_MouseY))...SetLifetime(CallbackLifetime.Forever)` and `RegisterCallback(n"Input/Key", ...)`. The handler (`:2138-2158`) feeds `event.GetValue()` into yaw/pitch, which is exactly the reticle-driven traverse input the framework needs.

### 9. UI / HUD
- [decl] `:42563-42578` `inkSystem { GetLayers(); GetLayer(layer: CName) -> ref<inkLayerWrapper>; GetWorldWidgets() }`, `GameInstance.GetInkSystem()`
- [decl] `:42681-42685` `inkLayerWrapper { GetLayerName(); GetVirtualWindow() -> wref<inkVirtualWindow>; GetGameController(); GetGameControllers() }`
- [used by TerminalKIT `TKHud.reds:234-241`] `GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer")` then `root.Reparent(layer.GetVirtualWindow())`
- [decl] `Codeware.UI.reds:832` `public abstract class inkCustomController extends inkLogicController` (`GetRootWidget` :938, `Reparent` :991-1012, `Mount` :1018-1029); `:1282` `public abstract class InGamePopup extends CustomPopup`; `:2094` `CustomPopupManager extends ScriptableService`; `:5` `ButtonHintsEx`; `:2560` `TextInput`
- [decl] `Codeware.Global.reds:43119-43120` `worlduiIGameController.GetWorldWidgetComponent()`

### 10. Animation / IK
- [decl] `:104-109` `@addField(AnimationControllerComponent) actionAnimDatabaseRef; animDatabaseCollection; controlBinding`; `:75-102` `@addField(AnimatedComponent) rig; graph; animations; animParameters; serverForcedLod/Visibility ...`
- [decl] `:8341-8342` **`public native class AnimFeature_DeviceCameraControlled extends AnimFeature { public native let currentRotation: Vector4; }`**. This feature is the likely yaw/pitch driver for device (camera/turret) anim graphs [unverified which graphs read it].
- [decl] `:8345-8350` `AnimFeature_DroneLocomotion { speed; angularSpeed; lookAtAngle; desiredSpeed; pathCurvative }`
- [decl] `:8896-8912` `animLookAtPreset_DroneHorizontal` / `animLookAtPreset_DroneVertical { softLimitDegrees; hardLimitDegrees; hardLimitDistance; backLimitDegrees; suppress; mode }`
- [decl] `:111-112` `@addField(AnimFeature_Aim) aimPoint: Vector4;`
- [decl] `:8550-8554` `animIKTargetParams_Add/Remove/Update` (empty classes); `:8683` `AnimInputSetterQuaternion extends AnimInputSetter`; `:13628` `ContextualLookAtAddEvent extends LookAtAddEvent`; `:15841` `entLookAtLimits`
- Vanilla `AnimationControllerComponent.ApplyFeature(obj, n"Name", feature)` [used by ITP BOBW `tpp_camera_bridge.reds:1309` `ApplyFeature(player, n"LookAt", lookAt)`], `AnimationControllerComponent.SetInputFloat(obj, n"var", v)` [used by ITP-TCOC `ITP-TCOC.reds:55`], `LookAtAddEvent` with `SetStaticTarget` / `SetPositionProvider` / `bodyPart` / `SetLimits` / `request` [used by ITP BOBW `tpp_camera_headlook.reds:67-94`; Photomode UI Improvements `LookAtCharacter.reds:437`].

### 11. Persistence / misc
- [decl] `:43190-43191` `Print(text)`, `ModLog(mod: CName, text)`; `:42376-42450` Reflection API; `:41940-41947` `ResourceDepot.ResourceExists(path: ResRef)`, `GameInstance.GetResourceDepot()`; `:43617-43639` `WorldStateSystem`.

---

## ArchiveXL 1.27.3
- Provides: loads archives, `.xl` resource patches and dynamic appearances (`!variant` names). The script API is minimal.
- [decl] `ArchiveXL.Global.reds:3-9` `public abstract native class ArchiveXL { GetBodyType(puppet) -> CName; EnableGarmentOffsets(); DisableGarmentOffsets(); Require(version: String) -> Bool; Version() -> String }`
- [decl] `ArchiveXL.DynamicAppearance.reds` (module `ArchiveXL.DynamicAppearance`): `OverrideDynamicAppearanceCondition(app, attr, value) -> String`, `ConvertAppearanceNameToTPP/FPP`, `...PartialSleeves/FullSleeves`
- Need 3 (mesh/appearance): ArchiveXL dynamic appearances are resolved when you use appearance names such as `base!variant` with `IComponent.ChangeAppearance` or `DynamicEntitySpec.appearanceName` [unverified for mech entities]. The practical value is shipping new `.ent`/`.app`/`.mesh` resources (a turret base, yaw ring and pitch cradle as separate meshes) via `.archive` + `.xl`.

## TweakXL 1.11.4
- Provides: YAML tweak loading plus a runtime TweakDB API.
- [decl] `TweakXL.Global.reds:3-4` `public abstract native class ScriptableTweak { protected cb func OnApply() -> Void }`
- [decl] `:82-89` `TweakDBManager.SetFlat(id, value: Variant) / CreateRecord(id, type: CName) / CloneRecord(id, base) / UpdateRecord(id) / RegisterName / StartBatch() -> ref<TweakDBBatch>`
- [decl] `:52-61` `TweakDBInterface.GetFlat(path) -> Variant / GetRecord / GetRecords(type) / GetRecordCount / GetRecordByIndex`
- Need 5: define turret weapon items, attacks and projectile templates as records (Doctrine Hydra does this in `r6\tweaks\DoctrineHydra\attacks_and_rounds.yaml`, `items.yaml`) [used by Doctrine Hydra, YAML side].

## RedFunctions 0.13.0
- Provides: native helpers for pure-redscript mods: resource/archive checks, real clock, file IO, clipboard, **raw mouse hook**, **script-input blocking**, TweakDB name search, JSON, ModStorage, console vars.
- Need 8 (input):
  - [decl] `RedFunctions.reds:24-27` `MouseX01() -> Float`, `MouseY01()`, `MouseButton(button: Int32) -> Bool`, `IsGameForeground()`
  - [decl] `:29-32` `MouseHook() -> Bool`, `MouseTakeDeltaX() -> Float`, `MouseTakeDeltaY() -> Float`, `MouseTakeWheel() -> Float`
  - [decl] `:40-45` `SetScriptInputBlocked(blocked: Bool)`, `AllowScriptInputFor(listener: ref<IScriptable>)`, `IsScriptInputBlocked()`, `ScriptInputHookReady()`, `ScriptInputHookError()`
  - [used by RedWindows `RW_System.reds:705-707, 822-828, 1145-1146`] `RedFunc.MouseHook(); RedFunc.SetScriptInputBlocked(true); ... RedFunc.AllowScriptInputFor(this); ... let dx = RedFunc.MouseTakeDeltaX() * speed;`
- Need 1 / 3: [decl] `:7` `ResourceExists(path: String) -> Bool`; `:37` `MountPatchedArchive(templateRelPath, outName, newResourcePath, sentinels, values) -> Bool`
- Need 11: [decl] `RedFunctions_Storage.reds:5-30` `ModStorage.Open(name) / ReadJson / WriteJson / ReadText / WriteText ...`; `RedFunctions_Json.reds:14-98` `JsonValue/JsonMap/JsonList/JsonText.Parse/Write`; `RedFunctions_EngineConfig.reds:4-53` `ConsoleVars.Get/Set...`

## RedFileSystem 0.15.1 (brief)
- [decl] `RedFileSystem.reds:53-55` `FileSystem.GetStorage(name: String) -> ref<FileSystemStorage>` / `GetSharedStorage()`; `:63-70` `FileSystemStorage.Exists / GetFile / GetAsyncFile / DeleteFile`; `:23-37` `File.ReadAsText / ReadAsJson / WriteText / WriteJson`; async variants with `FilePromise` (`:39-44`).

## RedData 0.10.1 (brief)
- [decl] `RedData.reds:4-9` `UUID.Generate() / Equals / IsValid / FromString / ToString`; `RedData.Json.reds:4` `ParseJson(text) -> ref<JsonVariant>`, `:6` `ToJson(object: ref<IScriptable>) -> ref<JsonObject>`; `JsonArray` (:7), `JsonObject` (:39), `JsonVariant` (:59).

## RedLogger 1.4.1 (brief)
- [decl] `RedLogger.reds:4-6` `RedLog.Append(mod: String, line: String)`, `RedLog.AppendLevel(mod, level, line)`; `:7-14` readers (`Mods`, `Files`, `ReadFile`, `CurrentFile`, `...In(source)` variants).

## Audioware 1.9.9
- Provides: audio playback, including sounds tied to entity emitters (turret firing and servo loops would follow the entity).
- [decl] `Ext.reds:11` `public native class AudioSystemExt`; `:13` `Play(eventName, entityID, emitterName, line, ext)`; `:14` `Stop(...)`; `:19` `RegisterEmitter(entityID: EntityID, tagName: CName, opt emitterName: CName, opt emitterSettings: ref<EmitterSettings>) -> Bool`; `:23` `PlayOnEmitter(eventName: CName, entityID: EntityID, tagName: CName, ext: ref<AudioSettingsExt>)`; `:24` `StopOnEmitter`; `:36` `Duration(eventName, ...)`
- Need 2 / 6: not a transform API. Emitter following a moving entity is [unverified].

## Mod Settings 0.2.21
- Provides: native settings menu from annotated script classes.
- [decl] `packed.reds:306-324` `ModSettings.GetInstance()`, `RegisterListenerToClass(self)`, `RegisterListenerToModifications(self)`, ...; `:346-349` **`ModConfigVarKeyBinding { SetValue(value: EInputKey); GetValue() -> EInputKey; GetDefaultValue() }`**; `:364-370` `ModConfigVarFloat` (sensitivity, traverse speed limits).
- `module.reds` only has `GetVersionString()` / `GetVersion()`.
- Need 8: a user-rebindable `EInputKey`, consumed with Codeware `InputTarget.Key(key)` [unverified combo].

## Input Loader 0.2.3
- Provides: merges `r6/input/*.xml` (children of `<bindings>`) into `inputContexts.xml` / `inputUserMappings.xml` (`red4ext\plugins\input_loader\readme.md`). No script API.
- Need 8: define custom actions (e.g. `CM_Fire`, `CM_Exit`) and read them in a wrapped `PlayerPuppet.OnAction` or via `ListenerAction`. [used by XUtils: `XUtils\r6\input\xutils.xml` + `XUtilsInputHooks.reds:13-76`, which wraps `PlayerPuppet.OnAction`, swallows Forward/Back/Left/Right/Jump and weapon-cycle actions while its camera is active (`return true`), and tracks held state.]

## re INPUT Mod Loader - v2.31
- `red4ext\plugins\a_input_loader\a_input_loader.dll` + `engine\config\platform\pc\a_input_loader.ini`; meta version=2.0.0.0. No scripts. Presumably an alternate input-XML loader [unverified]. Not framework-relevant beyond Input Loader.

## Redscript Configuration Framework 3.0.1
- Provides: config hub UI, schema/presets/JSON providers, Mod Settings bridge, RedLogger bridge, and hotkey override natives.
- [decl] `DVRCF_Input.reds:5-17` `RCFInput.SetKeyOverride(name: String, key: Int32) -> Bool`, `ClearKeyOverride(name)`, `Apply() -> Bool`, `IsAvailable()`, `Log(message)`, `LegacyPluginFound()`
- [decl] `DVRCF_InputBridge.reds:60-95` `DVRCF_Hotkeys.PushKey(name, keyInt)` / `PushSchema` / `PushAll(gi)`, plus a Session/Ready callback that pushes keys (`:122-131`).
- Framework-relevant only as an optional config/keybind layer.

## XUtils 1.0.2
- Provides: a CET + redscript toolkit. Scripted camera entity (spawn, activate, FOV, DOF, free-fly), raycast library, particle/FX helpers, native HUD helpers, proximity/lifecycle watchers, math (orbit, interpolation, velocity), input hooks. Native DLL only adds DOF.
- Need 1:
  - [used by XUtils `XUtilsCamera.reds:44-61`] `let spec = new StaticEntitySpec(); spec.templatePath = r"base\\xutils\\entities\\camera_entity.ent"; spec.position = ...; spec.orientation = EulerAngles.ToQuat(euler); spec.attached = true; let entityID = staticSystem.SpawnEntity(spec);`
  - [used by XUtils Lua `Subscription.lua:602`] `WorldFunctionalTests.SpawnEntity(templatePath, transform, '')`. Templates shipped in `XUtils.archive`: `base\xutils\entities\empty_entity.ent`, `camera_entity.ent`, `light.ent`.
  - [used by XUtils Lua `ShapeEntity.lua:65-80`] builds an `entMeshComponent` at runtime and `entity:AddComponent(component)` in the assemble callback.
- Need 2: [used by XUtils `XUtilsCamera.reds:123-156`] builds a `WorldTransform` (`WorldPosition.SetVector4`, `WorldTransform.SetWorldPosition`, `WorldTransform.SetOrientation`) and calls `this.m_entity.SetWorldTransform(wt)` every frame, skipping the call when nothing changed. Driven by CET `registerForEvent("onUpdate")` → `sys:FrameTick(delta)` (`init.lua:473-483`, `XUtilsCameraSystem.reds:1224`).
- Need 4: [used by XUtils `XUtilsCamera.reds:82`] `entity.FindComponentByName(n"camera") as CameraComponent`; `:186` `this.m_component.Activate(blendTime, true)` (the comment says the second argument moves the audio listener to the camera); `:204` `Deactivate(blendTime, true)`; `:216-219` re-activates `player.GetFPPCameraComponent()` and calls `ResetPitch()`; `:255` `SetFOV(fov)`.
- [decl] `XUtilsNative.reds:7-17` `public native func SetDof(intensity, nearBlur, nearFocus, farBlur, farFocus, useNearPlane: Bool, useFarPlane: Bool) -> Bool;` and `public native func ResetDof() -> Bool;` (module `XUtils.Native`)
- Need 6: [used by XUtils `ParticleEffects.reds:93-100`] `GameInstance.GetFxSystem(gi).SpawnEffect(fxRes, wt)` with `fx.effect *= r"base\\fx\\...effect"` (`:134`); `:165` `GameObjectEffectHelper.StartEffectEvent(entity, effectName, false, new worldEffectBlackboard())`; `:172-173` `StopEffectEvent` / `BreakEffectLoopEvent`.
- Need 7: [used by XUtils `XUtilsRaycast.reds:113`] `sq.SyncRaycastByCollisionGroup(rayStart, rayEnd, collisionGroup, result, false, true)`, with the hit read via `Cast<Vector4>(result.position)`. Position only; XUtils never gets the hit entity. Collision group list at `:3-22`. `Target.reds:12-65`: camera-forward raycast (`CameraSystem.GetActiveCameraForward()`), a template for a reticle aim point.
- Need 8: [used by XUtils `XUtilsCameraSystem.reds:128-138, 2138-2158`] Codeware `Input/Axis` for mouse X/Y/Z; `XUtilsInputHooks.reds:13-76` swallows player actions while active.
- Need 9: `Visual\NativeHUDSystem.reds` and `XUtilsNotifications.reds` (HUD hints, progress). Not read in detail.
- Need 10: none (PointCloud "LookAt" is a camera target, not anim).

## PhotoMode-EX 1.4.1
- [decl] `PhotoModeEx.Global.reds:4-6` `PhotoModeEx.Require(version) / Version()`; `PhotoModeEx.reds` has only `CountFracDigits` / `FormatFloat`. Not framework-relevant.

## Doctrine Hydra 1.2.0 (SmartProjectileLauncherNative.dll)
- Provides: arm-launcher "Hydra" smart missiles. Its native DLL only bridges the SmartGun UI payload.
- [decl] `05_native_smart_bridge.reds:1-8` (module `SmartProjectileLauncherSystem`):
  `public native class SmartProjectileLauncherNativeBridge extends IScriptable {`
  `public native func InspectSmartGunParams(params: Variant) -> Void;`
  `public native func AppendSmartGunTarget(params: Variant, entityID: EntityID, pos: Vector2, state: gamesmartGunTargetState, distance: Float, accuracy: Float, isLocked: Bool, timeLocking: Float, timeUnlocking: Float, attachedBoneName: CName) -> Bool;`
  `public native func CreateEmptySmartGunUIParameters() -> Variant;`
  `public native func InspectSmartGunSchema() -> Void;`
  [used by Doctrine Hydra `11_smartlink_vanilla_ui.reds:254-273`, which builds a SmartGun reticle payload and writes it to `UI_ActiveWeaponData.SmartGunParams`]. This could drive a smart-lock reticle for a mech [unverified outside Hydra].
- **Need 5 (projectile launching), [used by Doctrine Hydra `20_volley.reds:110-164`]:**
  ```
  let launchEvent: ref<gameprojectileSpawnerLaunchEvent> = new gameprojectileSpawnerLaunchEvent();
  launchEvent.launchParams.launchMode = gameprojectileELaunchMode.FromLogic;
  launchEvent.launchParams.logicalPositionProvider = ...IPositionProvider...;
  launchEvent.launchParams.logicalOrientationProvider = targetingSystem.GetDefaultCrosshairOrientationProvider(ownerObject, orientation);
  launchEvent.launchParams.visualPositionProvider = ...; launchEvent.launchParams.visualOrientationProvider = ...;
  launchEvent.templateName = projectileTemplateName; launchEvent.appearance = n"None"; launchEvent.owner = ownerObject;
  launchEvent.projectileParams.ignoreMountedVehicleCollision = true;
  launchEvent.projectileParams.trackedTargetComponent = target; launchEvent.projectileParams.targetPosition = targetPosition;
  itemObj.QueueEvent(launchEvent);
  ```
  Position providers (`20_volley.reds:78-107`): `IPositionProvider.CreateSlotPositionProvider(itemObj, n"Muzzle")`, `provider.CalculatePosition(out pos)`, `IPositionProvider.CreateStaticPositionProvider(worldPos)`, `IPositionProvider.CreateEntityPositionProvider(itemObj)`. Also `targetingSystem.GetDefaultCrosshairData(ownerObject, out position, out forward)` (`:68`, `:127`).
  Same pattern [used by Missile Rain `missile_rain.reds:73-98`, template `n"rain_missile_vehicle"`]. The event is queued on an ItemObject whose projectile spawner owns `templateName`. Queuing it on a non-weapon entity with a projectile spawner component is [unverified].
- Records: `r6\tweaks\DoctrineHydra\attacks_and_rounds.yaml` (71 KB) and `items.yaml` hold projectile/attack records you can copy from.

## RedIMGRetriever 0.3.0
- [decl] `RedIMGRetriever.reds:4-30` `RedIMG.PrepareDocImage(url) -> String`, `WithMax`, `GetDocUvWidth/Height`, `GetDocPixelWidth/Height`, `GetDocFrameCount/Delay`, `IsDocFailed`, `ListScreenshots`, `NowMs() -> Float`, `IsAvailable`, `Log`, `ClearCache`. Not framework-relevant (the HUD could show a bitmap).

## TerminalKIT (no meta.ini; version unknown)
- Provides: a redscript terminal-UI framework (TKPopup pages, rows, controls, map), TKHud HUD strips/toasts, and TerminalKitTools dev pages. Requires Codeware + RedFunctions (README).
- Need 9:
  - [decl] `TKHud.reds:79-91` `public abstract class TKHud { static Get() -> ref<TKHudSystem>; static Strip(id: String, width: Float) -> ref<TKHudStrip>; static Toast(kicker, title, line, highlight, text, items, secs, bad) }`
  - [decl] `:58-76` `TKHudStrip.Set(title, right, sub) / Target(pos: Vector4, opt noDistance: Bool) / NoTarget() / Warn(on) / Fraction(f) / Show() / Hide()`
  - [decl] `:232-241` builds the root on `GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer")` → `Reparent(layer.GetVirtualWindow())`; refreshed by a 0.1 s DelayCallback tick (`:21-28`, `:352-366`). Good for a mech status strip (heat, ammo, link); too slow for a reticle.
- Need 1 / 7 (dev tools): [used by TerminalKIT `TKToolsWorld.reds:202-213`] `DynamicEntitySpec` with `recordID`, `appearanceName`, `persistState=false`, `persistSpawn=false`, `alwaysSpawned=true`, `tags`, then `GetDynamicEntitySystem().CreateEntity(spec)`; `:125` `GameInstance.GetTargetingSystem(gi).GetLookAtObject(player)`.

## Cyber Engine Tweaks 1.37.1
- Lua runtime (`bin\x64\plugins\cyber_engine_tweaks.asi`, `version.dll`); no library Lua files ship with it.
- Relevant as a per-frame driver: `registerForEvent("onUpdate", function(delta) ... end)` [used by XUtils `init.lua:473`, which calls into redscript `FrameTick`]. Lua can call Codeware types (`StaticEntitySpec.new()`, `Game.GetStaticEntitySystem()`, `entMeshComponent.new()`) [used by XUtils Lua].

## Anti-Theft Measures / CustomHackingSystem 2.1.2
- Redscript `r6\scripts\CustomHackingSystem\...` (custom breach minigame, ink atlas/progress bars) and Lua `CustomHackingSystem\init.lua` (`CustomHackingSystem:new()`, `IsHackingSystemInstalled()`). It could offer a "hack to take control" entry, but it is not framework-relevant. Only `DelayScriptableSystemRequestNextFrame` usage noted (`CustomHackingSystem.reds:370`).

## Native Interactions Framework 1.1.3
- Lua-only (`nativeInteractions\modules\classes\interactions\*.lua`: workspot interactions like chair, netrunnerChair, teleport). A "sit in the pilot chair" interaction could reuse it; I did not investigate. Not framework-relevant.

## Extra references found (enabled mods, not libraries)
- **Night City Empires** `Security\NCETurretSystem.reds:209-217` [used]: `spec.templatePath = ResRef.FromString("base\\gameplay\\devices\\security_systems\\security_turret\\security_turret_1.ent")` (also `ceiling_turret.ent`, `special\arasaka_nest_ceiling_turret.ent`, `:229-237`) → `CreateEntity(spec)`; `:239-243` `DynamicEntityEvent` Spawned → cast to `SecurityTurret`; `:247-255` friendly via `ps.ActionSetDeviceAttitude()`; `:127` moves the turret with `TeleportationFacility.Teleport(obj, pos, Quaternion.ToEulerAngles(rot))`.
- **Nitrous** `nitro.reds:2076-2082`: `QueryFilter.ALL()` + `SyncRaycastByQueryFilter` + `TraceResult.GetHitEntity`.
- **Gone in 2077 Seconds** `GoneIn2077Seconds_System.reds:707-709`: `sqs.Overlap(box, queryPos, orient, n"Static", overlap)`.
- **Immersive Third Person BOBW** `tpp_camera_headlook.reds:65-94` (LookAtAddEvent fields), `tpp_camera_bridge.reds:1309-1310` (`ApplyFeature(player, n"LookAt", lookAt)`, `ApplyFeature(player, n"ProceduralLean", lean)`); **ITP-TCOC** `ITP-TCOC.reds:55` `AnimationControllerComponent.SetInputFloat(this, n"itp_tcoc_lateral_side", normalized)`. Those graph variables come from the mod's own patched anim graph.
- **General Shadows Fixes** `GeneralShadowsFixes.reds:7157-7160`: runtime `parentTransform.bindName` / `skinning.bindName` rewrite + `LoadAppearance(true)`.
- **RedWindows 2.2.0** `RW_System.reds:705-707, 1145-1146`: RedFunctions mouse hook + input block.
- The project's own existing code (`Controllable Mechs\r6\scripts\ControllableMechs\Pilot\CMPilotGuns.reds:253`) already calls `AIWeapon.Fire(mech, g.weapon, now, 0.0, gamedataTriggerMode.FullAuto, target);` and uses `LookAtAddEvent` (`CMPilotSystem.reds:1231`). That is not a resource and not verified here.
- Disabled, so not usable as references: Appearance Menu Mod, Explosion Knockback and Ragdoll Overhaul, Adam Smasher Encounters.

---

## What unlocks the framework

1. **Spawning the rig (base, yaw part, pitch part, gun), Codeware.** `GameInstance.GetDynamicEntitySystem().CreateEntity(spec: ref<DynamicEntitySpec>) -> EntityID`, with spec fields `recordID | templatePath, appearanceName, position, orientation, persistState, persistSpawn, alwaysSpawned, tags`. Alternatively `GetStaticEntitySystem().SpawnEntity(spec: ref<StaticEntitySpec>)` with `attached = true`. Readiness comes from `RegisterListener(tag, this, n"Fn")` → `DynamicEntityEvent.GetEventType() == Spawned`, or from `CallbackSystem.RegisterCallback(n"Entity/Attached", ...)`.
   - Used by NCE (real `security_turret_1.ent`), TerminalKIT, and XUtils.
2. **Per-frame yaw/pitch by moving whole entities.** `Entity.SetWorldTransform(transform: WorldTransform)` (Codeware `:42171`), fed from `WorldTransform.SetWorldPosition` / `SetOrientation(EulerAngles.ToQuat(...))`.
   - XUtils calls it every frame, driven by CET `onUpdate` → redscript.
   - Fallback: `TeleportationFacility.Teleport(obj, pos, EulerAngles)` (NCE, XUtils).
   - A pure-redscript frame tick is **[proven]** in Controllable Mechs (`DelayEventNextFrame(player, evt)` rescheduled each frame).
3. **Per-part rotation inside one entity.** `IPlacedComponent.SetLocalOrientation(Quaternion)`, used by XUtils on a CameraComponent. Supporting pieces:
   - Codeware fields `IPlacedComponent.localTransform` and `parentTransform: ref<entITransformBinding>`.
   - `entHardTransformBinding { slotName }` plus `entIBinding.bindName`, which parent a component (gun mesh) to another component or its slot/bone (pitch cradle).
   - Runtime rebinding is used by General Shadows Fixes.
   - Runtime `AddComponent` of an `entMeshComponent` with `localTransform` is used by XUtils Lua. Codeware `EntityBuilderWrapper...AddComponent` works at build time.
   - A composite yaw → pitch hierarchy is therefore possible in one entity; binding creation from script is [unverified].
4. **Reticle input.**
   - Codeware `RegisterCallback(n"Input/Axis", this, n"OnAxis").AddTarget(InputTarget.Axis(EInputKey.IK_MouseX)).AddTarget(InputTarget.Axis(EInputKey.IK_MouseY))` → `AxisInputEvent.GetValue()` (used by XUtils). `n"Input/Key"` + `InputTarget.Key(key, action)` covers fire and exit.
   - Or RedFunctions `MouseHook()` + `MouseTakeDeltaX/Y()` + `SetScriptInputBlocked(true)` / `AllowScriptInputFor(this)` (used by RedWindows).
   - Wrapping `PlayerPuppet.OnAction` and returning `true` suppresses on-foot actions (used by XUtils).
5. **Remote camera.** Spawn an entity with a camera component: vanilla `base\entities\cameras\simple_free_camera.ent` **[proven in Controllable Mechs]**, or XUtils' `base\xutils\entities\camera_entity.ent` (needs XUtils). Then:
   - `FindComponentByName(n"camera") as CameraComponent`
   - `.Activate(blendTime, true)`, `.SetFOV(fov)`, `.SetLocalOrientation(q)`
   - `.Deactivate(blendTime, true)`, then `player.GetFPPCameraComponent().Activate(blendTime, true)` and `ResetPitch()`
   - All used by XUtils. Codeware also declares `FreeCameraComponent` and `gameFreeCamera`.
6. **Firing.**
   - `gameprojectileSpawnerLaunchEvent` (launchParams position/orientation providers, `templateName`, `owner`, `projectileParams.targetPosition` / `trackedTargetComponent`) queued via `itemObj.QueueEvent(launchEvent)`. Used by Doctrine Hydra and Missile Rain.
   - Muzzle via `IPositionProvider.CreateSlotPositionProvider(itemObj, n"Muzzle")`.
   - Hitscan or NPC weapons: vanilla `AIWeapon.Fire(...)` **[proven in Controllable Mechs]**. The rounds go to the given point, but the muzzle flash follows the model's barrel.
   - Weapon, attack and projectile records via TweakXL YAML (Hydra's `attacks_and_rounds.yaml` is a template).
7. **Aim-point and target raycast.**
   - `SpatialQueriesSystem.SyncRaycastByQueryFilter(start, end, QueryFilter.ALL(), out TraceResult, false, false)` + Codeware `TraceResult.GetHitEntity(result) -> ref<Entity>`. Used by Nitrous.
   - Or `SyncRaycastByCollisionGroup(start, end, n"Static"|n"AI"|..., out result, false, true)` (XUtils; position only).
   - `CameraSystem.GetActiveCameraForward()` gives the ray direction (XUtils `Target.reds`).
8. **Muzzle flash and impact FX.** `GameInstance.GetFxSystem(gi).SpawnEffect(fx: FxResource, wt: WorldTransform) -> FxInstance`, where `fx.effect *= r"...effect"`; and `GameObjectEffectHelper.StartEffectEvent(entity, n"effectName", false, new worldEffectBlackboard())`. Both used by XUtils.
9. **Appearance and visibility control.**
   - Codeware `IComponent.ChangeAppearance(name, opt wait)`, `ChangeResource(path, opt wait)`, `LoadAppearance`.
   - `MeshComponent.chunkMask: Uint64`, `meshAppearance`, `visualScale`.
   - Vanilla `IComponent.Toggle(Bool)` to hide parts. Used by XUtils and General Shadows Fixes.
   - ArchiveXL/.xl for shipping custom split-mesh turret assets.
10. **HUD.**
    - Codeware `GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer").GetVirtualWindow()`, used by TerminalKIT TKHud (strips/toasts on a 0.1 s tick).
    - Codeware `inkCustomController` / `InGamePopup` for menus.
    - A per-frame reticle widget would reparent under the same layer [unverified].
    - Optional smart-lock reticle via Hydra's `SmartProjectileLauncherNativeBridge.AppendSmartGunTarget(...)` → `UI_ActiveWeaponData.SmartGunParams`.

Animation route (secondary): `AnimFeature_DeviceCameraControlled { currentRotation: Vector4 }` and `animLookAtPreset_DroneHorizontal/Vertical` are declared in Codeware and look like the vanilla device and turret yaw/pitch drivers. You would apply them with `AnimationControllerComponent.ApplyFeature(obj, n"...", feature)` (the ApplyFeature call pattern is used by ITP), or use `LookAtAddEvent.SetStaticTarget(pos)` (used by ITP and Photomode UI Improvements). Whether a spawned `security_turret_1.ent` graph responds to these from script is [unverified].

---

## Credits

This research leans on these resources and their authors' work. They are credited here as references; Controllable Mechs only depends on those listed in the README.
- **Codeware**, **ArchiveXL** and **TweakXL** by psiberx
- **redscript** by jac3km4
- **Cyber Engine Tweaks** by the CET team
- **RedFunctions**, **RedFileSystem**, **RedData**, **RedLogger** and **Audioware**, by their authors
- **Mod Settings** and **Input Loader** by jackhumbert
- **XUtils**, the most useful working reference for cameras, input hooks, FX and raycasts
- **Doctrine Hydra** and **Missile Rain** (projectile launching)
- **Nitrous** (raycast hit entities)
- **Immersive Third Person** (look-at / anim features)
- **General Shadows Fixes** (runtime component bindings)
- **Anti-Theft Measures** (the next-frame tick pattern)
- **Night City Empires** and **TerminalKIT** (Omar), read-only
- **WolvenKit** (the WolvenKit team), including its `soundEvents.json`
