//
//  CXProfileManager.m
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import "CXProfileManager.h"
#import "CXKeychainManager.h"

NSNotificationName const CXProfileDidChangeNotification = @"CXProfileDidChangeNotification";
NSNotificationName const CXActiveProfileDidChangeNotification = @"CXActiveProfileDidChangeNotification";

@interface CXProfileManager ()
@property (nonatomic, strong) NSMutableArray<CXProfile *> *profiles;
@end

@implementation CXProfileManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static CXProfileManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CXProfileManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _profiles = [NSMutableArray array];
        [self loadWithError:nil];
    }
    return self;
}

#pragma mark - Properties

- (NSArray<CXProfile *> *)allProfiles {
    return [self.profiles copy];
}

- (CXProfile *)activeProfile {
    if (!self.activeProfileId) return nil;
    return [self profileWithId:self.activeProfileId];
}

- (BOOL)isOfficialMode {
    return self.activeProfileId == nil;
}

- (NSUInteger)profileCount {
    return self.profiles.count;
}

#pragma mark - CRUD 操作

- (nullable CXProfile *)addProfileWithName:(NSString *)name 
                                   baseURL:(NSString *)baseURL 
                                    apiKey:(NSString *)apiKey 
                                     error:(NSError **)error {
    return [self addProfileWithName:name baseURL:baseURL model:nil apiKey:apiKey error:error];
}

- (nullable CXProfile *)addProfileWithName:(NSString *)name
                                   baseURL:(NSString *)baseURL
                                     model:(nullable NSString *)model
                                    apiKey:(NSString *)apiKey
                                     error:(NSError **)error {
    // 验证参数
    if (!name || name.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"名称不能为空"}];
        }
        return nil;
    }
    
    if (![CXProfile isValidBaseURL:baseURL]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-2 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Base URL 格式无效"}];
        }
        return nil;
    }
    
    NSString *normalizedKey = [CXKeychainManager normalizedAPIKeyFromUserInput:apiKey];
    if (!normalizedKey || normalizedKey.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-3 
                                     userInfo:@{NSLocalizedDescriptionKey: @"API Key 无效（请确认没有空格/换行等多余内容）"}];
        }
        return nil;
    }
    
    // 创建 Profile
    NSString *trimmedModel = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    CXProfile *profile = [CXProfile profileWithName:name baseURL:baseURL model:(trimmedModel.length > 0 ? trimmedModel : nil)];
    
    // 保存 API Key 到 Keychain
    NSError *keychainError = nil;
    BOOL keySaved = [[CXKeychainManager sharedManager] saveAPIKey:normalizedKey
                                                     forProfileId:profile.profileId 
                                                            error:&keychainError];
    if (!keySaved) {
        if (error) {
            *error = keychainError;
        }
        return nil;
    }
    
    // 添加到列表
    [self.profiles addObject:profile];
    
    // 保存到磁盘
    [self saveWithError:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXProfileDidChangeNotification object:profile];
    
    return profile;
}

- (BOOL)updateProfile:(CXProfile *)profile 
               apiKey:(nullable NSString *)apiKey 
                error:(NSError **)error {
    
    if (!profile) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-4 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Profile 不能为空"}];
        }
        return NO;
    }
    
    // 查找现有 Profile
    NSInteger index = [self indexOfProfileWithId:profile.profileId];
    if (index == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-5 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Profile 不存在"}];
        }
        return NO;
    }
    
    // 更新 API Key（如果提供）
    if (apiKey && apiKey.length > 0) {
        NSString *normalizedKey = [CXKeychainManager normalizedAPIKeyFromUserInput:apiKey];
        if (!normalizedKey || normalizedKey.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain"
                                             code:-3
                                         userInfo:@{NSLocalizedDescriptionKey: @"API Key 无效（请确认没有空格/换行等多余内容）"}];
            }
            return NO;
        }
        NSError *keychainError = nil;
        BOOL keySaved = [[CXKeychainManager sharedManager] updateAPIKey:normalizedKey
                                                           forProfileId:profile.profileId 
                                                                  error:&keychainError];
        if (!keySaved) {
            if (error) {
                *error = keychainError;
            }
            return NO;
        }
    }
    
    // 更新时间戳
    profile.updatedAt = [NSDate date];
    
    // 更新列表中的对象
    self.profiles[index] = profile;
    
    // 保存到磁盘
    [self saveWithError:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXProfileDidChangeNotification object:profile];
    
    return YES;
}

