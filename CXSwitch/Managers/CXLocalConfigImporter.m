//
//  CXLocalConfigImporter.m
//  CXSwitch
//
//  Created by Codex CLI on 2026/1/10.
//

#import "CXLocalConfigImporter.h"

@implementation CXLocalConfigImportCandidate
@end

@implementation CXLocalConfigImporter

+ (nullable NSString *)normalizedAPIKey:(nullable NSString *)value {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;
    // API keys should not contain whitespace/newlines; this usually indicates accidental copy of extra text.
    NSRange ws = [trimmed rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (ws.location != NSNotFound) return nil;
    return trimmed;
}

+ (nullable NSString *)topLevelTomlStringValueForKey:(NSString *)key inContent:(NSString *)content {
    if (key.length == 0 || content.length == 0) return nil;
    NSString *pattern = [NSString stringWithFormat:@"(?m)^\\s*%@\\s*=\\s*\"([^\"]+)\"\\s*$",
                         [NSRegularExpression escapedPatternForString:key]];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [regex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    NSRange r = [m rangeAtIndex:1];
    if (r.location == NSNotFound) return nil;
    NSString *value = [content substringWithRange:r];
    return value.length > 0 ? value : nil;
}

+ (NSArray<CXLocalConfigImportCandidate *> *)candidatesFromPath:(NSString *)path {
    if (path.length == 0) return @[];

    BOOL isDir = NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return @[];

    if (isDir) {
        return [self candidatesFromDirectory:path];
    }

    NSString *last = path.lastPathComponent.lowercaseString;
    if ([last isEqualToString:@".env"] || [last hasSuffix:@".env"] || [last hasPrefix:@".env."]) {
        CXLocalConfigImportCandidate *candidate = [self candidateFromEnvFile:path];
        return candidate ? @[candidate] : @[];
    }

    if ([last hasSuffix:@".sh"]) {
        // Only support Codex switch scripts; avoid importing unrelated scripts (e.g. Claude/Anthropic switchers).
        if ([last isEqualToString:@"codex_switch.sh"]) {
            return [self candidatesFromSwitchScript:path];
        }
        return @[];
    }

    if ([last isEqualToString:@"config.toml"] || [last hasSuffix:@".toml"]) {
        // treat as a codex config file; baseURL can be inferred from model_providers
        return [self candidatesFromCodexConfigFile:path codexDirectory:path.stringByDeletingLastPathComponent];
    }

    if ([last isEqualToString:@"auth.json"] || [last hasSuffix:@".json"]) {
        // JSON 结构不稳定；目前只支持 `.codex/auth.json` 由目录级处理
        return @[];
    }

    return @[];
}

#pragma mark - Directory scan (non-recursive)

+ (NSArray<CXLocalConfigImportCandidate *> *)candidatesFromDirectory:(NSString *)dir {
    NSMutableArray<CXLocalConfigImportCandidate *> *results = [NSMutableArray array];

    NSString *normalized = [dir stringByExpandingTildeInPath];
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1) If user picked a .codex directory directly
    if ([normalized.lastPathComponent isEqualToString:@".codex"]) {
        [results addObjectsFromArray:[self candidatesFromCodexDirectory:normalized]];
        return results;
    }

    // 2) Check common env filenames in this directory (non-recursive)
    NSArray<NSString *> *envNames = @[
        @".env",
        @".env.local",
        @".env.development",
        @".env.production",
        @".env.staging"
    ];

    for (NSString *name in envNames) {
        NSString *envPath = [normalized stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:envPath]) {
            CXLocalConfigImportCandidate *candidate = [self candidateFromEnvFile:envPath];
            if (candidate) [results addObject:candidate];
        }
    }

    // 3) Check `.codex` folder inside the chosen directory
    NSString *codexDir = [normalized stringByAppendingPathComponent:@".codex"];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:codexDir isDirectory:&isDir] && isDir) {
        [results addObjectsFromArray:[self candidatesFromCodexDirectory:codexDir]];
    }

    // 4) Check common switch scripts in this directory
    // CXSwitch focuses on Codex; avoid importing Claude/Anthropic switch scripts which typically do not map 1:1.
    NSArray<NSString *> *scriptNames = @[@"codex_switch.sh"];
    for (NSString *name in scriptNames) {
        NSString *scriptPath = [normalized stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:scriptPath]) {
            [results addObjectsFromArray:[self candidatesFromSwitchScript:scriptPath]];
        }
    }

    return results;
}

#pragma mark - .env parsing

