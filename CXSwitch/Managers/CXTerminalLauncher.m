//
//  CXTerminalLauncher.m
//  CXSwitch
//
//  Created by Codex CLI on 2026/1/11.
//

#import "CXTerminalLauncher.h"
#import <AppKit/AppKit.h>

@implementation CXTerminalLauncher

+ (NSString *)shellQuotedString:(NSString *)string {
    if (!string) return @"''";
    // POSIX shell safe single-quote: ' -> '\''.
    return [NSString stringWithFormat:@"'%@'", [string stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

+ (BOOL)openTerminalByOpeningCommandFile:(NSString *)command error:(NSError **)error {
    NSString *trimmed = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXTerminalLauncherErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"命令不能为空"}];
        }
        return NO;
    }

    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CXSwitch"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *filename = [NSString stringWithFormat:@"cxswitch-%@.command", [[NSUUID UUID] UUIDString]];
    NSString *path = [dir stringByAppendingPathComponent:filename];

    NSString *script = [NSString stringWithFormat:
                        @"#!/bin/zsh\n"
                        @"set -e\n"
                        @"cd \"$HOME\"\n"
                        @"%@\n"
                        @"\n"
                        @"# Keep the window interactive after the command exits.\n"
                        @"exec \"$SHELL\" -l\n",
                        trimmed];

    NSError *writeError = nil;
    BOOL ok = [script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (!ok) {
        if (error) *error = writeError;
        return NO;
    }

    [fm setAttributes:@{NSFilePosixPermissions: @(0700)} ofItemAtPath:path error:nil];

    return [[NSWorkspace sharedWorkspace] openFile:path withApplication:@"Terminal"];
}

+ (NSString *)escapedAppleScriptStringLiteral:(NSString *)string {
    if (!string) return @"\"\"";
    NSMutableString *s = [string mutableCopy];
    [s replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, s.length)];
    return [NSString stringWithFormat:@"\"%@\"", s];
}

+ (BOOL)openTerminalAndRunCommand:(NSString *)command error:(NSError **)error {
    NSString *trimmed = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXTerminalLauncherErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"命令不能为空"}];
        }
        return NO;
    }

    NSString *cmdLiteral = [self escapedAppleScriptStringLiteral:trimmed];
    NSString *source = [NSString stringWithFormat:
                        @"tell application \"Terminal\"\n"
                        @"  activate\n"
                        @"  do script %@\n"
                        @"end tell\n", cmdLiteral];

    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *errInfo = nil;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&errInfo];
    (void)result;

    if (errInfo) {
        NSInteger code = -2;
        id num = errInfo[NSAppleScriptErrorNumber];
        if ([num respondsToSelector:@selector(integerValue)]) {
            code = [num integerValue];
        }

        // If user hasn't authorized Automation for Terminal, fall back to opening a .command file.
        // Common error code: -1743 (Not authorized to send Apple events).
        if (code == -1743) {
            return [self openTerminalByOpeningCommandFile:trimmed error:error];
        }

        if (error) {
            NSString *msg = errInfo[NSAppleScriptErrorMessage] ?: @"无法控制 Terminal（可能需要授权 Automation 权限）";
            *error = [NSError errorWithDomain:@"CXTerminalLauncherErrorDomain"
                                         code:code
                                     userInfo:@{NSLocalizedDescriptionKey: msg,
                                                @"AppleScriptError": errInfo}];
        }
        return NO;
    }

    return YES;
}

@end
