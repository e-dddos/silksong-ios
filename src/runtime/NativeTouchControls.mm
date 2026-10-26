// On-screen touch controls, ported from the Silksong overlay in
// hollow-games-ios-builder. Buttons press the game's default keyboard
// bindings through NativeKeyboard_CopyState; controllers stay native.
#import <UIKit/UIKit.h>
#include <math.h>
#include "NativeTouchState.h"

extern "C" UIView* UnityGetGLView();

static NativeTouchKeys TouchKeys;

// The Options button and the top-row utilities use a rounded outline.
static BOOL UtilityTag(NSInteger tag)
{
    return tag == -101 || tag == 53 || tag == 34 || tag == 1 || tag == 3 || tag == 46;
}

static UIImage* TouchIcon(NSString* name)
{
    if (!name) return nil;
    NSString* file = [@"Data/Raw/native-touch" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    UIImage* image = [UIImage imageWithContentsOfFile:[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:file]];
    if (!image) return nil;
    // Trim the transparent margins of the wide and utility artwork.
    CGRect crop = CGRectMake(0, 0, 1, 1);
    if ([name isEqualToString:@"SuperDash"] || [name isEqualToString:@"QuickCast"]) crop = CGRectMake(.07, .13, .86, .74);
    else if ([name isEqualToString:@"Options"]) crop = CGRectMake(.10, .08, .80, .82);
    else if ([name isEqualToString:@"MapRectFantasy"]) crop = CGRectMake(.15, .16, .70, .70);
    else if ([name isEqualToString:@"InventoryGlyph"]) crop = CGRectMake(.18, .16, .70, .66);
    else if ([name isEqualToString:@"PortOptionsGlyph"]) crop = CGRectMake(.13, .12, .74, .76);
    if (!CGRectEqualToRect(crop, CGRectMake(0, 0, 1, 1))) {
        size_t w = CGImageGetWidth(image.CGImage), h = CGImageGetHeight(image.CGImage);
        CGImageRef clipped = CGImageCreateWithImageInRect(image.CGImage,
            CGRectMake(crop.origin.x * w, crop.origin.y * h, crop.size.width * w, crop.size.height * h));
        if (clipped) {
            image = [UIImage imageWithCGImage:clipped];
            CGImageRelease(clipped);
        }
    }
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@interface NativeTouchButton : UIButton
@end

@implementation NativeTouchButton
- (CGRect)imageRectForContentRect:(CGRect)rect
{
    if (!UtilityTag(self.tag) || !self.currentImage) return [super imageRectForContentRect:rect];
    CGRect box = CGRectInset(rect, 8, 7);
    CGSize size = self.currentImage.size;
    if (size.width <= 0 || size.height <= 0) return box;
    CGFloat scale = MIN(box.size.width / size.width, box.size.height / size.height);
    CGSize fit = CGSizeMake(size.width * scale, size.height * scale);
    return CGRectMake(CGRectGetMidX(box) - fit.width / 2, CGRectGetMidY(box) - fit.height / 2, fit.width, fit.height);
}
@end

@interface NativeTouchControls : UIView
@property(nonatomic, strong) UIView* stick;
@property(nonatomic, strong) UIView* knob;
@property(nonatomic, strong) UITouch* stickTouch;
@property(nonatomic, strong) NSMutableSet<NSNumber*>* touchKeys;
@property(nonatomic, strong) NSMutableSet<NSNumber*>* sentKeys;
@property(nonatomic, strong) NSMutableArray<UIButton*>* buttons;
@property(nonatomic, strong) UIButton* modeButton;
@property(nonatomic) BOOL gameplay, hideOptions, editing;
@property(nonatomic) NSInteger inputMode, layoutMode;
@property(nonatomic, strong) UIView* panel;
@property(nonatomic, strong) NSTimer* statusTimer;
@property(nonatomic, strong) NSMutableDictionary* customLayouts;
@property(nonatomic, strong) NSDictionary* layoutSnapshot;
@property(nonatomic, strong) UIView* editorBar;
@property(nonatomic, strong) UIView* selectedControl;
@property(nonatomic, strong) UILabel* editLabel;
@property(nonatomic, strong) UISlider* sizeSlider;
@property(nonatomic, strong) UISlider* opacitySlider;
@property(nonatomic, strong) UISwitch* visibleSwitch;
@property(nonatomic) CGPoint dragStart;
@end

@implementation NativeTouchControls
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.multipleTouchEnabled = YES;
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    self.customLayouts = [[defaults dictionaryForKey:@"NativeTouchLayouts"] mutableCopy] ?: [NSMutableDictionary new];
    self.gameplay = [defaults boolForKey:@"NativeTouchGameplay"];
    self.hideOptions = [defaults boolForKey:@"NativeTouchHideOptions"];
    self.inputMode = [defaults integerForKey:@"NativeTouchInputMode"] == 1 ? 1 : 0;
    self.layoutMode = MIN(MAX([defaults integerForKey:@"NativeTouchLayout"], 0), 2);
    self.touchKeys = [NSMutableSet new];
    self.sentKeys = [NSMutableSet new];
    self.buttons = [NSMutableArray new];

    self.stick = [[UIImageView alloc] initWithImage:TouchIcon(@"Ring")];
    self.stick.tag = -100;
    self.stick.accessibilityLabel = @"Movement joystick";
    self.stick.tintColor = UIColor.whiteColor;
    self.stick.userInteractionEnabled = NO;
    [self addSubview:self.stick];
    self.knob = [[UIImageView alloc] initWithImage:TouchIcon(@"Knob")];
    self.knob.tintColor = UIColor.whiteColor;
    self.knob.bounds = CGRectMake(0, 0, 34, 34);
    [self.stick addSubview:self.knob];
    [self installEditGestures:self.stick];

    NSArray* titles = @[@"OK", @"Pause / Back", @"Jump", @"Attack", @"Dash", @"Bind", @"Inventory",
                        @"Harpoon", @"Skill / Tool", @"Needolin", @"Challenge", @"Map (hold)"];
    NSArray* codes = @[@36, @53, @6, @7, @8, @0, @34, @1, @3, @2, @9, @46];
    NSDictionary* icons = @{@53: @"Options", @6: @"Jump", @7: @"Attack", @8: @"Dash", @0: @"Cast",
                            @34: @"InventoryGlyph", @1: @"SuperDash", @3: @"QuickCast", @2: @"DreamNail",
                            @9: @"Taunt", @46: @"MapRectFantasy"};
    for (NSUInteger i = 0; i < codes.count; i++) {
        UIButton* button = [[NativeTouchButton alloc] initWithFrame:CGRectZero];
        button.tag = [codes[i] integerValue];
        button.accessibilityLabel = titles[i];
        button.tintColor = UIColor.whiteColor;
        UIImage* image = TouchIcon(icons[codes[i]]);
        if (image) {
            [button setImage:image forState:UIControlStateNormal];
            button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        } else {
            [button setTitle:titles[i] forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            button.layer.borderWidth = 1;
            button.layer.borderColor = UIColor.whiteColor.CGColor;
            button.layer.cornerRadius = 8;
        }
        [button addTarget:self action:@selector(down:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(up:)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self installEditGestures:button];
        [self.buttons addObject:button];
        [self addSubview:button];
    }

    self.modeButton = [[NativeTouchButton alloc] initWithFrame:CGRectZero];
    [self.modeButton setImage:TouchIcon(@"PortOptionsGlyph") forState:UIControlStateNormal];
    self.modeButton.tintColor = UIColor.whiteColor;
    self.modeButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.modeButton.backgroundColor = UIColor.clearColor;
    self.modeButton.layer.cornerRadius = 12;
    self.modeButton.layer.borderWidth = 1.25;
    self.modeButton.layer.borderColor = UIColor.whiteColor.CGColor;
    [self.modeButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    self.modeButton.tag = -101;
    self.modeButton.accessibilityLabel = @"Touch Controls";
    [self installEditGestures:self.modeButton];
    [self addSubview:self.modeButton];

    // A hidden Options button reappears while it is touched or its panel is open.
    __weak NativeTouchControls* weakSelf = self;
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer* timer) {
        NativeTouchControls* view = weakSelf;
        if (!view) { [timer invalidate]; return; }
        if (view.editing) return;
        NSDictionary* entry = view.customLayouts[[view layoutKey:view.modeButton]];
        view.modeButton.alpha = view.hideOptions && !view.panel ? .02 : (entry[@"alpha"] ? [entry[@"alpha"] doubleValue] : .65);
    }];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(releaseAll)
        name:UIApplicationWillResignActiveNotification object:nil];
    return self;
}

- (void)dealloc
{
    [self.statusTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark Input

- (void)sync
{
    for (NSNumber* key in self.sentKeys)
        if (![self.touchKeys containsObject:key]) TouchKeys.Set(key.intValue, false);
    for (NSNumber* key in self.touchKeys)
        if (![self.sentKeys containsObject:key]) TouchKeys.Set(key.intValue, true);
    self.sentKeys = [self.touchKeys mutableCopy];
}

- (void)releaseAll
{
    [self.touchKeys removeAllObjects];
    [self sync];
    self.stickTouch = nil;
    self.knob.center = CGPointMake(self.stick.bounds.size.width / 2, self.stick.bounds.size.height / 2);
}

// Keep tag 46 as the saved-layout identity; its action is quick map (Tab).
- (NSInteger)keyForButton:(UIButton*)button { return button.tag == 46 ? 48 : button.tag; }

- (void)down:(UIButton*)button
{
    if (self.editing) return;
    [self.touchKeys addObject:@([self keyForButton:button])];
    [self sync];
}

- (void)up:(UIButton*)button
{
    if (self.editing) return;
    [self.touchKeys removeObject:@([self keyForButton:button])];
    [self sync];
}

- (void)moveStick:(UITouch*)touch
{
    CGPoint p = [touch locationInView:self.stick];
    CGFloat mid = self.stick.bounds.size.width / 2;
    CGFloat x = (p.x - mid) / (mid * .82), y = (p.y - mid) / (mid * .82), d = hypot(x, y);
    if (d > 1) { x /= d; y /= d; }
    self.knob.center = CGPointMake(mid + x * mid * .65, mid + y * mid * .65);
    for (NSNumber* key in @[@123, @124, @125, @126]) [self.touchKeys removeObject:key];
    if (x < -.3) [self.touchKeys addObject:@123];
    if (x > .3) [self.touchKeys addObject:@124];
    if (y < -.3) [self.touchKeys addObject:@126];
    if (y > .3) [self.touchKeys addObject:@125];
    [self sync];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    if (self.editing || self.stickTouch) return;
    for (UITouch* touch in touches)
        if (CGRectContainsPoint(CGRectInset(self.stick.frame, -15, -15), [touch locationInView:self])) {
            self.stickTouch = touch;
            [self moveStick:touch];
            break;
        }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    if (self.stickTouch && [touches containsObject:self.stickTouch]) [self moveStick:self.stickTouch];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    if (!self.stickTouch || ![touches containsObject:self.stickTouch]) return;
    self.stickTouch = nil;
    for (NSNumber* key in @[@123, @124, @125, @126]) [self.touchKeys removeObject:key];
    self.knob.center = CGPointMake(self.stick.bounds.size.width / 2, self.stick.bounds.size.height / 2);
    [self sync];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self touchesEnded:touches withEvent:event]; }

// Touches outside the controls fall through to Unity's own view.
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event
{
    if (!self.editing && CGRectContainsPoint(self.modeButton.frame, point) && self.modeButton.alpha < .1) {
        self.modeButton.alpha = 1;
        return self.modeButton;
    }
    UIView* view = [super hitTest:point withEvent:event];
    if (view != self) return view;
    if (self.panel) return self.panel;
    if (self.editing) return self;
    return !self.stick.hidden && CGRectContainsPoint(CGRectInset(self.stick.frame, -15, -15), point) ? self : nil;
}

#pragma mark Settings

- (void)saveSettings
{
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:self.gameplay forKey:@"NativeTouchGameplay"];
    [defaults setBool:self.hideOptions forKey:@"NativeTouchHideOptions"];
    [defaults setInteger:self.inputMode forKey:@"NativeTouchInputMode"];
    [defaults setInteger:self.layoutMode forKey:@"NativeTouchLayout"];
    [self setNeedsLayout];
}

- (void)changed:(UIControl*)control
{
    [self releaseAll];
    switch (control.tag) {
        case 100: self.inputMode = ((UISegmentedControl*)control).selectedSegmentIndex; break;
        case 101: self.layoutMode = ((UISegmentedControl*)control).selectedSegmentIndex; break;
        case 102: self.gameplay = ((UISegmentedControl*)control).selectedSegmentIndex == 1; break;
        case 103: self.hideOptions = ((UISwitch*)control).on; break;
    }
    [self saveSettings];
}

- (void)closeSettings
{
    [self.panel removeFromSuperview];
    self.panel = nil;
    [self releaseAll];
    [self setNeedsLayout];
}

- (void)addLabel:(NSString*)text stack:(UIStackView*)stack
{
    UILabel* label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:14];
    [stack addArrangedSubview:label];
}

