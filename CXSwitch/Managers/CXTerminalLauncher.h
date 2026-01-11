//
//  CXTerminalLauncher.h
//  CXSwitch
//
//  Created by Codex CLI on 2026/1/11.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CXTerminalLauncher : NSObject

/// Open system Terminal.app and run a shell command in a new tab/window.
+ (BOOL)openTerminalAndRunCommand:(NSString *)command error:(NSError **)error;

/// Shell-quote a string for POSIX shells (single-quote style).
+ (NSString *)shellQuotedString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
