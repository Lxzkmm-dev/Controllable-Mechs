"""Spike R1 (docs: Research: Drones as Real Rigid Bodies): a plain physics box.

Builds mnc/physics/proxy_box.ent (WolvenKit JSON) from the game's cardboard box prop
(base/items/interactive/containers/int_containers_001__cardboard_box_01_h.ent), which is
a kinematic, rig-mounted prop, into a free rigid body:
  - its rig, animation, slot, targeting and sound components are dropped;
  - its collider becomes the entity's root body: Dynamic, preset "World Dynamic", a box
    shape round the mesh, MASS kg, continuous collision on;
  - its mesh is bound to the collider, so it is drawn wherever the body is.
Only the game's own mesh is referenced (by path); no game asset is copied.

usage: python proxy_box.py <cardboard_box_01_h.ent.json> <out proxy_box.ent.json>
then:  WolvenKit.CLI convert deserialize <out json>  (gives proxy_box.ent)
"""
import copy
import json
import sys

MASS = 20.0
HALF = (0.30, 0.22, 0.20)   # m, the box collider's half extents (the mesh's rough size)
COLLIDER = "proxy_body"
KEEP = ("entMeshComponent", "entColliderComponent")


def cname(v):
    return {"$type": "CName", "$storage": "string", "$value": v}


def bind_to(target):
    return {
        "HandleId": "0",
        "Data": {
            "$type": "entHardTransformBinding",
            "bindName": cname(target),
            "enabled": 1,
            "enableMask": {
                "$type": "entTagMask",
                "excludedTags": {"$type": "redTagList", "tags": [cname("NoBinding")]},
                "hardTags": {"$type": "redTagList", "tags": []},
                "softTags": {"$type": "redTagList", "tags": []},
            },
            "slotName": cname("None"),
        },
    }


def box_collider(src):
    """the sphere collider turned into a box of HALF extents, centred on the body"""
    d = copy.deepcopy(src)
    d["$type"] = "physicsColliderBox"
    d.pop("radius", None)
    d["halfExtents"] = {"$type": "Vector3", "X": HALF[0], "Y": HALF[1], "Z": HALF[2]}
    d["isObstacle"] = 0
    d["localToBody"]["position"].update({"X": 0, "Y": 0, "Z": HALF[2]})
    return d


def fix(comps):
    out = []
    for c in comps:
        t = c.get("$type")
        if t not in KEEP:
            continue
        c = copy.deepcopy(c)
        if t == "entColliderComponent":
            c["name"] = cname(COLLIDER)
            c["parentTransform"] = None
            for col in c["colliders"]:
                if "Data" in col:   # (the inline copy refers to the compiled one's handle)
                    col["Data"] = box_collider(col["Data"])
            c["simulationType"] = "Dynamic"
            c["mass"] = MASS
            c["massOverride"] = -1
            c["useCCD"] = 1
            c["startInactive"] = 0
            if "Data" in c["filterData"]:
                c["filterData"]["Data"]["preset"] = cname("World Dynamic")
        else:
            c["parentTransform"] = bind_to(COLLIDER)
        out.append(c)
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8") as f:
        j = json.load(f)
    root = j["Data"]["RootChunk"]
    root["components"] = fix(root["components"])
    cd = root["compiledData"]["Data"]
    chunks = cd["Chunks"]
    ent = [c for c in chunks if c.get("$type") == "entEntity"]
    cd["Chunks"] = ent + fix(chunks)
    # the chunk table: chunk index -> component id (the entity is "0")
    cd["CruidDict"] = {str(i): (c.get("id", "0") if i else "0") for i, c in enumerate(cd["Chunks"])}
    j["Header"]["ArchiveFileName"] = dst.replace(".json", "")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(j, f, indent=2)
    kinds = [c["$type"] for c in root["compiledData"]["Data"]["Chunks"]]
    print("wrote", dst, "chunks:", kinds)


if __name__ == "__main__":
    main()
