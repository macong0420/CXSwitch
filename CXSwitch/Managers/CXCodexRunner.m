//
//  CXCodexRunner.m
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import "CXCodexRunner.h"

static NSString * const kCodexPathDefaultsKey = @"CXSwitch.CodexPath";

@interface CXCodexRunner ()
@property (nonatomic, copy, readwrite, nullable) NSString *detectedVersion;
@end

@implementation CXCodexRunner

#pragma mark - Singleton

+ (instancetype)sharedRunner {
    static CXCodexRunner *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CXCodexRunner alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *savedPath = [[NSUserDefaults standardUserDefaults] stringForKey:kCodexPathDefaultsKey];
        if (savedPath.length > 0 && [[NSFileManager defaultManager] isExecutableFileAtPath:savedPath]) {
            self.codexPath = savedPath;
        }

        // 尝试自动探测
        [self detectCodexPath];
    }
    return self;
}

#pragma mark - Properties

- (BOOL)isCodexAvailable {
    if (self.codexPath.length == 0) return NO;
    return [[NSFileManager defaultManager] isExecutableFileAtPath:self.codexPath];
}

#pragma mark - 路径探测

- (NSArray<NSString *> *)candidatePaths {
    NSMutableArray *paths = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    // 在沙盒/不同运行环境下，NSHomeDirectory 可能指向容器目录；尽量拿到真实用户目录
    NSString *realHome = NSHomeDirectoryForUser(NSUserName());
    if (realHome.length > 0) {
        home = realHome;
    }
    
    // 1. 用户指定路径
    if (self.codexPath && self.codexPath.length > 0) {
        [paths addObject:self.codexPath];
    }
    
    // 2. 常见安装路径
    // Homebrew (Apple Silicon)
    [paths addObject:@"/opt/homebrew/bin/codex"];
    
    // Homebrew (Intel)
    [paths addObject:@"/usr/local/bin/codex"];
    
    // npm global
    [paths addObject:[home stringByAppendingPathComponent:@".npm/bin/codex"]];

    // yarn global
    [paths addObject:[home stringByAppendingPathComponent:@".yarn/bin/codex"]];

    // n
    [paths addObject:[home stringByAppendingPathComponent:@".n/bin/codex"]];

    // volta
    [paths addObject:[home stringByAppendingPathComponent:@".volta/bin/codex"]];

    // asdf shims
    [paths addObject:[home stringByAppendingPathComponent:@".asdf/shims/codex"]];

    // ~/.local/bin
    [paths addObject:[home stringByAppendingPathComponent:@".local/bin/codex"]];

    // bun
    [paths addObject:[home stringByAppendingPathComponent:@".bun/bin/codex"]];

    // pnpm (default on macOS)
    [paths addObject:[home stringByAppendingPathComponent:@"Library/pnpm/codex"]];

    // @openai/codex vendor 二进制（优先匹配当前架构）
#if __arm64__
    NSArray<NSString *> *vendorArchOrder = @[@"aarch64-apple-darwin", @"x86_64-apple-darwin"];
#else
    NSArray<NSString *> *vendorArchOrder = @[@"x86_64-apple-darwin", @"aarch64-apple-darwin"];
#endif

    // n 版本管理器安装的位置（vendor 二进制）
    for (NSString *arch in vendorArchOrder) {
        [paths addObject:[home stringByAppendingPathComponent:
                          [NSString stringWithFormat:@".n/lib/node_modules/@openai/codex/vendor/%@/codex/codex", arch]]];
    }

    // Homebrew npm global
    for (NSString *arch in vendorArchOrder) {
        [paths addObject:[NSString stringWithFormat:@"/opt/homebrew/lib/node_modules/@openai/codex/vendor/%@/codex/codex", arch]];
    }
    for (NSString *arch in vendorArchOrder) {
        [paths addObject:[NSString stringWithFormat:@"/usr/local/lib/node_modules/@openai/codex/vendor/%@/codex/codex", arch]];
    }
    
    // nvm 安装的位置
    [paths addObject:[home stringByAppendingPathComponent:@".nvm/versions/node/*/bin/codex"]];
    [paths addObject:[home stringByAppendingPathComponent:
                      @".nvm/versions/node/*/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex"]];
    [paths addObject:[home stringByAppendingPathComponent:
                      @".nvm/versions/node/*/lib/node_modules/@openai/codex/vendor/x86_64-apple-darwin/codex/codex"]];
    
    // 直接全局安装
    [paths addObject:@"/usr/bin/codex"];
    
    return [paths copy];
}

