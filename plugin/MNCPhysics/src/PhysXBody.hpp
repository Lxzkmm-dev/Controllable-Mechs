#pragma once
// MNC Physics v3: per-physics-step control of chosen bodies (gravity, force, torque).
// Scripts only record what they want for a body; a hook on PxScene::simulate applies it
// right before every physics step, the one moment PhysX may be written to.
#include <RED4ext/RED4ext.hpp>

#include <cstdint>

namespace MNC::PhysXBody
{
struct Readback
{
    float vel[3];
    float spin[3];
    int32_t gravity; // 1 on, 0 off, -1 not known yet
    uint32_t steps;  // physics steps this body was driven in
    uint32_t reset;  // steps where its gravity flag had been put back by someone else
};

void Init(RED4ext::v1::PluginHandle aHandle, const RED4ext::v1::Sdk* aSdk);
void EnsureHooked();
bool IsHooked();

// what a script wants for a body (by its proxy id and body index); held until changed,
// dropped 0.3 s after it was last set (the drone stopped asking: let the body go)
bool SetGravity(uint32_t aProxy, uint32_t aIndex, bool aOn);
bool SetForce(uint32_t aProxy, uint32_t aIndex, const float aForce[3], const float aTorque[3]);
void Release(uint32_t aProxy, uint32_t aIndex);
bool GetReadback(uint32_t aProxy, uint32_t aIndex, Readback& aOut);
uint32_t Steps();
} // namespace MNC::PhysXBody
