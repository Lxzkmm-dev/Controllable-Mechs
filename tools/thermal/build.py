# MNC's sensor thermal modes, built from Kiroshi Optics Thermal Vision's effects (by
# permission; credited on Nexus). The original is a full-screen colour grade split by render
# object type: characters through a "hot" lookup table, the world through a "cold" one.
# What changes for a drone or mech sensor:
#   - vehicles read hot (engines), not as part of the cold world
#   - the cold world graded with more contrast, so hot targets stand out sharper
#   - bloom off in every mode (the white-hot one already had it): crisp edges, no glow
#   - everything under mnc\fx\thermal, so it doesn't clash with the original mod
#
# Usage: python build.py <folder of the original effects as WolvenKit JSON> <out folder>
# Writes mnc/fx/thermal/{white,orange,red}.effect.json (deserialize with WolvenKit) and the
# list of lookup tables to copy (original path -> ours) in luts.txt.
import copy, json, os, sys

SRC_LUT = "base\\weather\\24h_basic\\luts\\qc\\thermal_vision\\"
DST_LUT = "mnc\\fx\\thermal\\luts\\"
MODES = {"white": "thermal_vision_white_hot", "orange": "thermal_vision_orange", "red": "thermal_vision_spike"}
HOT = "ROT_Character"
WORLD_CONTRAST = 0.22


def main():
    src, out = sys.argv[1:3]
    os.makedirs(os.path.join(out, "mnc", "fx", "thermal"), exist_ok=True)
    luts = set()
    bloom = None
    white = json.load(open(os.path.join(src, MODES["white"] + ".effect.json"), encoding="utf-8"))
    for ev in white["Data"]["RootChunk"]["events"]:
        if ev["Data"]["$type"] == "effectTrackItemBloom":
            bloom = ev
    for mode, name in MODES.items():
        j = json.load(open(os.path.join(src, name + ".effect.json"), encoding="utf-8"))
        root = j["Data"]["RootChunk"]
        events = root["events"]
        grades = [e for e in events if e["Data"]["$type"] == "effectTrackItemColorGrade"]
        hot = next(e for e in grades if HOT in e["Data"]["mask"])
        world = next(e for e in grades if e is not hot)
        # vehicles are hot
        if "ROT_Vehicle" in world["Data"]["mask"]:
            world["Data"]["mask"].remove("ROT_Vehicle")
        if "ROT_Vehicle" not in hot["Data"]["mask"]:
            hot["Data"]["mask"].append("ROT_Vehicle")
        # the cold world sharper
        world["Data"]["contrast"]["evaluator"]["Data"]["value"] = WORLD_CONTRAST
        # bloom off
        if not any(e["Data"]["$type"] == "effectTrackItemBloom" for e in events) and bloom is not None:
            b = copy.deepcopy(bloom)
            ids = [int(h) for h in json.dumps(j).split('"HandleId": "')[1:] for h in [h.split('"')[0]] if h.isdigit()]
            base = max(ids) + 1 if ids else 100
            b["HandleId"] = str(base)
            b["Data"]["bloomColorScale"]["evaluator"]["HandleId"] = str(base + 1)
            b["Data"]["sceneColorScale"]["evaluator"]["HandleId"] = str(base + 2)
            events.append(b)
        # our own paths for the lookup tables
        for e in grades:
            for key in ("lutParams", "lutParamsHdr"):
                p = e["Data"][key]["LUT"]["DepotPath"]
                if p["$value"].startswith(SRC_LUT):
                    luts.add(p["$value"])
                    p["$value"] = DST_LUT + p["$value"][len(SRC_LUT):]
        j["Header"]["ArchiveFileName"] = "mnc\\fx\\thermal\\" + mode + ".effect"
        json.dump(j, open(os.path.join(out, "mnc", "fx", "thermal", mode + ".effect.json"), "w", encoding="utf-8"), indent=2)
    with open(os.path.join(out, "luts.txt"), "w") as f:
        for l in sorted(luts):
            f.write(l + "\t" + DST_LUT + l[len(SRC_LUT):] + "\n")
    print("modes:", list(MODES), "luts:", len(luts))


if __name__ == "__main__":
    main()