- (nullable NSString *)detectCodexPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 首先检查候选路径
    for (NSString *path in [self candidatePaths]) {
        // 处理通配符路径
        if ([path containsString:@"*"]) {
            NSArray *expandedPaths = [self expandWildcardPath:path];
            for (NSString *expandedPath in expandedPaths) {
                if ([fm isExecutableFileAtPath:expandedPath]) {
                    if ([self validateCodexAtPath:expandedPath]) {
                        self.codexPath = expandedPath;
                        [[NSUserDefaults standardUserDefaults] setObject:expandedPath forKey:kCodexPathDefaultsKey];
                        return expandedPath;
                    }
                }
            }
        } else {
            if ([fm isExecutableFileAtPath:path]) {
                if ([self validateCodexAtPath:path]) {
                    self.codexPath = path;
                    [[NSUserDefaults standardUserDefaults] setObject:path forKey:kCodexPathDefaultsKey];
                    return path;
                }
            }
        }
    }
    
    // 使用 which 命令查找
    NSString *whichPath = [self runWhichCodex];
    if (whichPath && [self validateCodexAtPath:whichPath]) {
        self.codexPath = whichPath;
        [[NSUserDefaults standardUserDefaults] setObject:whichPath forKey:kCodexPathDefaultsKey];
        return whichPath;
    }

    // 用 login shell 再试一次（GUI app 的 PATH 往往不包含 Homebrew/nvm/asdf 等）
    NSString *shellPath = [self runLoginShellWhichCodex];
    if (shellPath && [self validateCodexAtPath:shellPath]) {
        self.codexPath = shellPath;
        [[NSUserDefaults standardUserDefaults] setObject:shellPath forKey:kCodexPathDefaultsKey];
        return shellPath;
    }
    
    return nil;
}

- (NSArray<NSString *> *)expandWildcardPath:(NSString *)wildcardPath {
    NSString *path = [wildcardPath stringByExpandingTildeInPath];
    NSArray<NSString *> *components = [path pathComponents];

    NSUInteger starIndex = NSNotFound;
    for (NSUInteger i = 0; i < components.count; i++) {
        if ([components[i] isEqualToString:@"*"]) {
            starIndex = i;
            break;
        }
    }

    if (starIndex == NSNotFound) {
        // 也兼容 “foo/*/bar” 这种情况（* 在 path 中但不是独立 component）
        NSRange starRange = [path rangeOfString:@"*"];
        if (starRange.location == NSNotFound) return @[wildcardPath];
        // 回退：不展开，交给其他候选路径逻辑
        return @[wildcardPath];
    }

    NSString *parentDir = [NSString pathWithComponents:[components subarrayWithRange:NSMakeRange(0, starIndex)]];
    NSString *suffix = @"";
    if (starIndex + 1 < components.count) {
        suffix = [NSString pathWithComponents:[components subarrayWithRange:NSMakeRange(starIndex + 1, components.count - starIndex - 1)]];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:parentDir error:nil];
    if (children.count == 0) return @[];

    NSMutableArray<NSString *> *results = [NSMutableArray array];
    for (NSString *child in children) {
        NSString *candidate = [parentDir stringByAppendingPathComponent:child];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:candidate isDirectory:&isDir] || !isDir) continue;

        NSString *full = suffix.length > 0 ? [candidate stringByAppendingPathComponent:suffix] : candidate;
        [results addObject:full];
    }

    return results;
}

- (nullable NSString *)runWhichCodex {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/which"];
    task.arguments = @[@"codex"];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    
    NSError *error = nil;
    [task launchAndReturnError:&error];
    if (error) return nil;
    
    [task waitUntilExit];
    
    if (task.terminationStatus == 0) {
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    
    return nil;
}

- (nullable NSString *)runLoginShellWhichCodex {
    NSArray<NSString *> *shells = @[@"/bin/zsh", @"/bin/bash"];

    for (NSString *shell in shells) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm isExecutableFileAtPath:shell]) continue;

        // zsh/bash 用各自的“只找外部命令”的方式，避免 alias/function 干扰
        NSString *cmd = nil;
        if ([shell hasSuffix:@"/zsh"]) {
            cmd = @"whence -p codex 2>/dev/null || command -v codex 2>/dev/null";
        } else {
            cmd = @"type -P codex 2>/dev/null || command -v codex 2>/dev/null";
        }

        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:shell];
        task.arguments = @[@"-lc", cmd];

        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = [NSPipe pipe];

        NSError *error = nil;
        [task launchAndReturnError:&error];
        if (error) continue;

        [task waitUntilExit];
        if (task.terminationStatus != 0) continue;

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *path = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] firstObject];
        path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        // command -v 可能返回函数/别名等描述；这里只接受绝对路径
        if (path.length > 0 && [path hasPrefix:@"/"]) return path;
    }

    return nil;
}

