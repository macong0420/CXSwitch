//
//  CXConfigManager.h
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import <Foundation/Foundation.h>
#import "CXProfile.h"

NS_ASSUME_NONNULL_BEGIN

/// 配置变更通知
extern NSNotificationName const CXConfigDidApplyNotification;

/**
 * CXConfigManager - Codex 配置文件管理器
 * 负责读写 ~/.codex/config.toml 和 ~/.codex/auth.json
 */
@interface CXConfigManager : NSObject

/// 单例
+ (instancetype)sharedManager;

#pragma mark - 路径

/// ~/.codex 目录路径
@property (nonatomic, readonly) NSString *codexDirectoryPath;

/// config.toml 路径
@property (nonatomic, readonly) NSString *configTomlPath;

/// auth.json 路径
@property (nonatomic, readonly) NSString *authJsonPath;

/// auth.json 备份路径
@property (nonatomic, readonly) NSString *authJsonBackupPath;

#pragma mark - Apply Profile

/// 应用 API Key Profile
/// @param profile 要应用的 Profile
/// @param apiKey API Key
/// @param error 错误信息
/// @return 是否成功
- (BOOL)applyProfile:(CXProfile *)profile 
              apiKey:(NSString *)apiKey 
               error:(NSError **)error;

/// 应用 Official 登录模式
/// @param error 错误信息
/// @return 是否成功
- (BOOL)applyOfficialModeWithError:(NSError **)error;

#pragma mark - 状态读取

/// 获取当前配置状态
/// @return 状态字典
- (NSDictionary *)currentConfigStatus;

/// 检查 auth.json 是否存在且有效
- (BOOL)hasValidAuthJson;

/// 检查备份是否存在
- (BOOL)hasAuthJsonBackup;

/// 恢复备份
/// @param error 错误信息
/// @return 是否成功
- (BOOL)restoreAuthJsonBackupWithError:(NSError **)error;

#pragma mark - TOML 操作

/// 读取 config.toml 内容
/// @return TOML 文件内容
- (nullable NSString *)readConfigToml;

/// 读取 config.toml 并解析 projects 段（保留）
/// @return projects 段内容
- (nullable NSString *)extractProjectsSection;

#pragma mark - Provider 名称

/// App 管理的 provider 名称
@property (class, nonatomic, readonly) NSString *managedProviderName;

@end

NS_ASSUME_NONNULL_END