- (void)showSettings
{
    if (self.editing) return;
    [self releaseAll];
    if (self.panel) { [self closeSettings]; return; }
    self.modeButton.alpha = 1;
    self.panel = [UIView new];
    self.panel.backgroundColor = [UIColor colorWithWhite:.07 alpha:.98];
    self.panel.layer.cornerRadius = 18;
    self.panel.frame = CGRectInset(self.bounds, MAX(20, self.safeAreaInsets.left + 10), 12);
    [self addSubview:self.panel];
    UIScrollView* scroll = [[UIScrollView alloc] initWithFrame:self.panel.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:scroll];
    UIStackView* stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 11;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]]];
    [self addLabel:@"Silksong • Touch Controls" stack:stack];
    NSArray* labels = @[@"Input", @"Button layout", @"Controls", @"Hide Options button"];
    NSArray* segments = @[@[@"Touch + controller", @"Controller only"], @[@"Right hand", @"Left hand", @"Compact"], @[@"Menu", @"Play"]];
    NSArray* selected = @[@(self.inputMode), @(self.layoutMode), @(self.gameplay ? 1 : 0)];
    for (NSInteger i = 0; i < (NSInteger)labels.count; i++) {
        [self addLabel:labels[i] stack:stack];
        UIControl* control;
        if (i < (NSInteger)segments.count) {
            UISegmentedControl* choice = [[UISegmentedControl alloc] initWithItems:segments[i]];
            choice.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
            choice.selectedSegmentIndex = [selected[i] integerValue];
            control = choice;
        } else {
            UISwitch* toggle = [UISwitch new];
            toggle.on = self.hideOptions;
            control = toggle;
        }
        control.tag = 100 + i;
        [control addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
        [stack addArrangedSubview:control];
    }
    UIButton* edit = [UIButton buttonWithType:UIButtonTypeSystem];
    [edit setTitle:@"Customize button positions, size & opacity" forState:UIControlStateNormal];
    [edit addTarget:self action:@selector(beginEditing) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:edit];
    [self addLabel:@"Tap the Options spot to reopen a hidden button. Switch Menu/Play controls here. "
                   "Hold Map after obtaining a map in the game. Touch buttons press the default keyboard keys, "
                   "so keep the game's default keyboard bindings. Controllers and keyboards work alongside touch."
             stack:stack];
    UIButton* done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    [done addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:done];
    [self setNeedsLayout];
}