- (BOOL)deleteProfile:(CXProfile *)profile error:(NSError **)error {
    if (!profile) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-4 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Profile 不能为空"}];
        }
        return NO;
    }
    
    // 从 Keychain 删除 API Key
    [[CXKeychainManager sharedManager] deleteAPIKeyForProfileId:profile.profileId error:nil];
    
    // 从列表移除
    [self.profiles removeObject:profile];
    
    // 如果删除的是当前激活的 Profile，切换到 Official 模式
    if ([self.activeProfileId isEqualToString:profile.profileId]) {
        self.activeProfileId = nil;
        [[NSNotificationCenter defaultCenter] postNotificationName:CXActiveProfileDidChangeNotification object:nil];
    }
    
    // 保存到磁盘
    [self saveWithError:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXProfileDidChangeNotification object:nil];
    
    return YES;
}

- (nullable CXProfile *)duplicateProfile:(CXProfile *)profile {
    if (!profile) return nil;
    
    CXProfile *copy = [profile copy];
    copy.profileId = [[NSUUID UUID] UUIDString];
    copy.name = [NSString stringWithFormat:@"%@ (副本)", profile.name];
    copy.createdAt = [NSDate date];
    copy.updatedAt = [NSDate date];
    copy.lastUsedAt = nil;
    copy.active = NO;
    
    // 复制 API Key
    NSString *apiKey = [[CXKeychainManager sharedManager] getAPIKeyForProfileId:profile.profileId error:nil];
    if (apiKey) {
        [[CXKeychainManager sharedManager] saveAPIKey:apiKey forProfileId:copy.profileId error:nil];
    }
    
    // 添加到列表
    [self.profiles addObject:copy];
    
    // 保存到磁盘
    [self saveWithError:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXProfileDidChangeNotification object:copy];
    
    return copy;
}

- (nullable CXProfile *)profileWithId:(NSString *)profileId {
    if (!profileId) return nil;
    
    for (CXProfile *profile in self.profiles) {
        if ([profile.profileId isEqualToString:profileId]) {
            return profile;
        }
    }
    return nil;
}

- (NSInteger)indexOfProfileWithId:(NSString *)profileId {
    if (!profileId) return NSNotFound;
    
    for (NSInteger i = 0; i < self.profiles.count; i++) {
        if ([self.profiles[i].profileId isEqualToString:profileId]) {
            return i;
        }
    }
    return NSNotFound;
}

#pragma mark - 激活操作

- (BOOL)activateProfile:(CXProfile *)profile error:(NSError **)error {
    if (!profile) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-4 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Profile 不能为空"}];
        }
        return NO;
    }
    
    // 重置所有 Profile 的激活状态
    for (CXProfile *p in self.profiles) {
        p.active = NO;
    }
    
    // 激活指定 Profile
    profile.active = YES;
    profile.lastUsedAt = [NSDate date];
    self.activeProfileId = profile.profileId;
    
    // 保存到磁盘
    [self saveWithError:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXActiveProfileDidChangeNotification object:profile];
    
    return YES;
}

- (BOOL)switchToOfficialModeWithError:(NSError **)error {
    // 重置所有 Profile 的激活状态
    for (CXProfile *p in self.profiles) {
        p.active = NO;
    }
    
    self.activeProfileId = nil;
    
    // 保存到磁盘
    [self saveWithError:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXActiveProfileDidChangeNotification object:nil];
    
    return YES;
}

#pragma mark - 导入导出

- (nullable NSData *)exportProfilesIncludeKeys:(BOOL)includeKeys {
    NSMutableArray *exportArray = [NSMutableArray array];
    
    for (CXProfile *profile in self.profiles) {
        NSMutableDictionary *dict = [[profile toDictionary] mutableCopy];
        
        if (includeKeys) {
            NSString *apiKey = [[CXKeychainManager sharedManager] getAPIKeyForProfileId:profile.profileId error:nil];
            if (apiKey) {
                dict[@"apiKey"] = apiKey;
            }
        }
        
        [exportArray addObject:dict];
    }
    
    NSDictionary *exportData = @{
        @"version": @1,
        @"exportedAt": @([[NSDate date] timeIntervalSince1970]),
        @"profiles": exportArray
    };
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:exportData 
                                                       options:NSJSONWritingPrettyPrinted 
                                                         error:&error];
    return jsonData;
}

