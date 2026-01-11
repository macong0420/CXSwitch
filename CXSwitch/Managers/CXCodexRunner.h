//
//  CXCodexRunner.h
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Codex 命令执行完成回调
typedef void (^CXCodexRunnerCompletion)(int exitCode, NSString * _Nullable stdoutOutput, NSString * _Nullable stderrOutput);

/// Codex 版本检查完成回调
typedef void (^CXCodexVersionCompletion)(NSString * _Nullable version, NSError * _Nullable error);

/// Codex 登录状态检查完成回调
typedef void (^CXCodexLoginStatusCompletion)(NSString * _Nullable status, BOOL isLoggedIn, NSError * _Nullable error);

/**
 * CXCodexRunner - Codex 可执行文件管理器
 * 负责探测 codex 路径并执行命令
 */
@interface CXCodexRunner : NSObject

/// 单例
+ (instancetype)sharedRunner;

#pragma mark - Properties

/// Codex 可执行文件路径（用户可手动指定）
@property (nonatomic, copy, nullable) NSString *codexPath;

/// 当前检测到的 Codex 版本
@property (nonatomic, copy, readonly, nullable) NSString *detectedVersion;

/// 是否已检测到可用的 Codex
@property (nonatomic, readonly) BOOL isCodexAvailable;

#pragma mark - 路径探测

/// 自动探测可用的 codex 路径
/// @return 探测到的路径（找不到返回 nil）
- (nullable NSString *)detectCodexPath;

/// 获取所有候选路径
/// @return 候选路径数组
- (NSArray<NSString *> *)candidatePaths;

/// 验证指定路径是否为可用的 codex
/// @param path 路径
/// @return 是否可用
- (BOOL)validateCodexAtPath:(NSString *)path;

#pragma mark - 命令执行

/// 执行 codex 命令
/// @param args 命令参数
/// @param completion 完成回调
- (void)runCodexWithArgs:(NSArray<NSString *> *)args 
              completion:(CXCodexRunnerCompletion)completion;

/// 同步执行 codex 命令（会阻塞当前线程）
/// @param args 命令参数
/// @param stdoutOutput 标准输出
/// @param stderrOutput 标准错误
/// @return 退出码
- (int)runCodexSyncWithArgs:(NSArray<NSString *> *)args 
               stdoutOutput:(NSString * _Nullable * _Nullable)stdoutOutput 
               stderrOutput:(NSString * _Nullable * _Nullable)stderrOutput;

#pragma mark - 健康检查

/// 检查 Codex 版本
/// @param completion 完成回调
- (void)checkVersionWithCompletion:(CXCodexVersionCompletion)completion;

/// 检查登录状态
/// @param completion 完成回调
- (void)checkLoginStatusWithCompletion:(CXCodexLoginStatusCompletion)completion;

/// 触发登录流程
/// @param completion 完成回调（注意：登录需要用户在浏览器中操作）
- (void)triggerLoginWithCompletion:(void (^)(BOOL started, NSError * _Nullable error))completion;

#pragma mark - 工具方法

/// 脱敏命令输出（移除敏感信息）
+ (NSString *)sanitizeOutput:(NSString *)output;

@end

NS_ASSUME_NONNULL_END
