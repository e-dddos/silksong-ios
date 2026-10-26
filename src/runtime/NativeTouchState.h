#pragma once
#include <bitset>

// On-screen buttons keep the macOS virtual-key identities of the original
// overlay; the game reads USB HID usages, the same table as GCKeyboard.
inline int NativeTouchUsage(int macKey)
{
    switch (macKey)
    {
        case 0: return 4;    // A: Bind
        case 1: return 22;   // S: Harpoon
        case 2: return 7;    // D: Needolin
        case 3: return 9;    // F: Skill / Tool
        case 6: return 29;   // Z: Jump
        case 7: return 27;   // X: Attack
        case 8: return 6;    // C: Dash
        case 9: return 25;   // V: Challenge
        case 34: return 12;  // I: Inventory
        case 36: return 40;  // Return: OK
        case 46: return 16;  // M: Map
        case 48: return 43;  // Tab: Quick map
        case 53: return 41;  // Escape: Pause / Back
        case 123: return 80; // Left
        case 124: return 79; // Right
        case 125: return 81; // Down
        case 126: return 82; // Up
        default: return 0;
    }
}

// Keep a tap that begins and ends between two Unity updates. A held button
// remains pressed; a short tap produces one pressed frame. UIKit and Unity
// both run on the main thread, so no atomics are needed.
class NativeTouchKeys
{
    std::bitset<256> held, pending;
public:
    void Set(int macKey, bool pressed)
    {
        int usage = NativeTouchUsage(macKey);
        if (!usage) return;
        if (pressed && !held[usage]) pending[usage] = true;
        held[usage] = pressed;
    }
    void Merge(unsigned char* state)
    {
        std::bitset<256> keys = held | pending;
        pending.reset();
        for (int usage = 0; usage < 256; ++usage)
            if (keys[usage]) state[usage] = 1;
    }
    void Clear() { held.reset(); pending.reset(); }
};
