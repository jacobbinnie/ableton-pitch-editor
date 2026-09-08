#import "pitch_document_store.hpp"
#include <iostream>
#include <stdexcept>

static void require(bool value,const char *message){if(!value)throw std::runtime_error(message);}
int main(){@autoreleasepool{try{
    NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    pitch::Analysis analysis;analysis.duration=1;analysis.notes={{0,0,1,60,0}};
    PitchDocumentStore *store=[[PitchDocumentStore alloc] initWithDirectory:folder];
    auto a=[store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"];
    require(a->split(0,.5)&&a->transpose(a->analysis().notes[1].id,.37),"setup edits");
    require(a->setGain(0,-6)&&a->setVibrato(0,.3)&&a->setDrift(0,35,-20),"gain/vibrato edit");
    [store save:a identity:@"run1:song1:clip1" sourceHash:@"source1"];
    auto other=[store open:analysis identity:@"run1:song1:clip2" sourceHash:@"source1"];
    require(other!=a&&other->analysis().notes.size()==1&&other->analysis().notes[0].semitones==0,"same source leaks clip edits");
    require([store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"]==a,"cache loses document ownership");
    require(a->undo()&&a->redo(),"cached history lost");[store flush];
    store=[[PitchDocumentStore alloc] initWithDirectory:folder];
    auto loaded=[store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"];
    require(loaded->analysis().notes.size()==2&&loaded->analysis().notes[1].semitones==.37,"reload loses structural/fractional edits");
    require(loaded->analysis().notes[0].gainDb==-6&&loaded->analysis().notes[0].vibrato==.3&&loaded->analysis().notes[0].driftStart==35&&loaded->analysis().notes[0].driftEnd==-20,"gain recovery");
    require(loaded->analysis().notes[1].id==a->analysis().notes[1].id,"reload changes ids");
    require([store open:analysis identity:@"run2:song1:clip1" sourceHash:@"source1"]->analysis().notes.size()==1,"session leaks edits");
    require([store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source2"]->analysis().notes.size()==1,"changed source restores stale edits");
    auto files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:nil];
    require(files.count==1,"unexpected saved files");NSString *file=[folder stringByAppendingPathComponent:files[0]];
    NSDictionary *legacy=@{@"schema":@1,@"identity":@"run1:song1:clip1",@"sourceHash":@"source1",@"notes":@[@[@0,@0,@1,@60,@.37]]};
    [[NSJSONSerialization dataWithJSONObject:legacy options:0 error:nil] writeToFile:file atomically:YES];
    store=[[PitchDocumentStore alloc] initWithDirectory:folder];
    auto migrated=[store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"];
    require(migrated->analysis().notes[0].vibrato==1&&migrated->analysis().notes[0].gainDb==0&&migrated->analysis().notes[0].semitones==.37,"legacy migration lost edit");
    NSDictionary *legacyGain=@{@"schema":@2,@"identity":@"run1:song1:clip1",@"sourceHash":@"source1",@"notes":@[@[@0,@0,@1,@60,@.37,@(-6)]]};
    [[NSJSONSerialization dataWithJSONObject:legacyGain options:0 error:nil] writeToFile:file atomically:YES];
    store=[[PitchDocumentStore alloc] initWithDirectory:folder];
    auto migratedGain=[store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"];
    require(migratedGain->analysis().notes[0].gainDb==-6&&migratedGain->analysis().notes[0].vibrato==1,"schema 2 gain migration");
    NSDictionary *legacyExpression=@{@"schema":@3,@"identity":@"run1:song1:clip1",@"sourceHash":@"source1",@"notes":@[@[@0,@0,@1,@60,@.37,@(-6),@.3]]};
    [[NSJSONSerialization dataWithJSONObject:legacyExpression options:0 error:nil] writeToFile:file atomically:YES];
    store=[[PitchDocumentStore alloc] initWithDirectory:folder];
    auto migratedExpression=[store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"];
    require(migratedExpression->analysis().notes[0].vibrato==.3&&migratedExpression->analysis().notes[0].driftStart==0&&migratedExpression->analysis().notes[0].driftEnd==0,"schema 3 drift migration");
    NSDictionary *badDrift=@{@"schema":@4,@"identity":@"run1:song1:clip1",@"sourceHash":@"source1",@"notes":@[@[@0,@0,@1,@60,@.37,@(-6),@.3,@201,@0]]};
    [[NSJSONSerialization dataWithJSONObject:badDrift options:0 error:nil] writeToFile:file atomically:YES];
    store=[[PitchDocumentStore alloc] initWithDirectory:folder];
    require([store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"]->analysis().notes[0].semitones==0,"invalid drift recovery accepted");
    NSDictionary *badVibrato=@{@"schema":@3,@"identity":@"run1:song1:clip1",@"sourceHash":@"source1",@"notes":@[@[@0,@0,@1,@60,@.37,@(-6),@2]]};
    [[NSJSONSerialization dataWithJSONObject:badVibrato options:0 error:nil] writeToFile:file atomically:YES];
    store=[[PitchDocumentStore alloc] initWithDirectory:folder];
    require([store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"]->analysis().notes[0].semitones==0,"invalid vibrato recovery accepted");
    for(id invalid in @[@{@"schema":@2},@{@"schema":@1,@"identity":@"run1:song1:clip1",@"sourceHash":@"source1",@"notes":@[@[@0,@0,@.7,@60,@0],@[@1,@.5,@1,@60,@0]]},@{@"schema":@1,@"identity":@"run1:song1:clip1",@"sourceHash":@"source1",@"notes":@[@[@0,@0,@.5,@60,@0],@[@0,@.5,@1,@60,@0]]}]){
        [[NSJSONSerialization dataWithJSONObject:invalid options:0 error:nil] writeToFile:file atomically:YES];
        store=[[PitchDocumentStore alloc] initWithDirectory:folder];
        require([store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"]->analysis().notes.size()==1,"invalid recovery accepted");
    }
    [@"{truncated" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    store=[[PitchDocumentStore alloc] initWithDirectory:folder];
    require([store open:analysis identity:@"run1:song1:clip1" sourceHash:@"source1"]->analysis().notes.size()==1,"corrupt recovery accepted");
    [[NSFileManager defaultManager] removeItemAtPath:folder error:nil];
    std::cout<<"PASS: clip/source/session isolation, document lifetime, atomic recovery, structural edits and corrupt-data rejection\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}}
