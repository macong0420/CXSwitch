//
//  CXProfile.h
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * CXProfile - Codex 配置 Profile 数据模型
 * API Key 不在此存储，仅存于 Keychain
 */
@interface CXProfile : NSObject <NSSecureCoding, NSCopying>

/// UUID 唯一标识符
@property (nonatomic, copy) NSString *profileId;

/// 显示名称
@property (nonatomic, copy) NSString *name;

/// API Base URL (e.g., https://api.openai.com/v1)
@property (nonatomic, copy) NSString *baseURL;

/// Model (e.g., gpt-5.2). Optional; if empty, CXSwitch will use a default.
@property (nonatomic, copy, nullable) NSString *model;

/// Optional provider HTTP headers (e.g., Azure proxy headers).
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *httpHeaders;

/// Some providers require OpenAI-style auth semantics.
@property (nonatomic, assign) BOOL requiresOpenAIAuth;

/// 创建时间
@property (nonatomic, strong) NSDate *createdAt;

/// 更新时间
@property (nonatomic, strong) NSDate *updatedAt;

/// 最后使用时间
@property (nonatomic, strong, nullable) NSDate *lastUsedAt;

/// 当前是否激活
@property (nonatomic, assign, getter=isActive) BOOL active;

/// 可选备注
@property (nonatomic, copy, nullable) NSString *notes;

#pragma mark - Initializers

/// 创建新 Profile（自动生成 UUID 和时间戳）
+ (instancetype)profileWithName:(NSString *)name baseURL:(NSString *)baseURL;

/// 创建新 Profile（可选指定 model）
+ (instancetype)profileWithName:(NSString *)name baseURL:(NSString *)baseURL model:(nullable NSString *)model;

/// 从字典初始化（用于 JSON 解析）
- (instancetype)initWithDictionary:(NSDictionary *)dict;

/// 转换为字典（用于 JSON 序列化）
- (NSDictionary *)toDictionary;

#pragma mark - Helpers

/// 规范化 Base URL（确保格式正确，末尾无斜杠）
+ (NSString *)normalizeBaseURL:(NSString *)url;

/// 验证 Base URL 格式
+ (BOOL)isValidBaseURL:(NSString *)url;

/// 脱敏的 Base URL（用于日志）
- (NSString *)sanitizedBaseURL;

@end

NS_ASSUME_NONNULL_END
