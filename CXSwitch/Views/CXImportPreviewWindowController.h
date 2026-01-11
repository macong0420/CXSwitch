//
//  CXImportPreviewWindowController.h
//  CXSwitch
//
//  Created by Codex CLI on 2026/1/10.
//

#import <Cocoa/Cocoa.h>

@class CXLocalConfigImportCandidate;
@class CXProfile;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CXImportDedupeStrategy) {
    CXImportDedupeStrategySkipByBaseURL = 0,
    CXImportDedupeStrategyAllowDuplicates = 1,
};

typedef void (^CXImportPreviewCompletion)(NSArray<CXLocalConfigImportCandidate *> *selectedCandidates);

@interface CXImportPreviewWindowController : NSWindowController

/// Present a sheet to preview import candidates and return the selected ones.
+ (void)beginSheetForWindow:(NSWindow *)window
                 candidates:(NSArray<CXLocalConfigImportCandidate *> *)candidates
            existingProfiles:(NSArray<CXProfile *> *)existingProfiles
                 completion:(CXImportPreviewCompletion)completion;

@end

NS_ASSUME_NONNULL_END

