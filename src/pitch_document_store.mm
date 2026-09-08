#import "pitch_document_store.hpp"
#import <CommonCrypto/CommonDigest.h>
#include <cmath>
#include <map>
#include <set>
#include <string>

static NSString *keyFor(NSString *identity,NSString *hash){return [identity stringByAppendingFormat:@":%@",hash];}
static NSString *filename(NSString *key){
    NSData *bytes=[key dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,digest);NSMutableString *s=[NSMutableString new];
    for(auto byte:digest)[s appendFormat:@"%02x",byte];return [s stringByAppendingString:@".json"];
}
@implementation PitchDocumentStore {
    NSString *directory;
    dispatch_queue_t writer;
    std::map<std::string,std::shared_ptr<pitch::Document>> documents;
}
- (instancetype)initWithDirectory:(NSString*)path {
    if((self=[super init])){directory=[path copy];writer=dispatch_queue_create("pitch.documents",DISPATCH_QUEUE_SERIAL);}return self;
}
- (std::shared_ptr<pitch::Document>)open:(pitch::Analysis)analysis identity:(NSString*)identity sourceHash:(NSString*)hash {
    NSString *key=keyFor(identity,hash);auto cached=documents.find(key.UTF8String);
    if(cached!=documents.end())return cached->second;
    NSString *path=[directory stringByAppendingPathComponent:filename(key)];
    NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSData *bytes=[attributes fileSize]<=2*1024*1024?[NSData dataWithContentsOfFile:path]:nil;
    id value=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;
    if([value isKindOfClass:NSDictionary.class]&&([value[@"schema"] isEqual:@1]||[value[@"schema"] isEqual:@2]||[value[@"schema"] isEqual:@3]||[value[@"schema"] isEqual:@4])&&[value[@"identity"] isEqual:identity]&&[value[@"sourceHash"] isEqual:hash]&&[value[@"notes"] isKindOfClass:NSArray.class]){
        std::vector<pitch::Note> restored;std::set<std::size_t> ids;bool valid=[value[@"notes"] count]<=10000;
        double end=0;
        for(id row in value[@"notes"]){
            if(!valid||![row isKindOfClass:NSArray.class]||[row count]!=([value[@"schema"] isEqual:@4]?9:[value[@"schema"] isEqual:@3]?7:[value[@"schema"] isEqual:@2]?6:5)){valid=false;break;}
            for(id number in row)if(![number isKindOfClass:NSNumber.class]||!std::isfinite([number doubleValue]))valid=false;
            if(!valid)break;
            double idValue=[row[0] doubleValue];
            if(idValue<0||idValue>1e9||std::floor(idValue)!=idValue){valid=false;break;}
            pitch::Note n{(std::size_t)idValue,[row[1] doubleValue],[row[2] doubleValue],[row[3] doubleValue],[row[4] doubleValue]};
            n.gainDb=[row count]>=6?[row[5] doubleValue]:0;
            n.vibrato=[row count]>=7?[row[6] doubleValue]:1;
            n.driftStart=[row count]==9?[row[7] doubleValue]:0;n.driftEnd=[row count]==9?[row[8] doubleValue]:0;
            if(std::abs(n.driftStart)>200||std::abs(n.driftEnd)>200||n.vibrato<0||n.vibrato>1||n.gainDb < -24||n.gainDb > 12||n.start<end||n.end<=n.start||n.end>analysis.duration+1e-6||n.originalMidi<0||n.originalMidi>127||std::abs(n.semitones)>24||!ids.insert(n.id).second){valid=false;break;}
            restored.push_back(n);end=n.end;
        }
        if(valid)analysis.notes=std::move(restored);
    }
    auto result=std::make_shared<pitch::Document>(std::move(analysis));documents[key.UTF8String]=result;return result;
}
- (void)save:(std::shared_ptr<pitch::Document>)document identity:(NSString*)identity sourceHash:(NSString*)hash {
    NSString *key=keyFor(identity,hash);documents[key.UTF8String]=document;
    NSMutableArray *rows=[NSMutableArray new];
    for(const auto& n:document->analysis().notes)[rows addObject:@[@(n.id),@(n.start),@(n.end),@(n.originalMidi),@(n.semitones),@(n.gainDb),@(n.vibrato),@(n.driftStart),@(n.driftEnd)]];
    NSDictionary *snapshot=@{@"schema":@4,@"identity":identity,@"sourceHash":hash,@"notes":rows};
    NSString *path=[directory stringByAppendingPathComponent:filename(key)];NSString *folder=directory;
    void (^failure)(NSString*)=[self.saveFailed copy];
    dispatch_async(writer,^{@autoreleasepool{
        NSError *error=nil;
        NSData *bytes=[NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error];
        BOOL made=[[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
        if(!bytes||!made||![bytes writeToFile:path options:NSDataWritingAtomic error:&error]){
            if(failure)dispatch_async(dispatch_get_main_queue(),^{failure(@"Edits are in memory; recovery file could not be saved");});
        }
    }});
}
- (void)flush {dispatch_sync(writer,^{});}
@end
