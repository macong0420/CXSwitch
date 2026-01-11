//
//  CXConfigManager.m
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import "CXConfigManager.h"
#import "CXKeychainManager.h"

NSNotificationName const CXConfigDidApplyNotification = @"CXConfigDidApplyNotification";

static NSString * const kManagedProviderName = @"codexswitcher";
static NSString * const kBaselineModelProviderDefaultsKey = @"CXSwitch.BaselineModelProvider";
static NSString * const kBaselinePreferredAuthDefaultsKey = @"CXSwitch.BaselinePreferredAuthMethod";
static NSString * const kBaselineModelDefaultsKey = @"CXSwitch.BaselineModel";
static NSString * const kDefaultsNullSentinel = @"__CXSwitch_NULL__";
static NSString * const kPreferredAuthMethodKey = @"preferred_auth_method";
static NSString * const kModelProviderKey = @"model_provider";
static NSString * const kModelKey = @"model";
static NSString * const kDefaultModelValue = @"gpt-5.2";

@interface CXConfigManager ()
- (NSString *)stateFilePath;
- (NSString *)authJsonCXSwitchBackupPath;
- (void)backupAuthJsonIfNeeded;
- (BOOL)updateConfigTomlWithProfile:(CXProfile *)profile error:(NSError **)error;
- (NSString *)contentByApplyingManagedProviderToConfig:(NSString *)content profile:(CXProfile *)profile;
- (BOOL)writeStateProfileName:(NSString *)name error:(NSError **)error;
- (nullable NSString *)codexSwitchProfileKeyForProfile:(CXProfile *)profile;
@end

@implementation CXConfigManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static CXConfigManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CXConfigManager alloc] init];
    });
    return instance;
}

#pragma mark - 路径

- (NSString *)codexDirectoryPath {
    // Prefer CODEX_HOME when available (Codex CLI supports overriding the config directory).
    NSString *envCodexHome = [NSProcessInfo processInfo].environment[@"CODEX_HOME"];
    if (envCodexHome.length > 0) {
        NSString *expanded = [envCodexHome stringByExpandingTildeInPath];
        if (expanded.length > 0) return expanded;
    }

    NSString *home = NSHomeDirectory();
    // 在沙盒/不同运行环境下，NSHomeDirectory 可能指向容器目录；尽量拿到真实用户目录
    NSString *realHome = NSHomeDirectoryForUser(NSUserName());
    if (realHome.length > 0) {
        home = realHome;
    }
    return [home stringByAppendingPathComponent:@".codex"];
}

- (NSString *)configTomlPath {
    return [self.codexDirectoryPath stringByAppendingPathComponent:@"config.toml"];
}

- (NSString *)authJsonPath {
    return [self.codexDirectoryPath stringByAppendingPathComponent:@"auth.json"];
}

- (NSString *)authJsonBackupPath {
    return [self.codexDirectoryPath stringByAppendingPathComponent:@"auth.json.codexswitcher.backup"];
}

- (NSString *)stateFilePath {
    return [self.codexDirectoryPath stringByAppendingPathComponent:@"current_profile"];
}

- (NSString *)authJsonCXSwitchBackupPath {
    return [self.codexDirectoryPath stringByAppendingPathComponent:@"auth.json.cxswitch.backup"];
}

+ (NSString *)managedProviderName {
    return kManagedProviderName;
}

#pragma mark - 目录确保

- (BOOL)ensureCodexDirectoryWithError:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = self.codexDirectoryPath;
    
    if (![fm fileExistsAtPath:path]) {
        return [fm createDirectoryAtPath:path 
             withIntermediateDirectories:YES 
                              attributes:nil 
                                   error:error];
    }
    return YES;
}

#pragma mark - Backups

- (void)backupAuthJsonIfNeeded {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *authPath = self.authJsonPath;
    NSString *backupPath = [self authJsonCXSwitchBackupPath];

    if (![fm fileExistsAtPath:authPath]) return;
    if ([fm fileExistsAtPath:backupPath]) return;

    NSError *copyError = nil;
    if ([fm copyItemAtPath:authPath toPath:backupPath error:&copyError]) {
        [fm setAttributes:@{NSFilePosixPermissions: @(0600)} ofItemAtPath:backupPath error:nil];
    }
}

