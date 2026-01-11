//
//  CXProfileManager.h
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import <Foundation/Foundation.h>
#import "CXProfile.h"

NS_ASSUME_NONNULL_BEGIN

/// Profile 变更通知
extern NSNotificationName const CXProfileDidChangeNotification;
extern NSNotificationName const CXActiveProfileDidChangeNotification;

/**
 * CXProfileManager - Profile 管理器
 * 负责 Profile 的 CRUD、持久化和状态管理
 */
@interface CXProfileManager : NSObject

/// 单例
+ (instancetype)sharedManager;

#pragma mark - Properties

/// 所有 Profiles
@property (nonatomic, readonly) NSArray<CXProfile *> *allProfiles;

/// 当前激活的 Profile ID（nil 表示 Official 模式）
@property (nonatomic, copy, nullable) NSString *activeProfileId;

/// 当前激活的 Profile 对象
@property (nonatomic, readonly, nullable) CXProfile *activeProfile;

/// 是否为 Official 模式
@property (nonatomic, readonly) BOOL isOfficialMode;

/// Profile 总数
@property (nonatomic, readonly) NSUInteger profileCount;

#pragma mark - CRUD 操作

/// 添加新 Profile
/// @param name 名称
/// @param baseURL Base URL
/// @param apiKey API Key（将存入 Keychain）
/// @param error 错误信息
/// @return 创建的 Profile（失败返回 nil）
- (nullable CXProfile *)addProfileWithName:(NSString *)name 
                                   baseURL:(NSString *)baseURL 
                                    apiKey:(NSString *)apiKey 
                                     error:(NSError **)error;

/// 添加新 Profile（可选指定 model）
/// @param name 名称
/// @param baseURL Base URL
/// @param model model（可选）
/// @param apiKey API Key（将存入 Keychain）
/// @param error 错误信息
/// @return 创建的 Profile（失败返回 nil）
- (nullable CXProfile *)addProfileWithName:(NSString *)name
                                   baseURL:(NSString *)baseURL
                                     model:(nullable NSString *)model
                                    apiKey:(NSString *)apiKey
                                     error:(NSError **)error;

/// 更新 Profile
/// @param profile 要更新的 Profile
/// @param apiKey 新的 API Key（传 nil 则不更新 Key）
/// @param error 错误信息
/// @return 是否成功
- (BOOL)updateProfile:(CXProfile *)profile 
               apiKey:(nullable NSString *)apiKey 
                error:(NSError **)error;

/// 删除 Profile
/// @param profile 要删除的 Profile
/// @param error 错误信息
/// @return 是否成功
- (BOOL)deleteProfile:(CXProfile *)profile error:(NSError **)error;

/// 复制 Profile
/// @param profile 要复制的 Profile
/// @return 复制后的新 Profile
- (nullable CXProfile *)duplicateProfile:(CXProfile *)profile;

/// 根据 ID 获取 Profile
/// @param profileId Profile ID
/// @return Profile 对象（找不到返回 nil）
- (nullable CXProfile *)profileWithId:(NSString *)profileId;

#pragma mark - 激活操作

/// 激活指定 Profile
/// @param profile 要激活的 Profile
/// @param error 错误信息
/// @return 是否成功
- (BOOL)activateProfile:(CXProfile *)profile error:(NSError **)error;

/// 切换到 Official 模式
/// @param error 错误信息
/// @return 是否成功
- (BOOL)switchToOfficialModeWithError:(NSError **)error;

#pragma mark - 导入导出

/// 导出所有 Profiles
/// @param includeKeys 是否包含 API Key（Keychain 中）
/// @return JSON 数据
- (nullable NSData *)exportProfilesIncludeKeys:(BOOL)includeKeys;

/// 从数据导入 Profiles
/// @param data JSON 数据
/// @param error 错误信息
/// @return 是否成功
- (BOOL)importProfilesFromData:(NSData *)data error:(NSError **)error;

#pragma mark - 持久化

/// 保存到磁盘
/// @param error 错误信息
/// @return 是否成功
- (BOOL)saveWithError:(NSError **)error;

/// 从磁盘加载
/// @param error 错误信息
/// @return 是否成功
- (BOOL)loadWithError:(NSError **)error;

/// 获取存储路径
+ (NSString *)profilesFilePath;

@end

NS_ASSUME_NONNULL_END