#pragma mark Layout editor

- (CGFloat)normalBorder:(UIView*)view { return UtilityTag(view.tag) ? 1.25 : view.tag == 36 ? 1 : 0; }

- (NSString*)layoutKey:(UIView*)view
{
    return [NSString stringWithFormat:@"%ld.%@.%ld", (long)self.layoutMode, self.gameplay ? @"play" : @"menu", (long)view.tag];
}

- (void)applyCustom:(UIView*)view
{
    NSDictionary* d = self.customLayouts[[self layoutKey:view]];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height, m = MIN(W, H);
    if (d && W > 0 && H > 0) {
        CGFloat w = MAX(24, MIN(W, [d[@"w"] doubleValue] * m)), h = MAX(24, MIN(H, [d[@"h"] doubleValue] * m));
        CGFloat x = MAX(w / 2, MIN(W - w / 2, [d[@"x"] doubleValue] * W)), y = MAX(h / 2, MIN(H - h / 2, [d[@"y"] doubleValue] * H));
        view.bounds = CGRectMake(0, 0, w, h);
        view.center = CGPointMake(x, y);
    }
    CGFloat alpha = d[@"alpha"] ? MAX(.15, MIN(1, [d[@"alpha"] doubleValue])) : .65;
    view.alpha = self.editing ? MAX(.4, alpha) : alpha;
    if (view != self.modeButton && [d[@"hidden"] boolValue]) {
        if (!self.editing) view.hidden = YES;
        else if (!view.hidden) view.alpha = .25;
    }
    if (self.editing && view == self.selectedControl) {
        view.layer.borderWidth = 2;
        view.layer.borderColor = UIColor.systemCyanColor.CGColor;
    }
}

