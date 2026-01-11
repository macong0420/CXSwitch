//
//  CXProfile.m
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import "CXProfile.h"

@implementation CXProfile

#pragma mark - Class Methods

+ (instancetype)profileWithName:(NSString *)name baseURL:(NSString *)baseURL {
    return [self profileWithName:name baseURL:baseURL model:nil];
}

+ (instancetype)profileWithName:(NSString *)name baseURL:(NSString *)baseURL model:(nullable NSString *)model {
    CXProfile *profile = [[CXProfile alloc] init];
    profile.profileId = [[NSUUID UUID] UUIDString];
    profile.name = name;
    profile.baseURL = [self normalizeBaseURL:baseURL];
    profile.model = model.length > 0 ? model : nil;
    profile.httpHeaders = nil;
    profile.requiresOpenAIAuth = NO;
    profile.createdAt = [NSDate date];
    profile.updatedAt = [NSDate date];
    profile.active = NO;
    return profile;
}

+ (NSString *)normalizeBaseURL:(NSString *)url {
    if (!url || url.length == 0) return @"";
    
    NSString *normalized = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // 移除末尾斜杠
    while ([normalized hasSuffix:@"/"]) {
        normalized = [normalized substringToIndex:normalized.length - 1];
    }
    
    // 确保有协议前缀
    if (![normalized hasPrefix:@"http://"] && ![normalized hasPrefix:@"https://"]) {
        normalized = [@"https://" stringByAppendingString:normalized];
    }

    // 对 Codex/OpenAI 兼容服务：如果用户只填了 host（无 path），默认补上 /v1
    // 例如 https://wzw.pp.ua -> https://wzw.pp.ua/v1
    NSURLComponents *components = [NSURLComponents componentsWithString:normalized];
    NSString *path = components.path ?: @"";
    if (components.host.length > 0 && (path.length == 0 || [path isEqualToString:@"/"])) {
        components.path = @"/v1";
        NSString *rebuilt = components.string;
        if (rebuilt.length > 0) {
            normalized = rebuilt;
        }
    }
    
    return normalized;
}

+ (BOOL)isValidBaseURL:(NSString *)url {
    if (!url || url.length == 0) return NO;
    
    NSString *normalized = [self normalizeBaseURL:url];
    NSURL *nsurl = [NSURL URLWithString:normalized];
    
    return nsurl != nil && nsurl.scheme != nil && nsurl.host != nil;
}

#pragma mark - Initializers

- (instancetype)init {
    self = [super init];
    if (self) {
        _profileId = [[NSUUID UUID] UUIDString];
        _createdAt = [NSDate date];
        _updatedAt = [NSDate date];
        _active = NO;
        _requiresOpenAIAuth = NO;
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _profileId = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
        _name = dict[@"name"] ?: @"";
        _baseURL = [[self class] normalizeBaseURL:(dict[@"baseURL"] ?: @"")];
        id model = dict[@"model"];
        if ([model isKindOfClass:[NSString class]] && ((NSString *)model).length > 0) {
            _model = model;
        }
        id headers = dict[@"httpHeaders"];
        if ([headers isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary<NSString *, NSString *> *filtered = [NSMutableDictionary dictionary];
            for (id k in (NSDictionary *)headers) {
                id v = [(NSDictionary *)headers objectForKey:k];
                if (![k isKindOfClass:[NSString class]] || ![v isKindOfClass:[NSString class]]) continue;
                if (((NSString *)k).length == 0) continue;
                filtered[(NSString *)k] = (NSString *)v;
            }
            _httpHeaders = filtered.count > 0 ? [filtered copy] : nil;
        }
        id requires = dict[@"requiresOpenAIAuth"];
        if ([requires respondsToSelector:@selector(boolValue)]) {
            _requiresOpenAIAuth = [requires boolValue];
        }
        
        // 解析日期
        _createdAt = [self dateFromValue:dict[@"createdAt"]] ?: [NSDate date];
        _updatedAt = [self dateFromValue:dict[@"updatedAt"]] ?: [NSDate date];
        _lastUsedAt = [self dateFromValue:dict[@"lastUsedAt"]];
        
        _active = [dict[@"active"] boolValue];
        _notes = dict[@"notes"];
    }
    return self;
}

- (NSDate *)dateFromValue:(id)value {
    if (!value || [value isKindOfClass:[NSNull class]]) return nil;
    
    if ([value isKindOfClass:[NSDate class]]) {
        return value;
    }
    
    if ([value isKindOfClass:[NSNumber class]]) {
        return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
    }
    
    if ([value isKindOfClass:[NSString class]]) {
        // ISO 8601 格式
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
        NSDate *date = [formatter dateFromString:value];
        if (date) return date;
        
        // 尝试时间戳
        double timestamp = [value doubleValue];
        if (timestamp > 0) {
            return [NSDate dateWithTimeIntervalSince1970:timestamp];
        }
    }
    
    return nil;
}

#pragma mark - Serialization

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"id"] = self.profileId;
    dict[@"name"] = self.name ?: @"";
    dict[@"baseURL"] = self.baseURL ?: @"";
    if (self.model.length > 0) {
        dict[@"model"] = self.model;
    }
    if (self.httpHeaders.count > 0) {
        dict[@"httpHeaders"] = self.httpHeaders;
    }
    dict[@"requiresOpenAIAuth"] = @(self.requiresOpenAIAuth);
    dict[@"createdAt"] = @([self.createdAt timeIntervalSince1970]);
    dict[@"updatedAt"] = @([self.updatedAt timeIntervalSince1970]);
    dict[@"active"] = @(self.active);
    
    if (self.lastUsedAt) {
        dict[@"lastUsedAt"] = @([self.lastUsedAt timeIntervalSince1970]);
    }
    
    if (self.notes) {
        dict[@"notes"] = self.notes;
    }
    
    return [dict copy];
}

