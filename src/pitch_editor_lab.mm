#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#include "pitch_core.hpp"
#include <algorithm>
#include <cmath>
#include <memory>

#import "pitch_canvas.hpp"

@interface LabDelegate : NSObject <NSApplicationDelegate>
@property(strong) NSWindow* window;
@property(strong) PitchCanvas* canvas;
@property(strong) NSTextField* status;
@property(strong) NSButton* openButton;
@end
@implementation LabDelegate
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(160,160,1040,520)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Pitch Editor — Development Lab";
    self.window.minSize = NSMakeSize(650,360);
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSView* root = self.window.contentView;
    self.canvas = [[PitchCanvas alloc] initWithFrame:NSMakeRect(0,36,1040,432)];
    self.canvas.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    [root addSubview:self.canvas];
    NSTextField* title = [NSTextField labelWithString:@"PITCH EDITOR"];
    title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    title.frame = NSMakeRect(18,484,190,18); title.autoresizingMask = NSViewMinYMargin;
    [root addSubview:title];
    NSArray* titles = @[@"Open audio…",@"Undo",@"Redo"];
    SEL actions[] = {@selector(openAudio:),@selector(undo:),@selector(redo:)};
    for (NSUInteger i = 0; i < titles.count; ++i) {
        NSButton* button = [NSButton buttonWithTitle:titles[i] target:self action:actions[i]];
        button.frame = NSMakeRect(720+i*102,478,98,28);
        button.autoresizingMask = NSViewMinXMargin|NSViewMinYMargin;
        [root addSubview:button]; if (!i) self.openButton = button;
    }
    self.status = [NSTextField labelWithString:@"Drag notes vertically • Semitone snap • ⌘Z undo • Audio rendering pending"];
    self.status.frame = NSMakeRect(18,9,1000,18); self.status.autoresizingMask = NSViewWidthSizable;
    self.status.textColor = [NSColor secondaryLabelColor]; self.status.font = [NSFont systemFontOfSize:11];
    [root addSubview:self.status];
    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    if (NSProcessInfo.processInfo.arguments.count > 1)
        [self loadURL:[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[1]]];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender { (void)sender; return YES; }
- (void)undo:(id)sender { (void)sender; [self.canvas undoEdit]; }
- (void)redo:(id)sender { (void)sender; [self.canvas redoEdit]; }
- (void)openAudio:(id)sender {
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) [self loadURL:panel.URL];
    }];
}
- (void)loadURL:(NSURL*)url {
    self.openButton.enabled = NO; self.status.stringValue = @"Analyzing audio…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
            NSError* error = nil;
            AVAudioFile* file = [[AVAudioFile alloc] initForReading:url error:&error];
            NSString* failure = error.localizedDescription;
            std::shared_ptr<pitch::Analysis> result;
            if (file) {
                double sr = file.processingFormat.sampleRate;
                // Bound development-harness memory and quadratic per-frame YIN work.
                if (file.length <= 0 || file.length / sr > 60 || sr > 48000 || file.processingFormat.channelCount > 2) {
                    failure = @"Use a mono/stereo clip up to 60 seconds at 8–48 kHz for this prototype.";
                } else {
                    AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:static_cast<AVAudioFrameCount>(file.length)];
                    if (![file readIntoBuffer:buffer error:&error] || !buffer.floatChannelData) failure = error.localizedDescription ?: @"Could not decode floating-point audio.";
                    else {
                        // Use the channel with the most AC energy, avoiding cancellation
                        // when a stereo recording contains inverted microphone channels.
                        unsigned channel = 0;
                        double best = -1;
                        for (unsigned c = 0; c < buffer.format.channelCount; ++c) {
                            double sum = 0, energy = 0;
                            for (unsigned i = 0; i < buffer.frameLength; ++i) { double v = buffer.floatChannelData[c][i]; sum += v; energy += v*v; }
                            energy -= sum * sum / std::max(1u,buffer.frameLength);
                            if (energy > best) { best = energy; channel = c; }
                        }
                        std::vector<float> mono(buffer.floatChannelData[channel],buffer.floatChannelData[channel]+buffer.frameLength);
                        try { result = std::make_shared<pitch::Analysis>(pitch::analyze(mono,sr)); }
                        catch (const std::exception& e) { failure = [NSString stringWithUTF8String:e.what()]; }
                    }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.openButton.enabled = YES;
                if (result) {
                    auto count = result->notes.size();
                    [self.canvas setAnalysis:std::move(*result)];
                    [self.window makeFirstResponder:self.canvas];
                    self.status.stringValue = [NSString stringWithFormat:@"%@ • %lu notes • Drag to transpose • ⌘Z undo • Audio rendering pending",url.lastPathComponent,static_cast<unsigned long>(count)];
                } else self.status.stringValue = failure ?: @"Unable to analyze audio.";
            });
        }
    });
}
@end

int main(int argc, const char* argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication* app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        LabDelegate* delegate = [LabDelegate new]; app.delegate = delegate;
        NSMenu* menu = [NSMenu new];
        NSMenuItem* application = [NSMenuItem new]; [menu addItem:application];
        NSMenu* applicationMenu = [NSMenu new];
        [applicationMenu addItemWithTitle:@"Quit Pitch Editor Lab" action:@selector(terminate:) keyEquivalent:@"q"];
        application.submenu = applicationMenu;
        NSMenuItem* edit = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
        [menu addItem:edit]; NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
        NSMenuItem* undo = [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"]; undo.target = delegate;
        NSMenuItem* redo = [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"]; redo.target = delegate;
        edit.submenu = editMenu; app.mainMenu = menu;
        [app run];
    }
    return 0;
}