#pragma mark - Apply Profile

- (BOOL)applyProfile:(CXProfile *)profile 
              apiKey:(NSString *)apiKey 
               error:(NSError **)error {
    
    if (!profile) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXConfigManagerErrorDomain" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Profile 不能为空"}];
        }
        return NO;
    }
    
    if (!apiKey || apiKey.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXConfigManagerErrorDomain" 
                                         code:-2 
                                     userInfo:@{NSLocalizedDescriptionKey: @"API Key 不能为空"}];
        }
        return NO;
    }

    NSString *normalizedKey = [CXKeychainManager normalizedAPIKeyFromUserInput:apiKey];
    if (!normalizedKey || normalizedKey.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXConfigManagerErrorDomain"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"API Key 无效（请确认没有空格/换行等多余内容）"}];
        }
        return NO;
    }
    
    // 确保目录存在
    if (![self ensureCodexDirectoryWithError:error]) {
        return NO;
    }

    // 记录 baseline（第一次接管时保存，用于恢复 Official）
    [self persistBaselineConfigIfNeeded];

    // 备份现有 auth.json（只备份一次，便于用户回滚）
    [self backupAuthJsonIfNeeded];
    
    // 1. 写入 auth.json
    if (![self writeAuthJsonWithAPIKey:normalizedKey error:error]) {
        return NO;
    }
    
    // 2. 更新 config.toml
    if (![self updateConfigTomlWithProfile:profile error:error]) {
        return NO;
    }

    // 3. 写入 state（便于终端侧/其他工具显示当前状态）
    // 兼容用户在 shell 启动时自动运行 ~/.codex/codex_switch.sh 的场景：
    // 该脚本通常读取 ~/.codex/current_profile 并将其作为 profile 参数。
    // 如果写入显示名（例如中文/空格），会导致脚本打印 usage 并产生“无关输出”。
    NSString *stateKey = [self codexSwitchProfileKeyForProfile:profile];
    [self writeStateProfileName:(stateKey ?: @"") error:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXConfigDidApplyNotification 
                                                        object:profile 
                                                      userInfo:@{@"mode": @"apiKey"}];
    
    return YES;
}

