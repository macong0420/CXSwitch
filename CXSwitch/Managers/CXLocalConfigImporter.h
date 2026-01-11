//
//  CXLocalConfigImporter.h
//  CXSwitch
//
//  Created by Codex CLI on 2026/1/10.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CXLocalConfigImportCandidate : NSObject

@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *baseURL;
@property(nonatomic, copy, nullable) NSString *model;
@property(nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *httpHeaders;
@property(nonatomic, assign) BOOL requiresOpenAIAuth;
@property(nonatomic, copy, nullable) NSString *apiKey;
@property(nonatomic, copy, nullable) NSString *notes;

@end

/**
 * CXLocalConfigImporter - 从本地配置导入 Profiles
 *
 * 支持：
 * - `.env` 文件：解析 OPENAI_API_KEY / OPENAI_BASE_URL 等
 * - `.codex` 目录：解析 config.toml/config_*.toml 中的 model_providers.*.base_url，并尝试从 auth.json 读取 OPENAI_API_KEY
 *
 * 注意：不会递归扫描目录，仅对用户选择的文件/目录进行解析。
 */
@interface CXLocalConfigImporter : NSObject

/// 从本地路径解析候选 Profiles（文件或目录）
+ (NSArray<CXLocalConfigImportCandidate *> *)candidatesFromPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