- (BOOL)validateCodexAtPath:(NSString *)path {
    // 快速验证：尝试执行 --version
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = @[@"--version"];
    
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;
    
    NSError *error = nil;
    [task launchAndReturnError:&error];
    if (error) {
        NSLog(@"Failed to validate codex at %@: %@", path, error);
        return NO;
    }
    
    [task waitUntilExit];
    
    if (task.terminationStatus == 0) {
        NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
        NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
        NSString *stdoutOutput = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
        NSString *stderrOutput = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
        NSString *output = stdoutOutput.length > 0 ? stdoutOutput : stderrOutput;
        
        // 检查输出是否像版本号
        if (output && (
            [output containsString:@"codex"] || 
            [output containsString:@"Codex"] ||
            [output containsString:@"version"] ||
            [output containsString:@"."])) {
            
            self.detectedVersion = [output stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - 命令执行

- (void)runCodexWithArgs:(NSArray<NSString *> *)args 
              completion:(CXCodexRunnerCompletion)completion {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *stdoutOutput = nil;
        NSString *stderrOutput = nil;
        
        int exitCode = [self runCodexSyncWithArgs:args 
                                     stdoutOutput:&stdoutOutput 
                                     stderrOutput:&stderrOutput];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(exitCode, stdoutOutput, stderrOutput);
            }
        });
    });
}

- (int)runCodexSyncWithArgs:(NSArray<NSString *> *)args 
               stdoutOutput:(NSString * _Nullable * _Nullable)stdoutOutput 
               stderrOutput:(NSString * _Nullable * _Nullable)stderrOutput {
    
    if (!self.codexPath) {
        if (stderrOutput) {
            *stderrOutput = @"Codex path not configured";
        }
        return -1;
    }
    
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:self.codexPath];
    task.arguments = args ?: @[];
    
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;
    
    // 设置环境变量
    NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    task.environment = env;
    
    NSError *error = nil;
    [task launchAndReturnError:&error];
    
    if (error) {
        if (stderrOutput) {
            *stderrOutput = [error localizedDescription];
        }
        return -1;
    }
    
    [task waitUntilExit];
    
    if (stdoutOutput) {
        NSData *data = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
        *stdoutOutput = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    if (stderrOutput) {
        NSData *data = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
        *stderrOutput = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    
    return task.terminationStatus;
}

#pragma mark - 健康检查

- (void)checkVersionWithCompletion:(CXCodexVersionCompletion)completion {
    [self runCodexWithArgs:@[@"--version"] completion:^(int exitCode, NSString *stdoutOutput, NSString *stderrOutput) {
        if (exitCode == 0 && stdoutOutput) {
            NSString *version = [stdoutOutput stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            self.detectedVersion = version;
            if (completion) {
                completion(version, nil);
            }
        } else {
            NSError *error = [NSError errorWithDomain:@"CXCodexRunnerErrorDomain" 
                                                 code:exitCode 
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: @"Failed to get Codex version",
                                                 NSLocalizedFailureReasonErrorKey: stderrOutput ?: @"Unknown error"
                                             }];
            if (completion) {
                completion(nil, error);
            }
        }
    }];
}

- (void)checkLoginStatusWithCompletion:(CXCodexLoginStatusCompletion)completion {
    [self runCodexWithArgs:@[@"login", @"status"] completion:^(int exitCode, NSString *stdoutOutput, NSString *stderrOutput) {
        NSString *output = stdoutOutput ?: stderrOutput ?: @"";
        output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // 根据输出判断登录状态
        BOOL isLoggedIn = NO;
        if ([output.lowercaseString containsString:@"logged in"] ||
            [output.lowercaseString containsString:@"authenticated"]) {
            isLoggedIn = YES;
        }
        
        if (completion) {
            NSError *error = nil;
            if (exitCode != 0 && !isLoggedIn) {
                error = [NSError errorWithDomain:@"CXCodexRunnerErrorDomain" 
                                            code:exitCode 
                                        userInfo:@{NSLocalizedDescriptionKey: output}];
            }
            completion(output, isLoggedIn, error);
        }
    }];
}

- (void)triggerLoginWithCompletion:(void (^)(BOOL started, NSError * _Nullable error))completion {
    // 使用 --device-auth 避免浏览器自动打开的问题
    [self runCodexWithArgs:@[@"login"] completion:^(int exitCode, NSString *stdoutOutput, NSString *stderrOutput) {
        if (completion) {
            if (exitCode == 0) {
                completion(YES, nil);
            } else {
                NSError *error = [NSError errorWithDomain:@"CXCodexRunnerErrorDomain" 
                                                     code:exitCode 
                                                 userInfo:@{
                                                     NSLocalizedDescriptionKey: @"Failed to start login",
                                                     NSLocalizedFailureReasonErrorKey: stderrOutput ?: @"Unknown error"
                                                 }];
                completion(NO, error);
            }
        }
    }];
}

#pragma mark - 工具方法

+ (NSString *)sanitizeOutput:(NSString *)output {
    if (!output) return @"";
    
    // 移除可能包含的 API Key
    NSRegularExpression *apiKeyRegex = [NSRegularExpression 
                                         regularExpressionWithPattern:@"sk-[a-zA-Z0-9]{20,}" 
                                                              options:0 
                                                                error:nil];
    
    NSString *sanitized = [apiKeyRegex stringByReplacingMatchesInString:output 
                                                                options:0 
                                                                  range:NSMakeRange(0, output.length) 
                                                           withTemplate:@"sk-****"];
    
    return sanitized;
}

@end
