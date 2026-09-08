#pragma once
#import <Foundation/Foundation.h>
#include "pitch_core.hpp"
#include <memory>

// Control-thread cache; disk writes own immutable snapshots on a serial queue.
@interface PitchDocumentStore : NSObject
- (instancetype)initWithDirectory:(NSString*)directory;
- (std::shared_ptr<pitch::Document>)open:(pitch::Analysis)analysis identity:(NSString*)identity sourceHash:(NSString*)hash;
- (void)save:(std::shared_ptr<pitch::Document>)document identity:(NSString*)identity sourceHash:(NSString*)hash;
- (void)flush;
@property (copy) void (^saveFailed)(NSString* message);
@end