- (BOOL)applyOfficialModeWithError:(NSError **)error {
    // 确保目录存在
    if (![self ensureCodexDirectoryWithError:error]) {
        return NO;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 1. 备份现有 auth.json（如果存在）
    NSString *authPath = self.authJsonPath;
    NSString *backupPath = self.authJsonBackupPath;
    
    if ([fm fileExistsAtPath:authPath]) {
        // 删除旧备份
        if ([fm fileExistsAtPath:backupPath]) {
            [fm removeItemAtPath:backupPath error:nil];
        }
        
        // 创建新备份
        NSError *copyError = nil;
        if (![fm copyItemAtPath:authPath toPath:backupPath error:&copyError]) {
            NSLog(@"Warning: Failed to backup auth.json: %@", copyError);
        } else {
            // 设置备份文件权限为 0600
            [fm setAttributes:@{NSFilePosixPermissions: @(0600)} 
                 ofItemAtPath:backupPath 
                        error:nil];
        }
    }
    
    // 2. 删除 auth.json
    if ([fm fileExistsAtPath:authPath]) {
        NSError *removeError = nil;
        if (![fm removeItemAtPath:authPath error:&removeError]) {
            if (error) {
                *error = removeError;
            }
            return NO;
        }
    }
    
    // 3. 清理 config.toml 中我们添加的 provider 配置
    [self cleanupConfigTomlWithError:nil];

    // 4. 更新 state
    // 写空避免触发用户 shell 启动时执行 codex_switch.sh 的 usage 输出
    [self writeStateProfileName:@"" error:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXConfigDidApplyNotification 
                                                        object:nil 
                                                      userInfo:@{@"mode": @"official"}];
    
    return YES;
}

#pragma mark - auth.json 操作

- (BOOL)writeAuthJsonWithAPIKey:(NSString *)apiKey error:(NSError **)error {
    NSDictionary *authData = @{
        @"OPENAI_API_KEY": apiKey
    };
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:authData 
                                                       options:NSJSONWritingPrettyPrinted 
                                                         error:&jsonError];
    if (!jsonData) {
        if (error) {
            *error = jsonError;
        }
        return NO;
    }
    
    NSString *path = self.authJsonPath;
    
    // 原子写入
    if (![jsonData writeToFile:path options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    
    // 设置文件权限为 0600
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = @{NSFilePosixPermissions: @(0600)};
    [fm setAttributes:attrs ofItemAtPath:path error:nil];
    
    return YES;
}

#pragma mark - config.toml 操作

- (BOOL)updateConfigTomlWithProfile:(CXProfile *)profile error:(NSError **)error {
    NSString *path = self.configTomlPath;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 读取现有内容
    NSString *existingContent = @"";
    if ([fm fileExistsAtPath:path]) {
        existingContent = [NSString stringWithContentsOfFile:path 
                                                    encoding:NSUTF8StringEncoding 
                                                       error:nil] ?: @"";
    }

    NSString *updated = [self contentByApplyingManagedProviderToConfig:existingContent profile:profile];
    NSError *writeError = nil;
    if (![updated writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        if (error) {
            *error = writeError;
        }
        return NO;
    }
    return YES;
}

- (BOOL)cleanupConfigTomlWithError:(NSError **)error {
    NSString *path = self.configTomlPath;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:path]) {
        return YES;
    }
    
    NSString *existingContent = [NSString stringWithContentsOfFile:path 
                                                          encoding:NSUTF8StringEncoding 
                                                             error:nil];
    if (!existingContent) {
        return YES;
    }
    
    NSString *newContent = [self contentByCleaningManagedProviderFromConfig:existingContent];
    return [newContent writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
}

- (nullable NSString *)extractProjectsSectionFromContent:(NSString *)content {
    if (!content || content.length == 0) return nil;
    
    // 查找 [projects. 开头的段落并保留所有内容
    NSRange projectsRange = [content rangeOfString:@"[projects."];
    if (projectsRange.location == NSNotFound) {
        return nil;
    }
    
    // 从 [projects. 开始到文件末尾
    return [content substringFromIndex:projectsRange.location];
}

- (nullable NSString *)extractProjectsSection {
    NSString *content = [self readConfigToml];
    return [self extractProjectsSectionFromContent:content];
}

#pragma mark - 状态读取

- (NSDictionary *)currentConfigStatus {
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // auth.json 状态
    status[@"authJsonExists"] = @([fm fileExistsAtPath:self.authJsonPath]);
    
    // 读取 auth.json 内容
    if ([fm fileExistsAtPath:self.authJsonPath]) {
        NSData *data = [NSData dataWithContentsOfFile:self.authJsonPath];
        if (data) {
            NSDictionary *authData = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *raw = [authData[@"OPENAI_API_KEY"] isKindOfClass:[NSString class]] ? authData[@"OPENAI_API_KEY"] : nil;
            NSString *normalized = [CXKeychainManager normalizedAPIKeyFromUserInput:raw];
            if (normalized.length > 0) {
                status[@"hasAPIKey"] = @YES;
                status[@"authJsonValid"] = @YES;
            } else if (raw.length > 0) {
                status[@"hasAPIKey"] = @YES;
                status[@"authJsonValid"] = @NO;
            }
        }
    }
    
    // config.toml 状态
    status[@"configTomlExists"] = @([fm fileExistsAtPath:self.configTomlPath]);
    
    // 读取 config.toml 中的 base_url
    NSString *configContent = [self readConfigToml];
    if (configContent) {
        NSString *modelProvider = [self topLevelStringValueForKey:kModelProviderKey inContent:configContent];
        if (modelProvider) {
            status[@"modelProvider"] = modelProvider;
        }

        NSString *model = [self topLevelStringValueForKey:kModelKey inContent:configContent];
        if (model) {
            status[@"model"] = model;
        }

        if ([modelProvider isEqualToString:kManagedProviderName]) {
            status[@"isManagedProvider"] = @YES;
        }

        NSString *managedBaseURL = [self managedProviderBaseURLFromContent:configContent];
        if (managedBaseURL) {
            status[@"baseURL"] = managedBaseURL;
        }
    }
    
    // 备份状态
    status[@"hasBackup"] = @([fm fileExistsAtPath:self.authJsonBackupPath]);
    
    return [status copy];
}

- (BOOL)hasValidAuthJson {
    NSDictionary *status = [self currentConfigStatus];
    if (![status[@"authJsonExists"] boolValue]) return NO;
    if (status[@"authJsonValid"] != nil) {
        return [status[@"authJsonValid"] boolValue];
    }
    return [status[@"hasAPIKey"] boolValue];
}

- (BOOL)hasAuthJsonBackup {
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:self.authJsonBackupPath];
}

- (BOOL)restoreAuthJsonBackupWithError:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *backupPath = self.authJsonBackupPath;
    NSString *authPath = self.authJsonPath;
    
    if (![fm fileExistsAtPath:backupPath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXConfigManagerErrorDomain" 
                                         code:-3 
                                     userInfo:@{NSLocalizedDescriptionKey: @"备份文件不存在"}];
        }
        return NO;
    }
    
    // 删除现有的 auth.json
    if ([fm fileExistsAtPath:authPath]) {
        [fm removeItemAtPath:authPath error:nil];
    }
    
    // 复制备份
    BOOL ok = [fm copyItemAtPath:backupPath toPath:authPath error:error];
    if (ok) {
        [fm setAttributes:@{NSFilePosixPermissions: @(0600)} ofItemAtPath:authPath error:nil];
    }
    return ok;
}