- (void)storeCustom:(UIView*)view
{
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height, m = MIN(W, H);
    if (m <= 0) return;
    NSMutableDictionary* d = [self.customLayouts[[self layoutKey:view]] mutableCopy] ?: [NSMutableDictionary new];
    d[@"x"] = @(view.center.x / W);
    d[@"y"] = @(view.center.y / H);
    d[@"w"] = @(view.bounds.size.width / m);
    d[@"h"] = @(view.bounds.size.height / m);
    if (!d[@"alpha"]) d[@"alpha"] = @.65;
    self.customLayouts[[self layoutKey:view]] = d;
}

- (void)installEditGestures:(UIView*)view
{
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragControl:)];
    pan.enabled = NO;
    pan.maximumNumberOfTouches = 1;
    [view addGestureRecognizer:pan];
    UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(selectControl:)];
    tap.enabled = NO;
    [tap requireGestureRecognizerToFail:pan];
    [view addGestureRecognizer:tap];
}

- (NSArray<UIView*>*)editableControls
{
    NSMutableArray* controls = [self.buttons mutableCopy];
    [controls addObjectsFromArray:@[self.stick, self.modeButton]];
    return controls;
}

- (void)selectView:(UIView*)view
{
    if (self.selectedControl) {
        self.selectedControl.layer.borderWidth = [self normalBorder:self.selectedControl];
        self.selectedControl.layer.borderColor = UIColor.whiteColor.CGColor;
    }
    self.selectedControl = view;
    view.layer.borderWidth = 2;
    view.layer.borderColor = UIColor.systemCyanColor.CGColor;
    self.editLabel.text = view.accessibilityLabel ?: @"Control";
    self.sizeSlider.value = view.bounds.size.width;
    NSDictionary* d = self.customLayouts[[self layoutKey:view]];
    self.opacitySlider.value = d[@"alpha"] ? [d[@"alpha"] floatValue] : .65;
    self.visibleSwitch.on = view == self.modeButton ? YES : ![d[@"hidden"] boolValue];
    self.visibleSwitch.enabled = view != self.modeButton;
}