+ (nullable CXLocalConfigImportCandidate *)candidateFromEnvFile:(NSString *)envPath {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:envPath encoding:NSUTF8StringEncoding error:&error];
    if (content.length == 0) return nil;

    NSDictionary<NSString *, NSString *> *vars = [self parseEnvContent:content];

    NSString *apiKey = vars[@"OPENAI_API_KEY"];
    NSString *baseURL = vars[@"OPENAI_BASE_URL"];
    if (baseURL.length == 0) baseURL = vars[@"OPENAI_API_BASE"];
    if (baseURL.length == 0) baseURL = vars[@"OPENAI_BASEURL"];

    if (baseURL.length == 0 && apiKey.length == 0) return nil;

    CXLocalConfigImportCandidate *c = [[CXLocalConfigImportCandidate alloc] init];
    c.name = [NSString stringWithFormat:@"导入 %@", envPath.lastPathComponent];
    c.baseURL = baseURL ?: @"";
    c.apiKey = apiKey;
    c.notes = [NSString stringWithFormat:@"Imported from %@", envPath];
    return c;
}

+ (NSDictionary<NSString *, NSString *> *)parseEnvContent:(NSString *)content {
    NSMutableDictionary<NSString *, NSString *> *vars = [NSMutableDictionary dictionary];
    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;
        if ([line hasPrefix:@"#"]) continue;

        if ([line hasPrefix:@"export "]) {
            line = [[line substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }

        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;

        NSString *key = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [[line substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length == 0) continue;

        // Remove inline comments if value is not quoted
        if (value.length > 0 && ![value hasPrefix:@"\""] && ![value hasPrefix:@"'"]) {
            NSRange hash = [value rangeOfString:@"#"];
            if (hash.location != NSNotFound) {
                value = [[value substringToIndex:hash.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
        }

        value = [self unquoteEnvValue:value];
        if (value.length == 0) continue;

        vars[key] = value;
    }

    return vars;
}

+ (NSString *)unquoteEnvValue:(NSString *)value {
    if (value.length >= 2) {
        unichar first = [value characterAtIndex:0];
        unichar last = [value characterAtIndex:value.length - 1];
        if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
            return [value substringWithRange:NSMakeRange(1, value.length - 2)];
        }
    }
    return value;
}

#pragma mark - .codex parsing

+ (NSArray<CXLocalConfigImportCandidate *> *)candidatesFromCodexDirectory:(NSString *)codexDir {
    NSMutableArray<CXLocalConfigImportCandidate *> *results = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *authPath = [codexDir stringByAppendingPathComponent:@"auth.json"];
    NSString *apiKey = [self apiKeyFromCodexAuthJson:authPath];

    // If a codex_switch.sh exists, import per-profile configs/keys when possible.
    NSString *switchScript = [codexDir stringByAppendingPathComponent:@"codex_switch.sh"];
    if ([fm fileExistsAtPath:switchScript]) {
        [results addObjectsFromArray:[self candidatesFromSwitchScript:switchScript]];
    }

    NSError *error = nil;
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:codexDir error:&error];
    if (contents.count == 0) return results;

    for (NSString *name in contents) {
        if (![name hasSuffix:@".toml"]) continue;
        NSString *full = [codexDir stringByAppendingPathComponent:name];
        // Only import TOML-only candidates when we can also provide a usable API key.
        if (apiKey.length > 0) {
            [results addObjectsFromArray:[self candidatesFromCodexConfigFile:full codexDirectory:codexDir defaultAPIKey:apiKey]];
        }
    }

    return results;
}

+ (NSArray<CXLocalConfigImportCandidate *> *)candidatesFromCodexConfigFile:(NSString *)path codexDirectory:(NSString *)codexDir {
    NSString *apiKey = [self apiKeyFromCodexAuthJson:[codexDir stringByAppendingPathComponent:@"auth.json"]];
    return [self candidatesFromCodexConfigFile:path codexDirectory:codexDir defaultAPIKey:apiKey];
}

+ (NSArray<CXLocalConfigImportCandidate *> *)candidatesFromCodexConfigFile:(NSString *)path
                                                             codexDirectory:(NSString *)codexDir
                                                              defaultAPIKey:(nullable NSString *)defaultAPIKey {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (content.length == 0) return @[];

    NSDictionary<NSString *, NSString *> *providers = [self parseTomlModelProvidersBaseURLs:content];
    if (providers.count == 0) return @[];

    NSString *model = [self topLevelTomlStringValueForKey:@"model" inContent:content];
    NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *headersByProvider = [self parseTomlModelProvidersHTTPHeaders:content];
    NSDictionary<NSString *, NSNumber *> *requiresByProvider = [self parseTomlModelProvidersRequiresOpenAIAuth:content];

    NSMutableArray<CXLocalConfigImportCandidate *> *results = [NSMutableArray array];
    NSString *baseName = path.lastPathComponent;

    for (NSString *providerName in providers) {
        NSString *baseURL = providers[providerName];
        if (baseURL.length == 0) continue;

        CXLocalConfigImportCandidate *c = [[CXLocalConfigImportCandidate alloc] init];
        c.name = [NSString stringWithFormat:@"导入 %@:%@", baseName, providerName];
        c.baseURL = baseURL;
        c.model = model;
        c.httpHeaders = headersByProvider[providerName];
        c.requiresOpenAIAuth = [requiresByProvider[providerName] boolValue];
        c.apiKey = defaultAPIKey;
        c.notes = [NSString stringWithFormat:@"Imported from %@ (%@)", path, codexDir];
        [results addObject:c];
    }

    return results;
}

+ (nullable NSString *)apiKeyFromCodexAuthJson:(NSString *)authPath {
    NSData *data = [NSData dataWithContentsOfFile:authPath];
    if (!data) return nil;

    NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;

    id value = obj[@"OPENAI_API_KEY"];
    return [self normalizedAPIKey:value];
    return nil;
}

+ (NSDictionary<NSString *, NSString *> *)parseTomlModelProvidersBaseURLs:(NSString *)content {
    // Best-effort TOML parsing using regex: find blocks [model_providers.<name>] and base_url = "..."
    NSMutableDictionary<NSString *, NSString *> *results = [NSMutableDictionary dictionary];

    NSString *blockPattern = @"(?ms)^\\[model_providers\\.([A-Za-z0-9_\\-]+)\\]\\s*(.*?)(?=^\\[|\\z)";
    NSRegularExpression *blockRegex = [NSRegularExpression regularExpressionWithPattern:blockPattern options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [blockRegex matchesInString:content options:0 range:NSMakeRange(0, content.length)];

    NSRegularExpression *baseURLRegex = [NSRegularExpression regularExpressionWithPattern:@"(?m)^\\s*base_url\\s*=\\s*\"([^\"]+)\"\\s*$" options:0 error:nil];

    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 3) continue;
        NSRange nameRange = [m rangeAtIndex:1];
        NSRange bodyRange = [m rangeAtIndex:2];
        if (nameRange.location == NSNotFound || bodyRange.location == NSNotFound) continue;

        NSString *provider = [content substringWithRange:nameRange];
        NSString *body = [content substringWithRange:bodyRange];

        NSTextCheckingResult *urlMatch = [baseURLRegex firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        if (urlMatch.numberOfRanges < 2) continue;
        NSRange urlRange = [urlMatch rangeAtIndex:1];
        if (urlRange.location == NSNotFound) continue;

        NSString *url = [body substringWithRange:urlRange];
        if (url.length > 0) {
            results[provider] = url;
        }
    }

    return results;
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)parseTomlModelProvidersHTTPHeaders:(NSString *)content {
    // Parse blocks like [model_providers.<name>.http_headers]
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *results = [NSMutableDictionary dictionary];
    if (content.length == 0) return results;

    NSString *blockPattern = @"(?ms)^\\[model_providers\\.([A-Za-z0-9_\\-]+)\\.http_headers\\]\\s*(.*?)(?=^\\[|\\z)";
    NSRegularExpression *blockRegex = [NSRegularExpression regularExpressionWithPattern:blockPattern options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [blockRegex matchesInString:content options:0 range:NSMakeRange(0, content.length)];

    NSRegularExpression *kvRegex = [NSRegularExpression regularExpressionWithPattern:@"(?m)^\\s*([A-Za-z0-9_\\-\\.]+)\\s*=\\s*\"([^\"]*)\"\\s*$" options:0 error:nil];

    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 3) continue;
        NSRange nameRange = [m rangeAtIndex:1];
        NSRange bodyRange = [m rangeAtIndex:2];
        if (nameRange.location == NSNotFound || bodyRange.location == NSNotFound) continue;

        NSString *provider = [content substringWithRange:nameRange];
        NSString *body = [content substringWithRange:bodyRange];

        NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
        NSArray<NSTextCheckingResult *> *kvs = [kvRegex matchesInString:body options:0 range:NSMakeRange(0, body.length)];
        for (NSTextCheckingResult *kv in kvs) {
            if (kv.numberOfRanges < 3) continue;
            NSRange kRange = [kv rangeAtIndex:1];
            NSRange vRange = [kv rangeAtIndex:2];
            if (kRange.location == NSNotFound || vRange.location == NSNotFound) continue;
            NSString *k = [body substringWithRange:kRange];
            NSString *v = [body substringWithRange:vRange];
            if (k.length == 0) continue;
            headers[k] = v ?: @"";
        }
        if (headers.count > 0) {
            results[provider] = [headers copy];
        }
    }

    return results;
}

+ (NSDictionary<NSString *, NSNumber *> *)parseTomlModelProvidersRequiresOpenAIAuth:(NSString *)content {
    // Parse requires_openai_auth per provider block [model_providers.<name>]
    NSMutableDictionary<NSString *, NSNumber *> *results = [NSMutableDictionary dictionary];
    if (content.length == 0) return results;

    NSString *blockPattern = @"(?ms)^\\[model_providers\\.([A-Za-z0-9_\\-]+)\\]\\s*(.*?)(?=^\\[|\\z)";
    NSRegularExpression *blockRegex = [NSRegularExpression regularExpressionWithPattern:blockPattern options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [blockRegex matchesInString:content options:0 range:NSMakeRange(0, content.length)];

    NSRegularExpression *reqRegex = [NSRegularExpression regularExpressionWithPattern:@"(?m)^\\s*requires_openai_auth\\s*=\\s*(true|false)\\s*$" options:0 error:nil];

    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 3) continue;
        NSRange nameRange = [m rangeAtIndex:1];
        NSRange bodyRange = [m rangeAtIndex:2];
        if (nameRange.location == NSNotFound || bodyRange.location == NSNotFound) continue;

        NSString *provider = [content substringWithRange:nameRange];
        NSString *body = [content substringWithRange:bodyRange];

        NSTextCheckingResult *req = [reqRegex firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        if (!req || req.numberOfRanges < 2) continue;
        NSRange vRange = [req rangeAtIndex:1];
        if (vRange.location == NSNotFound) continue;
        NSString *val = [[body substringWithRange:vRange] lowercaseString];
        results[provider] = @([val isEqualToString:@"true"]);
    }

    return results;
}
#pragma mark - Switch script parsing (.sh)

+ (NSArray<CXLocalConfigImportCandidate *> *)candidatesFromSwitchScript:(NSString *)scriptPath {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:&error];
    if (content.length == 0) return @[];

    // Pattern A: PROFILE_<NAME>_BASEURL / PROFILE_<NAME>_APIKEY (claude_switch style)
    // Example:
    // PROFILE_ANYROUTER_APIKEY="sk-..."
    // PROFILE_ANYROUTER_BASEURL="https://..."
    NSDictionary<NSString *, NSString *> *namedBaseURLs = [self parseScriptKeyValues:content pattern:@"(?m)^\\s*PROFILE_([A-Z0-9_]+)_BASEURL\\s*=\\s*\"([^\"]*)\"\\s*$" keyIndex:1 valueIndex:2];
    NSDictionary<NSString *, NSString *> *namedAPIKeys = [self parseScriptKeyValues:content pattern:@"(?m)^\\s*PROFILE_([A-Z0-9_]+)_(?:APIKEY|API_KEY)\\s*=\\s*\"([^\"]*)\"\\s*$" keyIndex:1 valueIndex:2];

    NSMutableArray<CXLocalConfigImportCandidate *> *results = [NSMutableArray array];
    for (NSString *name in namedBaseURLs) {
        NSString *baseURL = namedBaseURLs[name];
        if (baseURL.length == 0) continue;

        CXLocalConfigImportCandidate *c = [[CXLocalConfigImportCandidate alloc] init];
        c.name = [NSString stringWithFormat:@"导入 %@:%@", scriptPath.lastPathComponent, name.lowercaseString];
        c.baseURL = baseURL;
        c.apiKey = [self normalizedAPIKey:namedAPIKeys[name]];
        c.notes = [NSString stringWithFormat:@"Imported from %@", scriptPath];
        if (c.apiKey.length > 0) {
            [results addObject:c];
        }
    }

    // Pattern B: PROFILE<n>_CONFIG + PROFILE<n>_API_KEY (codex_switch style)
    // Example:
    // PROFILE2_CONFIG="${CONFIG_DIR}/config_anyrouter.toml"
    // PROFILE2_API_KEY="sk-..."
    NSDictionary<NSString *, NSString *> *profileConfigPaths = [self parseScriptKeyValues:content pattern:@"(?m)^\\s*PROFILE([0-9]+)_CONFIG\\s*=\\s*\"([^\"]*)\"\\s*$" keyIndex:1 valueIndex:2];
    NSDictionary<NSString *, NSString *> *profileAPIKeys = [self parseScriptKeyValues:content pattern:@"(?m)^\\s*PROFILE([0-9]+)_API_KEY\\s*=\\s*\"([^\"]*)\"\\s*$" keyIndex:1 valueIndex:2];

    NSString *configDir = scriptPath.stringByDeletingLastPathComponent;
    for (NSString *num in profileConfigPaths) {
        NSString *configPath = profileConfigPaths[num];
        if (configPath.length == 0) continue;

        // Expand ${HOME} and ${CONFIG_DIR} best-effort
        NSString *expanded = [configPath stringByReplacingOccurrencesOfString:@"${HOME}" withString:NSHomeDirectory()];
        expanded = [expanded stringByReplacingOccurrencesOfString:@"${CONFIG_DIR}" withString:configDir];
        expanded = [expanded stringByReplacingOccurrencesOfString:@"$HOME" withString:NSHomeDirectory()];
        expanded = [expanded stringByReplacingOccurrencesOfString:@"$CONFIG_DIR" withString:configDir];
        expanded = [expanded stringByExpandingTildeInPath];

        NSDictionary<NSString *, NSString *> *providers = @{};
        NSString *model = nil;
        NSString *modelProvider = nil;
        NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *headersByProvider = @{};
        NSDictionary<NSString *, NSNumber *> *requiresByProvider = @{};
        NSError *readError = nil;
        NSString *toml = [NSString stringWithContentsOfFile:expanded encoding:NSUTF8StringEncoding error:&readError];
        if (toml.length > 0) {
            providers = [self parseTomlModelProvidersBaseURLs:toml];
            model = [self topLevelTomlStringValueForKey:@"model" inContent:toml];
            modelProvider = [self topLevelTomlStringValueForKey:@"model_provider" inContent:toml];
            headersByProvider = [self parseTomlModelProvidersHTTPHeaders:toml];
            requiresByProvider = [self parseTomlModelProvidersRequiresOpenAIAuth:toml];
        }

        // Pick the first base_url found
        NSString *firstProviderName = providers.allKeys.firstObject;
        NSString *baseURL = firstProviderName ? providers[firstProviderName] : providers.allValues.firstObject;
        if (baseURL.length == 0) continue;

        CXLocalConfigImportCandidate *c = [[CXLocalConfigImportCandidate alloc] init];
        NSString *displayProvider = modelProvider.length > 0 ? modelProvider : (firstProviderName.length > 0 ? firstProviderName : [NSString stringWithFormat:@"profile%@", num]);
        c.name = [NSString stringWithFormat:@"导入 %@:%@", scriptPath.lastPathComponent, displayProvider];
        c.baseURL = baseURL;
        c.model = model;
        c.httpHeaders = firstProviderName ? headersByProvider[firstProviderName] : nil;
        c.requiresOpenAIAuth = firstProviderName ? [requiresByProvider[firstProviderName] boolValue] : NO;
        c.apiKey = [self normalizedAPIKey:profileAPIKeys[num]];
        c.notes = [NSString stringWithFormat:@"Imported from %@ (%@)", scriptPath, expanded];
        if (c.apiKey.length > 0) {
            [results addObject:c];
        }
    }

    return results;
}

+ (NSDictionary<NSString *, NSString *> *)parseScriptKeyValues:(NSString *)content
                                                     pattern:(NSString *)pattern
                                                    keyIndex:(NSInteger)keyIndex
                                                  valueIndex:(NSInteger)valueIndex {
    if (content.length == 0 || pattern.length == 0) return @{};

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:content options:0 range:NSMakeRange(0, content.length)];
    if (matches.count == 0) return @{};

    NSMutableDictionary<NSString *, NSString *> *out = [NSMutableDictionary dictionary];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges <= MAX(keyIndex, valueIndex)) continue;
        NSRange kr = [m rangeAtIndex:keyIndex];
        NSRange vr = [m rangeAtIndex:valueIndex];
        if (kr.location == NSNotFound || vr.location == NSNotFound) continue;
        NSString *k = [content substringWithRange:kr];
        NSString *v = [content substringWithRange:vr];
        if (k.length == 0 || v.length == 0) continue;
        out[k] = v;
    }
    return out;
}

@end
