#import <GameController/GameController.h>
#import <UIKit/UIKit.h>
#include <cstring>

extern "C" int NativeTouchControls_MergeKeys(unsigned char* state);

// Called once per InControl update; copy every physical key independently.
// There is no text-input/repeat event or single-current-key state here.
extern "C" int NativeKeyboard_CopyState(unsigned char* destination, int length)
{
    if (!destination || length < 256) return 0;
    std::memset(destination, 0, 256);
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return 0;
    // On-screen buttons press the same key usages as a hardware keyboard.
    int touch = NativeTouchControls_MergeKeys(destination);
    GCKeyboardInput* input = [GCKeyboard coalescedKeyboard].keyboardInput;
    if (!input) return touch;
    for (int code = 4; code < 232; ++code)
        if ([input buttonForKeyCode:static_cast<GCKeyCode>(code)].pressed) destination[code] = 1;
    return 1;
}