- (void)selectControl:(UITapGestureRecognizer*)gesture
{
    if (self.editing) [self selectView:gesture.view];
}

- (void)dragControl:(UIPanGestureRecognizer*)gesture
{
    if (!self.editing) return;
    UIView* view = gesture.view;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self selectView:view];
        self.dragStart = view.center;
    }
    CGPoint d = [gesture translationInView:self];
    CGFloat w = view.bounds.size.width, h = view.bounds.size.height;
    view.center = CGPointMake(MAX(w / 2, MIN(self.bounds.size.width - w / 2, self.dragStart.x + d.x)),
                              MAX(h / 2, MIN(self.bounds.size.height - h / 2, self.dragStart.y + d.y)));
    [self storeCustom:view];
}

- (void)editValueChanged:(UIControl*)control
{
    UIView* view = self.selectedControl;
    if (!view) return;
    [self storeCustom:view];
    if (control == self.sizeSlider) {
        CGFloat aspect = view.bounds.size.height / MAX(1, view.bounds.size.width), w = self.sizeSlider.value;
        view.bounds = CGRectMake(0, 0, w, w * aspect);
        [self storeCustom:view];
    }
    NSMutableDictionary* d = [self.customLayouts[[self layoutKey:view]] mutableCopy];
    if (control == self.opacitySlider) d[@"alpha"] = @(self.opacitySlider.value);
    if (control == self.visibleSwitch) d[@"hidden"] = @(!self.visibleSwitch.on);
    self.customLayouts[[self layoutKey:view]] = d;
    [self setNeedsLayout];
}