- (nullable NSString *)readConfigToml {
    NSString *path = self.configTomlPath;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:path]) {
        return nil;
    }
    
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - Managed Provider Helpers

- (void)persistBaselineConfigIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id existingModelProvider = [defaults objectForKey:kBaselineModelProviderDefaultsKey];
    id existingPreferredAuth = [defaults objectForKey:kBaselinePreferredAuthDefaultsKey];
    id existingModel = [defaults objectForKey:kBaselineModelDefaultsKey];
    BOOL hasExisting =
        [existingModelProvider isKindOfClass:[NSString class]] &&
        [existingPreferredAuth isKindOfClass:[NSString class]] &&
        [existingModel isKindOfClass:[NSString class]];
    if (hasExisting) return;

    // 清理旧的异常值（例如曾尝试写入 NSNull 导致崩溃）
    if (existingModelProvider && ![existingModelProvider isKindOfClass:[NSString class]]) {
        [defaults removeObjectForKey:kBaselineModelProviderDefaultsKey];
    }
    if (existingPreferredAuth && ![existingPreferredAuth isKindOfClass:[NSString class]]) {
        [defaults removeObjectForKey:kBaselinePreferredAuthDefaultsKey];
    }
    if (existingModel && ![existingModel isKindOfClass:[NSString class]]) {
        [defaults removeObjectForKey:kBaselineModelDefaultsKey];
    }

    NSString *content = [self readConfigToml] ?: @"";
    NSString *modelProvider = [self topLevelStringValueForKey:kModelProviderKey inContent:content];
    NSString *preferredAuth = [self topLevelStringValueForKey:kPreferredAuthMethodKey inContent:content];
    NSString *model = [self topLevelStringValueForKey:kModelKey inContent:content];

    // NSUserDefaults 只接受 property list 类型；用字符串 sentinel 表示“原来没有这个键”
    [defaults setObject:(modelProvider.length > 0 ? modelProvider : kDefaultsNullSentinel)
                 forKey:kBaselineModelProviderDefaultsKey];
    [defaults setObject:(preferredAuth.length > 0 ? preferredAuth : kDefaultsNullSentinel)
                 forKey:kBaselinePreferredAuthDefaultsKey];
    [defaults setObject:(model.length > 0 ? model : kDefaultsNullSentinel)
                 forKey:kBaselineModelDefaultsKey];
}