#pragma mark - Helpers

- (NSString *)sanitizedBaseURL {
    // 只显示 host 部分
    NSURL *url = [NSURL URLWithString:self.baseURL];
    if (url && url.host) {
        return [NSString stringWithFormat:@"%@://%@/...", url.scheme, url.host];
    }
    return @"[invalid URL]";
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.profileId forKey:@"profileId"];
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.baseURL forKey:@"baseURL"];
    [coder encodeObject:self.model forKey:@"model"];
    [coder encodeObject:self.httpHeaders forKey:@"httpHeaders"];
    [coder encodeBool:self.requiresOpenAIAuth forKey:@"requiresOpenAIAuth"];
    [coder encodeObject:self.createdAt forKey:@"createdAt"];
    [coder encodeObject:self.updatedAt forKey:@"updatedAt"];
    [coder encodeObject:self.lastUsedAt forKey:@"lastUsedAt"];
    [coder encodeBool:self.active forKey:@"active"];
    [coder encodeObject:self.notes forKey:@"notes"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _profileId = [coder decodeObjectOfClass:[NSString class] forKey:@"profileId"];
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _baseURL = [coder decodeObjectOfClass:[NSString class] forKey:@"baseURL"];
        _model = [coder decodeObjectOfClass:[NSString class] forKey:@"model"];
        _httpHeaders = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"httpHeaders"];
        _requiresOpenAIAuth = [coder decodeBoolForKey:@"requiresOpenAIAuth"];
        _createdAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"createdAt"];
        _updatedAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"updatedAt"];
        _lastUsedAt = [coder decodeObjectOfClass:[NSDate class] forKey:@"lastUsedAt"];
        _active = [coder decodeBoolForKey:@"active"];
        _notes = [coder decodeObjectOfClass:[NSString class] forKey:@"notes"];
    }
    return self;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    CXProfile *copy = [[CXProfile allocWithZone:zone] init];
    copy.profileId = [self.profileId copy];
    copy.name = [self.name copy];
    copy.baseURL = [self.baseURL copy];
    copy.model = [self.model copy];
    copy.httpHeaders = [self.httpHeaders copy];
    copy.requiresOpenAIAuth = self.requiresOpenAIAuth;
    copy.createdAt = [self.createdAt copy];
    copy.updatedAt = [self.updatedAt copy];
    copy.lastUsedAt = [self.lastUsedAt copy];
    copy.active = self.active;
    copy.notes = [self.notes copy];
    return copy;
}

#pragma mark - Description

- (NSString *)description {
    return [NSString stringWithFormat:@"<CXProfile: %@ (%@) - %@>", 
            self.name, self.profileId, [self sanitizedBaseURL]];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CXProfile class]]) return NO;
    
    CXProfile *other = (CXProfile *)object;
    return [self.profileId isEqualToString:other.profileId];
}

- (NSUInteger)hash {
    return [self.profileId hash];
}

@end