- (UIButton*)editorButton:(NSString*)title action:(SEL)action
{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)beginEditing
{
    [self closeSettings];
    [self releaseAll];
    self.layoutSnapshot = [self.customLayouts copy];
    self.editing = YES;
    for (UIView* view in [self editableControls])
        for (UIGestureRecognizer* gesture in view.gestureRecognizers) gesture.enabled = YES;
    self.editorBar = [UIView new];
    self.editorBar.backgroundColor = [UIColor colorWithWhite:.04 alpha:.94];
    self.editorBar.layer.cornerRadius = 12;
    [self addSubview:self.editorBar];
    UIStackView* stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.editorBar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.editorBar.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:self.editorBar.trailingAnchor constant:-10],
        [stack.topAnchor constraintEqualToAnchor:self.editorBar.topAnchor constant:6],
        [stack.bottomAnchor constraintEqualToAnchor:self.editorBar.bottomAnchor constant:-6]]];
    UIStackView* top = [UIStackView new];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.spacing = 10;
    self.editLabel = [UILabel new];
    self.editLabel.text = @"Drag a control • tap to select";
    self.editLabel.textColor = UIColor.whiteColor;
    self.editLabel.font = [UIFont systemFontOfSize:12];
    [top addArrangedSubview:self.editLabel];
    [top addArrangedSubview:[self editorButton:@"Reset" action:@selector(resetEditingLayout)]];
    [top addArrangedSubview:[self editorButton:@"Cancel" action:@selector(cancelEditing)]];
    [top addArrangedSubview:[self editorButton:@"Save" action:@selector(saveEditing)]];
    [stack addArrangedSubview:top];
    for (int i = 0; i < 2; i++) {
        UIStackView* row = [UIStackView new];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 8;
        UILabel* label = [UILabel new];
        label.text = i ? @"Opacity" : @"Size";
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont systemFontOfSize:12];
        [label.widthAnchor constraintEqualToConstant:48].active = YES;
        [row addArrangedSubview:label];
        UISlider* slider = [UISlider new];
        slider.minimumValue = i ? .15 : 30;
        slider.maximumValue = i ? 1 : 230;
        [slider addTarget:self action:@selector(editValueChanged:) forControlEvents:UIControlEventValueChanged];
        [row addArrangedSubview:slider];
        if (i) {
            self.opacitySlider = slider;
            UILabel* visible = [UILabel new];
            visible.text = @"Visible";
            visible.font = [UIFont systemFontOfSize:12];
            visible.textColor = UIColor.whiteColor;
            [row addArrangedSubview:visible];
            self.visibleSwitch = [UISwitch new];
            [self.visibleSwitch addTarget:self action:@selector(editValueChanged:) forControlEvents:UIControlEventValueChanged];
            [row addArrangedSubview:self.visibleSwitch];
        } else self.sizeSlider = slider;
        [stack addArrangedSubview:row];
    }
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self selectView:self.stick];
}

- (void)finishEditing
{
    self.editing = NO;
    [self releaseAll];
    if (self.selectedControl) {
        self.selectedControl.layer.borderWidth = [self normalBorder:self.selectedControl];
        self.selectedControl.layer.borderColor = UIColor.whiteColor.CGColor;
    }
    self.selectedControl = nil;
    for (UIView* view in [self editableControls])
        for (UIGestureRecognizer* gesture in view.gestureRecognizers) gesture.enabled = NO;
    [self.editorBar removeFromSuperview];
    self.editorBar = nil;
    self.layoutSnapshot = nil;
    [self setNeedsLayout];
}

- (void)saveEditing
{
    [NSUserDefaults.standardUserDefaults setObject:self.customLayouts forKey:@"NativeTouchLayouts"];
    [self finishEditing];
}

- (void)cancelEditing
{
    self.customLayouts = [self.layoutSnapshot mutableCopy] ?: [NSMutableDictionary new];
    [self finishEditing];
}

- (void)resetEditingLayout
{
    NSString* prefix = [NSString stringWithFormat:@"%ld.%@.", (long)self.layoutMode, self.gameplay ? @"play" : @"menu"];
    for (NSString* key in [self.customLayouts.allKeys copy])
        if ([key hasPrefix:prefix]) [self.customLayouts removeObjectForKey:key];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    if (self.selectedControl) [self selectView:self.selectedControl];
}