- (BOOL)importProfilesFromData:(NSData *)data error:(NSError **)error {
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-6 
                                     userInfo:@{NSLocalizedDescriptionKey: @"导入数据为空"}];
        }
        return NO;
    }
    
    NSError *parseError = nil;
    NSDictionary *importData = [NSJSONSerialization JSONObjectWithData:data 
                                                               options:0 
                                                                 error:&parseError];
    if (!importData) {
        if (error) {
            *error = parseError;
        }
        return NO;
    }
    
    NSArray *profilesArray = importData[@"profiles"];
    if (![profilesArray isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXProfileManagerErrorDomain" 
                                         code:-7 
                                     userInfo:@{NSLocalizedDescriptionKey: @"导入数据格式无效"}];
        }
        return NO;
    }
    
    for (NSDictionary *dict in profilesArray) {
        CXProfile *profile = [[CXProfile alloc] initWithDictionary:dict];
        
        // 生成新 ID 避免冲突
        profile.profileId = [[NSUUID UUID] UUIDString];
        profile.name = [NSString stringWithFormat:@"%@ (导入)", profile.name];
        
        // 如果有 API Key，保存到 Keychain
        NSString *apiKey = dict[@"apiKey"];
        if (apiKey && apiKey.length > 0) {
            [[CXKeychainManager sharedManager] saveAPIKey:apiKey forProfileId:profile.profileId error:nil];
        }
        
        [self.profiles addObject:profile];
    }
    
    // 保存到磁盘
    [self saveWithError:nil];
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:CXProfileDidChangeNotification object:nil];
    
    return YES;
}

#pragma mark - 持久化

+ (NSString *)profilesFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupportDir = [paths firstObject];
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.mccamera.demo.CXSwitch";
    NSString *appDir = [appSupportDir stringByAppendingPathComponent:bundleId];
    
    // 确保目录存在
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:appDir]) {
        [fm createDirectoryAtPath:appDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return [appDir stringByAppendingPathComponent:@"profiles.json"];
}

- (BOOL)saveWithError:(NSError **)error {
    NSMutableArray *profilesArray = [NSMutableArray array];
    
    for (CXProfile *profile in self.profiles) {
        [profilesArray addObject:[profile toDictionary]];
    }
    
    NSDictionary *saveData = @{
        @"version": @1,
        @"activeProfileId": self.activeProfileId ?: [NSNull null],
        @"profiles": profilesArray
    };
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:saveData 
                                                       options:NSJSONWritingPrettyPrinted 
                                                         error:&jsonError];
    if (!jsonData) {
        if (error) {
            *error = jsonError;
        }
        return NO;
    }
    
    NSString *path = [[self class] profilesFilePath];
    
    // 原子写入
    BOOL success = [jsonData writeToFile:path options:NSDataWritingAtomic error:error];
    
    return success;
}

- (BOOL)loadWithError:(NSError **)error {
    NSString *path = [[self class] profilesFilePath];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        // 文件不存在不算错误
        return YES;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) {
        return NO;
    }
    
    NSError *parseError = nil;
    NSDictionary *loadData = [NSJSONSerialization JSONObjectWithData:data 
                                                             options:0 
                                                               error:&parseError];
    if (!loadData) {
        if (error) {
            *error = parseError;
        }
        return NO;
    }
    
    // 解析 Profiles
    NSArray *profilesArray = loadData[@"profiles"];
    if ([profilesArray isKindOfClass:[NSArray class]]) {
        [self.profiles removeAllObjects];
        for (NSDictionary *dict in profilesArray) {
            CXProfile *profile = [[CXProfile alloc] initWithDictionary:dict];
            [self.profiles addObject:profile];
        }
    }
    
    // 解析激活的 Profile ID
    id activeId = loadData[@"activeProfileId"];
    if ([activeId isKindOfClass:[NSString class]]) {
        self.activeProfileId = activeId;
    }

    // 归一化 active 标记，避免 activeProfileId 与 profile.active 不一致
    if (self.activeProfileId.length > 0) {
        BOOL found = NO;
        for (CXProfile *profile in self.profiles) {
            BOOL isActive = [profile.profileId isEqualToString:self.activeProfileId];
            profile.active = isActive;
            if (isActive) found = YES;
        }
        if (!found) {
            self.activeProfileId = nil;
            for (CXProfile *profile in self.profiles) {
                profile.active = NO;
            }
        }
    } else {
        for (CXProfile *profile in self.profiles) {
            profile.active = NO;
        }
    }
    
    return YES;
}

@end
