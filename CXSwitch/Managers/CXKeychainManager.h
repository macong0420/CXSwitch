//
//  CXKeychainManager.h
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Keychain 服务标识符
extern NSString * const CXKeychainService;

/**
 * CXKeychainManager - Keychain 操作管理器
 * 用于安全存储 API Key
 */
@interface CXKeychainManager : NSObject

/// 单例
+ (instancetype)sharedManager;

#pragma mark - API Key 操作

/// 保存 API Key
/// @param apiKey 要保存的 API Key
/// @param profileId 关联的 Profile ID
/// @param error 错误信息
/// @return 是否成功
- (BOOL)saveAPIKey:(NSString *)apiKey 
      forProfileId:(NSString *)profileId 
             error:(NSError **)error;

/// 获取 API Key
/// @param profileId Profile ID
/// @param error 错误信息
/// @return API Key（找不到返回 nil）
- (nullable NSString *)getAPIKeyForProfileId:(NSString *)profileId 
                                       error:(NSError **)error;

/// 删除 API Key
/// @param profileId Profile ID
/// @param error 错误信息
/// @return 是否成功
- (BOOL)deleteAPIKeyForProfileId:(NSString *)profileId 
                           error:(NSError **)error;

/// 检查是否存在 API Key
/// @param profileId Profile ID
/// @return 是否存在
- (BOOL)hasAPIKeyForProfileId:(NSString *)profileId;

/// 更新 API Key（如果存在则更新，不存在则创建）
/// @param apiKey 新的 API Key
/// @param profileId Profile ID
/// @param error 错误信息
/// @return 是否成功
- (BOOL)updateAPIKey:(NSString *)apiKey 
        forProfileId:(NSString *)profileId 
               error:(NSError **)error;

#pragma mark - 批量操作

/// 删除所有 API Key（谨慎使用）
/// @param error 错误信息
/// @return 是否成功
- (BOOL)deleteAllAPIKeysWithError:(NSError **)error;

/// 获取所有存储的 Profile ID 列表
/// @return Profile ID 数组
- (NSArray<NSString *> *)allStoredProfileIds;

#pragma mark - 工具方法

/// 归一化并校验用户输入的 API Key（trim；若包含空格/换行则视为无效）
/// @param apiKey 用户输入
/// @return 归一化后的 key；无效则返回 nil
+ (nullable NSString *)normalizedAPIKeyFromUserInput:(nullable NSString *)apiKey;

/// 脱敏 API Key（只显示前4位和后4位）
/// @param apiKey 原始 API Key
/// @return 脱敏后的字符串
+ (NSString *)sanitizeAPIKey:(NSString *)apiKey;

@end

NS_ASSUME_NONNULL_END
