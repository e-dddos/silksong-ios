#include "../src/runtime/NativeTouchState.h"
#include <cassert>
#include <cstring>
#include <iostream>

int main()
{
    // Default desktop bindings, as USB HID usages read by NativeKeyState.
    assert(NativeTouchUsage(6) == 29);   // Z
    assert(NativeTouchUsage(36) == 40);  // Return
    assert(NativeTouchUsage(48) == 43);  // Tab
    assert(NativeTouchUsage(53) == 41);  // Escape
    assert(NativeTouchUsage(123) == 80 && NativeTouchUsage(124) == 79);
    assert(NativeTouchUsage(125) == 81 && NativeTouchUsage(126) == 82);
    assert(NativeTouchUsage(46) == 16);  // Layout identity only; the button sends Tab.
    assert(NativeTouchUsage(999) == 0);

    NativeTouchKeys keys;
    unsigned char state[256];
    std::memset(state, 0, sizeof(state));
    keys.Set(6, true);
    keys.Set(6, false);
    keys.Merge(state);
    assert(state[29] == 1); // Tap between two Unity updates is delivered once.
    std::memset(state, 0, sizeof(state));
    keys.Merge(state);
    assert(state[29] == 0);

    keys.Set(123, true);
    keys.Merge(state);
    keys.Merge(state);
    assert(state[80] == 1); // Held stick direction stays pressed.
    std::memset(state, 0, sizeof(state));
    keys.Set(123, false);
    keys.Merge(state);
    assert(state[80] == 0);

    state[4] = 1; // A hardware key already copied is preserved.
    keys.Set(36, true);
    keys.Merge(state);
    assert(state[4] == 1 && state[40] == 1);

    keys.Set(999, true); // Unknown identities are ignored.
    keys.Clear();
    std::memset(state, 0, sizeof(state));
    keys.Merge(state);
    for (unsigned char value : state) assert(value == 0);
    std::cout << "touch state tests passed\n";
    return 0;
}