- (NSString *)contentByApplyingManagedProviderToConfig:(NSString *)content profile:(CXProfile *)profile {
    NSString *result = content ?: @"";

    NSString *normalizedBaseURL = [CXProfile normalizeBaseURL:profile.baseURL ?: @""];

    // 1) 移除旧的 managed provider block（避免重复）
    result = [self stringByRemovingManagedProviderBlock:result];

    // 2) 设置 model_provider / preferred_auth_method（只改键对应的行，不动其它内容）
    result = [self stringByUpsertingTopLevelKey:kModelProviderKey stringValue:kManagedProviderName inContent:result];
    result = [self stringByUpsertingTopLevelKey:kPreferredAuthMethodKey stringValue:@"apikey" inContent:result];

    // 2.1) 设置 model（如果 Profile 指定了 model 则强制；否则使用默认值，避免“沿用上一个供应商的 model”导致不可用）
    NSString *rawProfileModel = profile.model;
    if (!rawProfileModel) rawProfileModel = @"";
    NSString *profileModel = [rawProfileModel stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (profileModel.length > 0) {
        result = [self stringByUpsertingTopLevelKey:kModelKey stringValue:profileModel inContent:result];
    } else {
        result = [self stringByUpsertingTopLevelKey:kModelKey stringValue:kDefaultModelValue inContent:result];
    }

    // 3) 插入 managed provider block
    NSMutableString *block = [NSMutableString string];
    [block appendFormat:@"[model_providers.%@]\n", kManagedProviderName];
    [block appendString:@"name = \"CXSwitch Managed Provider\"\n"];
    [block appendFormat:@"base_url = \"%@\"\n", normalizedBaseURL];
    [block appendString:@"wire_api = \"responses\"\n"];
    if (profile.requiresOpenAIAuth) {
        [block appendString:@"requires_openai_auth = true\n"];
    }

    if (profile.httpHeaders.count > 0) {
        [block appendString:@"\n"];
        [block appendFormat:@"[model_providers.%@.http_headers]\n", kManagedProviderName];
        NSArray<NSString *> *keys = [profile.httpHeaders.allKeys sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *key in keys) {
            NSString *value = profile.httpHeaders[key] ?: @"";
            NSString *escaped = [[value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                                 stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
            [block appendFormat:@"%@ = \"%@\"\n", key, escaped];
        }
    }

    result = [self stringByInsertingBlock:block beforeFirstProjectsSectionInContent:result];

    // 确保文件末尾有换行，避免与后续编辑器/工具冲突
    if (result.length > 0 && ![result hasSuffix:@"\n"]) {
        result = [result stringByAppendingString:@"\n"];
    }

    return result;
}

- (NSString *)contentByCleaningManagedProviderFromConfig:(NSString *)content {
    NSString *result = content ?: @"";

    // 1) 删除 managed provider block
    result = [self stringByRemovingManagedProviderBlock:result];

    // 2) 恢复/清理 model_provider / preferred_auth_method
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id baselineModelProvider = [defaults objectForKey:kBaselineModelProviderDefaultsKey];
    id baselinePreferredAuth = [defaults objectForKey:kBaselinePreferredAuthDefaultsKey];
    id baselineModel = [defaults objectForKey:kBaselineModelDefaultsKey];

    NSString *currentModelProvider = [self topLevelStringValueForKey:kModelProviderKey inContent:result];
    if ([currentModelProvider isEqualToString:kManagedProviderName]) {
        if ([baselineModelProvider isKindOfClass:[NSString class]] &&
            ![(NSString *)baselineModelProvider isEqualToString:kDefaultsNullSentinel]) {
            result = [self stringByUpsertingTopLevelKey:kModelProviderKey
                                            stringValue:(NSString *)baselineModelProvider
                                              inContent:result];
        } else {
            result = [self stringByRemovingTopLevelKey:kModelProviderKey inContent:result];
        }
    }

    NSString *currentPreferredAuth = [self topLevelStringValueForKey:kPreferredAuthMethodKey inContent:result];
    if ([currentModelProvider isEqualToString:kManagedProviderName] && [currentPreferredAuth isEqualToString:@"apikey"]) {
        if ([baselinePreferredAuth isKindOfClass:[NSString class]] &&
            ![(NSString *)baselinePreferredAuth isEqualToString:kDefaultsNullSentinel]) {
            result = [self stringByUpsertingTopLevelKey:kPreferredAuthMethodKey
                                            stringValue:(NSString *)baselinePreferredAuth
                                              inContent:result];
        } else {
            result = [self stringByRemovingTopLevelKey:kPreferredAuthMethodKey inContent:result];
        }
    }

    NSString *currentModel = [self topLevelStringValueForKey:kModelKey inContent:result];
    if ([currentModelProvider isEqualToString:kManagedProviderName] && currentModel.length > 0) {
        if ([baselineModel isKindOfClass:[NSString class]] &&
            ![(NSString *)baselineModel isEqualToString:kDefaultsNullSentinel]) {
            result = [self stringByUpsertingTopLevelKey:kModelKey
                                            stringValue:(NSString *)baselineModel
                                              inContent:result];
        } else {
            result = [self stringByRemovingTopLevelKey:kModelKey inContent:result];
        }
    }

    if (result.length > 0 && ![result hasSuffix:@"\n"]) {
        result = [result stringByAppendingString:@"\n"];
    }
    return result;
}

- (nullable NSString *)topLevelStringValueForKey:(NSString *)key inContent:(NSString *)content {
    if (!key.length || !content.length) return nil;

    NSString *pattern = [NSString stringWithFormat:@"(?m)^[ \\t]*%@\\s*=\\s*\"([^\"]*)\"\\s*$", [NSRegularExpression escapedPatternForString:key]];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
    if (!match || match.numberOfRanges < 2) return nil;

    NSRange r = [match rangeAtIndex:1];
    if (r.location == NSNotFound) return nil;
    return [content substringWithRange:r];
}

- (NSString *)stringByUpsertingTopLevelKey:(NSString *)key stringValue:(NSString *)value inContent:(NSString *)content {
    NSString *result = content ?: @"";
    NSString *escapedKey = [NSRegularExpression escapedPatternForString:key ?: @""];
    NSString *pattern = [NSString stringWithFormat:@"(?m)^[ \\t]*%@\\s*=.*$", escapedKey];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSString *replacement = [NSString stringWithFormat:@"%@ = \"%@\"", key, value ?: @""];
    NSString *replacementTemplate = [[replacement stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"$" withString:@"\\$"];

    NSTextCheckingResult *match = [regex firstMatchInString:result options:0 range:NSMakeRange(0, result.length)];
    if (match) {
        return [regex stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:replacementTemplate];
    }

    // 插入在文件头（但如果文件头有注释/空行，也可以插在第一行之前）
    if (result.length == 0) {
        return [replacement stringByAppendingString:@"\n"];
    }
    return [NSString stringWithFormat:@"%@\n%@", replacement, result];
}

- (NSString *)stringByRemovingTopLevelKey:(NSString *)key inContent:(NSString *)content {
    NSString *result = content ?: @"";
    NSString *escapedKey = [NSRegularExpression escapedPatternForString:key ?: @""];
    NSString *pattern = [NSString stringWithFormat:@"(?m)^[ \\t]*%@\\s*=.*\\n?", escapedKey];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    return [regex stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@""];
}

- (NSString *)stringByRemovingManagedProviderBlock:(NSString *)content {
    NSString *result = content ?: @"";
    // Remove both:
    // - [model_providers.<managed>]
    // - [model_providers.<managed>.<subtable>] (e.g. http_headers)
    NSString *pattern = [NSString stringWithFormat:@"(?ms)^\\[model_providers\\.%@(\\.[^\\]]+)?\\]\\s*.*?(?=^\\[|\\z)",
                         [NSRegularExpression escapedPatternForString:kManagedProviderName]];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    result = [regex stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@""];

    // 清理多余的空行（最多压缩到 2 个）
    NSRegularExpression *blank = [NSRegularExpression regularExpressionWithPattern:@"\\n{3,}" options:0 error:nil];
    result = [blank stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@"\n\n"];
    return result;
}

- (NSString *)stringByInsertingBlock:(NSString *)block beforeFirstProjectsSectionInContent:(NSString *)content {
    NSString *result = content ?: @"";
    if (!block.length) return result;

    // 确保 block 前后有合适的空行
    NSString *blockWithSpacing = block;
    if (![blockWithSpacing hasSuffix:@"\n"]) {
        blockWithSpacing = [blockWithSpacing stringByAppendingString:@"\n"];
    }
    blockWithSpacing = [NSString stringWithFormat:@"\n%@\n", blockWithSpacing];

    NSRange projectsRange = [result rangeOfString:@"(?m)^\\[projects\\." options:NSRegularExpressionSearch];
    if (projectsRange.location == NSNotFound) {
        if (result.length == 0) return [blockWithSpacing stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        return [result stringByAppendingString:blockWithSpacing];
    }

    NSMutableString *mutable = [result mutableCopy];
    [mutable insertString:blockWithSpacing atIndex:projectsRange.location];
    return [mutable copy];
}

- (nullable NSString *)managedProviderBaseURLFromContent:(NSString *)content {
    if (!content.length) return nil;

    NSString *blockPattern = [NSString stringWithFormat:@"(?ms)^\\[model_providers\\.%@\\]\\s*(.*?)(?=^\\[|\\z)", [NSRegularExpression escapedPatternForString:kManagedProviderName]];
    NSRegularExpression *blockRegex = [NSRegularExpression regularExpressionWithPattern:blockPattern options:0 error:nil];
    NSTextCheckingResult *blockMatch = [blockRegex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
    if (!blockMatch || blockMatch.numberOfRanges < 2) return nil;

    NSRange bodyRange = [blockMatch rangeAtIndex:1];
    if (bodyRange.location == NSNotFound) return nil;
    NSString *body = [content substringWithRange:bodyRange];

    NSRegularExpression *urlRegex = [NSRegularExpression regularExpressionWithPattern:@"(?m)^\\s*base_url\\s*=\\s*\"([^\"]+)\"\\s*$" options:0 error:nil];
    NSTextCheckingResult *m = [urlRegex firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    NSRange r = [m rangeAtIndex:1];
    if (r.location == NSNotFound) return nil;
    return [body substringWithRange:r];
}

#pragma mark - State file

- (BOOL)writeStateProfileName:(NSString *)name error:(NSError **)error {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) trimmed = @"";

    NSString *path = self.stateFilePath;
    NSError *writeError = nil;
    BOOL ok = [trimmed writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (!ok) {
        if (error) *error = writeError;
        return NO;
    }

    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0644)} ofItemAtPath:path error:nil];
    return YES;
}

- (nullable NSString *)codexSwitchProfileKeyForProfile:(CXProfile *)profile {
    if (!profile) return nil;

    // 1) If user already uses a codex_switch-supported key as the display name, keep it.
    NSString *trimmedName = [[profile.name ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (trimmedName.length > 0) {
        NSSet<NSString *> *allowed = [NSSet setWithArray:@[
            @"88code", @"anyrouter", @"anyrouter-5.1", @"anthropic",
            @"privnode", @"azure", @"ctl", @"paolu", @"hotaru", @"wong", @"york"
        ]];
        if ([allowed containsObject:trimmedName]) {
            return trimmedName;
        }
    }

    // 2) Infer by base URL (best-effort).
    NSString *normalized = [CXProfile normalizeBaseURL:profile.baseURL ?: @""];
    NSURLComponents *components = [NSURLComponents componentsWithString:normalized];
    NSString *host = components.host.lowercaseString ?: @"";
    NSString *path = components.path.lowercaseString ?: @"";
    if (host.length == 0) return nil;

    // Matches the common profiles in ~/.codex/codex_switch.sh (user's local setup).
    if ([host isEqualToString:@"wzw.pp.ua"]) return @"wong";
    if ([host isEqualToString:@"newapi.144500.xyz"]) return @"york";
    if ([host isEqualToString:@"runanytime.hxi.me"]) return @"paolu";
    if ([host isEqualToString:@"api.hotaruapi.top"]) return @"hotaru";
    if ([host isEqualToString:@"chat.199228.xyz"]) return @"ctl";
    if ([host isEqualToString:@"pro.privnode.com"]) return @"privnode";
    if ([host isEqualToString:@"c.cspok.cn"]) return @"anyrouter";
    if ([host isEqualToString:@"www.88code.org"]) return @"88code";
    if ([host isEqualToString:@"next.ke.com"] && [path containsString:@"/api/plugin/lite-llm"]) return @"azure";

    return nil;
}

@end
