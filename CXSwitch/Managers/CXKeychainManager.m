//
//  CXKeychainManager.m
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import "CXKeychainManager.h"
#import <Security/Security.h>

NSString * const CXKeychainService = @"com.macongcong.CodexSwitcher";

@implementation CXKeychainManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static CXKeychainManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CXKeychainManager alloc] init];
    });
    return instance;
}

#pragma mark - Private Helpers

- (NSMutableDictionary *)baseQueryForProfileId:(NSString *)profileId {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = CXKeychainService;
    query[(__bridge id)kSecAttrAccount] = profileId;
    return query;
}

- (NSError *)errorWithCode:(OSStatus)status message:(NSString *)message {
    NSString *description = (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL) ?: @"Unknown Keychain error";
    return [NSError errorWithDomain:@"CXKeychainManagerErrorDomain" 
                               code:status 
                           userInfo:@{
                               NSLocalizedDescriptionKey: message,
                               NSLocalizedFailureReasonErrorKey: description
                           }];
}

#pragma mark - API Key 操作

- (BOOL)saveAPIKey:(NSString *)apiKey 
      forProfileId:(NSString *)profileId 
             error:(NSError **)error {
    
    NSString *normalizedKey = [[self class] normalizedAPIKeyFromUserInput:apiKey];
    if (!normalizedKey || normalizedKey.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXKeychainManagerErrorDomain" 
                                         code:-1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"API Key 无效（请确认没有空格/换行等多余内容）"}];
        }
        return NO;
    }
    
    if (!profileId || profileId.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXKeychainManagerErrorDomain" 
                                         code:-2 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Profile ID cannot be empty"}];
        }
        return NO;
    }
    
    // 先删除可能存在的旧值
    [self deleteAPIKeyForProfileId:profileId error:nil];
    
    // 创建新条目
    NSMutableDictionary *query = [self baseQueryForProfileId:profileId];
    NSData *keyData = [normalizedKey dataUsingEncoding:NSUTF8StringEncoding];
    query[(__bridge id)kSecValueData] = keyData;
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;
    
    // 添加描述
    query[(__bridge id)kSecAttrLabel] = @"CXSwitch API Key";
    query[(__bridge id)kSecAttrDescription] = @"API Key for Codex profile";
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    
    if (status == errSecSuccess) {
        return YES;
    } else {
        if (error) {
            *error = [self errorWithCode:status message:@"Failed to save API Key to Keychain"];
        }
        return NO;
    }
}

- (nullable NSString *)getAPIKeyForProfileId:(NSString *)profileId 
                                       error:(NSError **)error {
    
    if (!profileId || profileId.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXKeychainManagerErrorDomain" 
                                         code:-2 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Profile ID cannot be empty"}];
        }
        return nil;
    }
    
    NSMutableDictionary *query = [self baseQueryForProfileId:profileId];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    
    if (status == errSecSuccess && result != NULL) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSString *apiKey = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return apiKey;
    } else if (status == errSecItemNotFound) {
        // 未找到不算错误
        return nil;
    } else {
        if (error) {
            *error = [self errorWithCode:status message:@"Failed to retrieve API Key from Keychain"];
        }
        return nil;
    }
}

- (BOOL)deleteAPIKeyForProfileId:(NSString *)profileId 
                           error:(NSError **)error {
    
    if (!profileId || profileId.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"CXKeychainManagerErrorDomain" 
                                         code:-2 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Profile ID cannot be empty"}];
        }
        return NO;
    }
    
    NSMutableDictionary *query = [self baseQueryForProfileId:profileId];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    
    if (status == errSecSuccess || status == errSecItemNotFound) {
        return YES;
    } else {
        if (error) {
            *error = [self errorWithCode:status message:@"Failed to delete API Key from Keychain"];
        }
        return NO;
    }
}

- (BOOL)hasAPIKeyForProfileId:(NSString *)profileId {
    if (!profileId || profileId.length == 0) return NO;
    
    NSMutableDictionary *query = [self baseQueryForProfileId:profileId];
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

- (BOOL)updateAPIKey:(NSString *)apiKey 
        forProfileId:(NSString *)profileId 
               error:(NSError **)error {
    // 使用 save 方法，它会先删除再添加
    return [self saveAPIKey:apiKey forProfileId:profileId error:error];
}

#pragma mark - 批量操作

- (BOOL)deleteAllAPIKeysWithError:(NSError **)error {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = CXKeychainService;
    
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    
    if (status == errSecSuccess || status == errSecItemNotFound) {
        return YES;
    } else {
        if (error) {
            *error = [self errorWithCode:status message:@"Failed to delete all API Keys"];
        }
        return NO;
    }
}

- (NSArray<NSString *> *)allStoredProfileIds {
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    query[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    query[(__bridge id)kSecAttrService] = CXKeychainService;
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
    
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    
    if (status == errSecSuccess && result != NULL) {
        NSArray *items = (__bridge_transfer NSArray *)result;
        NSMutableArray *profileIds = [NSMutableArray array];
        
        for (NSDictionary *item in items) {
            NSString *account = item[(__bridge id)kSecAttrAccount];
            if (account) {
                [profileIds addObject:account];
            }
        }
        
        return [profileIds copy];
    }
    
    return @[];
}

#pragma mark - 工具方法

+ (nullable NSString *)normalizedAPIKeyFromUserInput:(nullable NSString *)apiKey {
    if (![apiKey isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [apiKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;
    // Keys should not contain whitespace/newlines; it usually indicates extra copied text.
    NSRange ws = [trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (ws.location != NSNotFound) return nil;
    return trimmed;
}

+ (NSString *)sanitizeAPIKey:(NSString *)apiKey {
    if (!apiKey || apiKey.length < 8) {
        return @"****";
    }
    
    NSString *prefix = [apiKey substringToIndex:4];
    NSString *suffix = [apiKey substringFromIndex:apiKey.length - 4];
    NSInteger maskLength = apiKey.length - 8;
    NSString *mask = [@"" stringByPaddingToLength:MIN(maskLength, 8) 
                                       withString:@"*" 
                                  startingAtIndex:0];
    
    return [NSString stringWithFormat:@"%@%@%@", prefix, mask, suffix];
}

@end