#pragma mark Layout

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat l = MAX(16, self.safeAreaInsets.left + 8), r = self.bounds.size.width - MAX(16, self.safeAreaInsets.right + 8);
    CGFloat h = self.bounds.size.height, b = MAX(14, self.safeAreaInsets.bottom + 8), t = MAX(10, self.safeAreaInsets.top + 6);
    CGFloat u = self.layoutMode == 2 ? .82 : 1;
    BOOL touchHidden = self.inputMode == 1 && !self.editing;
    self.stick.hidden = NO;
    self.modeButton.hidden = NO;
    self.stick.frame = CGRectMake(l + 16, h - b - 114, 90, 90);
    self.modeButton.frame = CGRectMake(l + 212, t + 36, 100, 52);
    for (UIButton* view in self.buttons) {
        view.hidden = !self.gameplay;
        CGFloat x = 0, y = 0, w = 64, ht = 64;
        switch (view.tag) {
            case 36: x = r - 76; y = h - b - 68; w = 76; ht = 62; view.hidden = self.gameplay; break;
            case 53: x = r - 100; y = t + 36; w = 100; ht = 52; view.hidden = NO; break;
            case 6: x = r - 125; y = h - b - 160; break;
            case 7: x = r - 125; y = h - b - 90; break;
            case 8: x = r - 58; y = h - b - 119; break;
            case 0: x = r - 58; y = h - b - 188; break;
            case 2: x = r - 192; y = h - b - 135; break;
            case 9: x = r - 192; y = h - b - 65; break;
            case 1: x = l; y = t + 36; w = 100; ht = 52; break;
            case 3: x = r - 312; y = t + 36; w = 100; ht = 52; break;
            case 46: x = r - 206; y = t + 36; w = 100; ht = 52; break;
            case 34: x = l + 106; y = t + 36; w = 100; ht = 52; break;
        }
        if (self.layoutMode == 2 && !UtilityTag(view.tag)) {
            x = r - (r - x) * u;
            y = h - b - (h - b - y) * u;
            w *= u;
            ht *= u;
        }
        view.frame = CGRectMake(x, y, w, ht);
        if (self.layoutMode == 1) {
            CGRect f = view.frame;
            f.origin.x = self.bounds.size.width - CGRectGetMaxX(f);
            view.frame = f;
        }
        if (UtilityTag(view.tag)) {
            view.layer.borderWidth = 1.25;
            view.layer.borderColor = UIColor.whiteColor.CGColor;
            view.layer.cornerRadius = 12;
        }
        [self applyCustom:view];
        if (touchHidden) view.hidden = YES;
    }
    if (self.layoutMode == 1) {
        for (UIView* view in @[self.stick, self.modeButton]) {
            CGRect f = view.frame;
            f.origin.x = self.bounds.size.width - CGRectGetMaxX(f);
            view.frame = f;
        }
    }
    self.modeButton.layer.borderWidth = 1.25;
    self.modeButton.layer.borderColor = UIColor.whiteColor.CGColor;
    [self applyCustom:self.stick];
    [self applyCustom:self.modeButton];
    if (touchHidden) self.stick.hidden = YES;
    self.stick.userInteractionEnabled = self.editing;
    if (!self.stickTouch) {
        CGFloat z = self.stick.bounds.size.width;
        self.knob.bounds = CGRectMake(0, 0, z * .32, z * .32);
        self.knob.center = CGPointMake(z / 2, self.stick.bounds.size.height / 2);
    }
    if (self.panel) {
        self.panel.frame = CGRectInset(self.bounds, MAX(20, self.safeAreaInsets.left + 10), 12);
        [self bringSubviewToFront:self.panel];
    }
    if (self.editorBar) {
        CGFloat w = MIN(500, self.bounds.size.width - self.safeAreaInsets.left - self.safeAreaInsets.right - 24);
        self.editorBar.frame = CGRectMake((self.bounds.size.width - w) / 2, h - 116 - MAX(8, self.safeAreaInsets.bottom), w, 116);
        [self bringSubviewToFront:self.editorBar];
    }
}
@end

static NativeTouchControls* Overlay;

// Called once the original Loader owns the game, after the startup notice.
extern "C" void NativeTouchControls_Install()
{
    if (Overlay) return;
    UIView* host = UnityGetGLView();
    if (!host) return;
    Overlay = [[NativeTouchControls alloc] initWithFrame:host.bounds];
    [host addSubview:Overlay];
}

// Adds held touch buttons to the keyboard state; 0 when touch is off.
extern "C" int NativeTouchControls_MergeKeys(unsigned char* state)
{
    if (!Overlay || Overlay.inputMode == 1) return 0;
    TouchKeys.Merge(state);
    return 1;
}
