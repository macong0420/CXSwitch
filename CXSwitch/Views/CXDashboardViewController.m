//
//  CXDashboardViewController.m
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import "CXDashboardViewController.h"
#import "CXProfileManager.h"
#import "CXConfigManager.h"
#import "CXCodexRunner.h"
#import "CXKeychainManager.h"
#import "CXMainWindowController.h"
#import "CXLocalConfigImporter.h"
#import "CXImportPreviewWindowController.h"
#import "CXTerminalLauncher.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface CXDashboardViewController ()

// 统计卡片
@property (nonatomic, strong) NSTextField *totalProfilesLabel;
@property (nonatomic, strong) NSTextField *codexStatusLabel;
@property (nonatomic, strong) NSTextField *configStatusLabel;
@property (nonatomic, strong) NSTextField *officialStatusLabel;

// 当前 Profile 卡片
@property (nonatomic, strong) NSTextField *currentModeLabel;
@property (nonatomic, strong) NSTextField *currentProfileLabel;
@property (nonatomic, strong) NSTextField *currentURLLabel;
@property (nonatomic, strong) NSButton *switchButton;

// 快速操作
@property (nonatomic, strong) NSPopUpButton *profilePopup;
@property (nonatomic, strong) NSButton *applyButton;
@property (nonatomic, strong) NSButton *launchButton;
@property (nonatomic, strong) NSButton *officialButton;
@property (nonatomic, strong) NSButton *importButton;

@end

@implementation CXDashboardViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self refresh];
    
    // 监听通知
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(profileDidChange:) 
                                                 name:CXActiveProfileDidChangeNotification 
                                               object:nil];
}

- (void)setupUI {
    // 主滚动视图
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:scrollView];
    
    // 内容视图
    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    scrollView.documentView = contentView;
    
    // 主容器
    NSStackView *mainStack = [[NSStackView alloc] init];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.alignment = NSLayoutAttributeLeading;
    mainStack.spacing = 24;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:mainStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:24],
        [mainStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24],
        [mainStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24],
    ]];
    
    // 1. 欢迎标题
    NSTextField *welcomeLabel = [NSTextField labelWithString:@"欢迎使用 CXSwitch"];
    welcomeLabel.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    [mainStack addArrangedSubview:welcomeLabel];
    
    // 2. 统计卡片行
    [mainStack addArrangedSubview:[self createStatsRow]];
    
    // 3. 当前状态和快速操作
    NSStackView *contentRow = [[NSStackView alloc] init];
    contentRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    contentRow.spacing = 24;
    contentRow.distribution = NSStackViewDistributionFillEqually;
    
    [contentRow addArrangedSubview:[self createCurrentProfileCard]];
    [contentRow addArrangedSubview:[self createQuickActionsCard]];
    
    [mainStack addArrangedSubview:contentRow];
    
    // 4. 底部快捷链接
    [mainStack addArrangedSubview:[self createBottomLinks]];
}

- (NSView *)createStatsRow {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 16;
    row.distribution = NSStackViewDistributionFillEqually;
    
    // 总 Profile 数
    self.totalProfilesLabel = [NSTextField labelWithString:@"0"];
    [row addArrangedSubview:[self createStatCard:[NSImage imageWithSystemSymbolName:@"person.2.fill" accessibilityDescription:nil] value:self.totalProfilesLabel title:@"总 Profile 数"]];
    
    // Codex 状态
    self.codexStatusLabel = [NSTextField labelWithString:@"检测中..."];
    [row addArrangedSubview:[self createStatCard:[NSImage imageWithSystemSymbolName:@"bolt.fill" accessibilityDescription:nil] value:self.codexStatusLabel title:@"Codex 状态"]];
    
    // 配置状态
    self.configStatusLabel = [NSTextField labelWithString:@"-"];
    [row addArrangedSubview:[self createStatCard:[NSImage imageWithSystemSymbolName:@"doc.text.fill" accessibilityDescription:nil] value:self.configStatusLabel title:@"配置状态"]];
    
    // Official 状态
    self.officialStatusLabel = [NSTextField labelWithString:@"-"];
    [row addArrangedSubview:[self createStatCard:[NSImage imageWithSystemSymbolName:@"building.2.fill" accessibilityDescription:nil] value:self.officialStatusLabel title:@"Official 模式"]];
    
    return row;
}

- (NSView *)createStatCard:(NSImage *)icon value:(NSTextField *)valueLabel title:(NSString *)title {
    NSBox *card = [[NSBox alloc] init];
    card.boxType = NSBoxCustom;
    card.fillColor = [NSColor controlBackgroundColor];
    card.borderColor = [NSColor separatorColor];
    card.borderWidth = 1;
    card.cornerRadius = 8;
    card.contentViewMargins = NSMakeSize(12, 12);
    card.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 图标
    NSImageView *iconView = [NSImageView imageViewWithImage:icon];
    iconView.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightRegular];
    iconView.contentTintColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:iconView];
    
    // 值
    valueLabel.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
    valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [stack addArrangedSubview:valueLabel];
    
    // 标题
    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:11];
    titleLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:titleLabel];
    
    [card.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.contentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor],
        [card.heightAnchor constraintEqualToConstant:90]
    ]];
    
    return card;
}

- (NSView *)createCurrentProfileCard {
    NSBox *card = [[NSBox alloc] init];
    card.title = @"当前 Profile";
    card.titleFont = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    card.boxType = NSBoxPrimary;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.currentModeLabel = [NSTextField labelWithString:@"模式：-"];
    self.currentModeLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    [stack addArrangedSubview:self.currentModeLabel];
    
    self.currentProfileLabel = [NSTextField labelWithString:@"Profile：-"];
    self.currentProfileLabel.font = [NSFont systemFontOfSize:12];
    self.currentProfileLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:self.currentProfileLabel];
    
    self.currentURLLabel = [NSTextField labelWithString:@"URL：-"];
    self.currentURLLabel.font = [NSFont systemFontOfSize:11];
    self.currentURLLabel.textColor = [NSColor tertiaryLabelColor];
    self.currentURLLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [stack addArrangedSubview:self.currentURLLabel];
    
    self.switchButton = [NSButton buttonWithTitle:@"切换 Profile" target:self action:@selector(switchProfile:)];
    self.switchButton.bezelStyle = NSBezelStyleRounded;
    self.switchButton.controlSize = NSControlSizeSmall;
    [stack addArrangedSubview:self.switchButton];
    
    [card.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor constant:-12],
        [card.heightAnchor constraintEqualToConstant:150]
    ]];
    
    return card;
}

- (NSView *)createQuickActionsCard {
    NSBox *card = [[NSBox alloc] init];
    card.title = @"快速操作";
    card.titleFont = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    card.boxType = NSBoxPrimary;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Profile 选择
    NSStackView *profileRow = [[NSStackView alloc] init];
    profileRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    profileRow.spacing = 8;
    
    self.profilePopup = [[NSPopUpButton alloc] init];
    self.profilePopup.translatesAutoresizingMaskIntoConstraints = NO;
    self.profilePopup.controlSize = NSControlSizeSmall;
    [self.profilePopup.widthAnchor constraintEqualToConstant:180].active = YES;
    [profileRow addArrangedSubview:self.profilePopup];
    
    self.applyButton = [NSButton buttonWithTitle:@"应用" target:self action:@selector(applySelectedProfile:)];
    self.applyButton.bezelStyle = NSBezelStyleRounded;
    self.applyButton.controlSize = NSControlSizeSmall;
    [profileRow addArrangedSubview:self.applyButton];
    
    [stack addArrangedSubview:profileRow];

    // 启动 codex（会在启动前确保选中的 Profile 已应用）
    self.launchButton = [NSButton buttonWithTitle:@"打开 Terminal 并启动 Codex" target:self action:@selector(openTerminalAndLaunchCodex:)];
    self.launchButton.bezelStyle = NSBezelStyleRounded;
    self.launchButton.controlSize = NSControlSizeSmall;
    [stack addArrangedSubview:self.launchButton];
    
    // Official 按钮
    self.officialButton = [NSButton buttonWithTitle:@"切换到 Official 登录" target:self action:@selector(switchToOfficial:)];
    self.officialButton.bezelStyle = NSBezelStyleRounded;
    self.officialButton.controlSize = NSControlSizeSmall;
    [stack addArrangedSubview:self.officialButton];
    
    // 刷新按钮
    NSButton *refreshButton = [NSButton buttonWithTitle:@"刷新状态" target:self action:@selector(refresh)];
    refreshButton.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:nil];
    refreshButton.imagePosition = NSImageLeading;
    refreshButton.bezelStyle = NSBezelStyleRounded;
    refreshButton.controlSize = NSControlSizeSmall;
    [stack addArrangedSubview:refreshButton];
    
    [card.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor constant:-12],
        [card.heightAnchor constraintEqualToConstant:150]
    ]];
    
    return card;
}

- (NSView *)createBottomLinks {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 24;
    
    NSButton *viewAllButton = [NSButton buttonWithTitle:@"查看所有账号" target:self action:@selector(viewAllProfiles:)];
    viewAllButton.bezelStyle = NSBezelStyleInline;
    viewAllButton.image = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:nil];
    viewAllButton.imagePosition = NSImageTrailing;
 
    [row addArrangedSubview:viewAllButton];

    self.importButton = [NSButton buttonWithTitle:@"从本地导入" target:self action:@selector(importFromLocal:)];
    self.importButton.bezelStyle = NSBezelStyleInline;
    self.importButton.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.down" accessibilityDescription:nil];
    self.importButton.imagePosition = NSImageTrailing;
    [row addArrangedSubview:self.importButton];
    
    NSButton *exportButton = [NSButton buttonWithTitle:@"导出账号数据" target:self action:@selector(exportProfiles:)];
    exportButton.bezelStyle = NSBezelStyleInline;
    exportButton.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.down" accessibilityDescription:nil];
    exportButton.imagePosition = NSImageTrailing;
    [row addArrangedSubview:exportButton];
    
    return row;
}

#pragma mark - Refresh

- (void)refresh {
    CXProfileManager *manager = [CXProfileManager sharedManager];
    
    // 更新统计
    self.totalProfilesLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)manager.profileCount];
    
    // Codex 状态
    CXCodexRunner *runner = [CXCodexRunner sharedRunner];
    if (runner.isCodexAvailable) {
        self.codexStatusLabel.stringValue = @"可用";
        self.codexStatusLabel.textColor = [NSColor systemGreenColor];
    } else {
        self.codexStatusLabel.stringValue = @"不可用";
        self.codexStatusLabel.textColor = [NSColor systemRedColor];
    }
    
    // 配置状态
    NSDictionary *configStatus = [[CXConfigManager sharedManager] currentConfigStatus];
    if ([configStatus[@"authJsonExists"] boolValue]) {
        if (configStatus[@"authJsonValid"] != nil && ![configStatus[@"authJsonValid"] boolValue]) {
            self.configStatusLabel.stringValue = @"已配置(疑似无效)";
            self.configStatusLabel.textColor = [NSColor systemRedColor];
        } else {
            self.configStatusLabel.stringValue = @"已配置";
            self.configStatusLabel.textColor = [NSColor systemGreenColor];
        }
    } else {
        self.configStatusLabel.stringValue = @"未配置";
        self.configStatusLabel.textColor = [NSColor systemOrangeColor];
    }
    
    // Official 状态
    if (manager.isOfficialMode) {
        self.officialStatusLabel.stringValue = @"已启用";
        self.officialStatusLabel.textColor = [NSColor systemGreenColor];
    } else {
        self.officialStatusLabel.stringValue = @"未启用";
        self.officialStatusLabel.textColor = [NSColor secondaryLabelColor];
    }
    
    // 当前 Profile
    if (manager.isOfficialMode) {
        self.currentModeLabel.stringValue = @"模式：Official 登录";
        self.currentProfileLabel.stringValue = @"使用官方 ChatGPT 登录";
        self.currentURLLabel.stringValue = @"api.openai.com";
    } else if (manager.activeProfile) {
        CXProfile *profile = manager.activeProfile;
        self.currentModeLabel.stringValue = @"模式：API Key";
        self.currentProfileLabel.stringValue = [NSString stringWithFormat:@"Profile：%@", profile.name];
        self.currentURLLabel.stringValue = [NSString stringWithFormat:@"URL：%@", profile.baseURL];
    } else {
        self.currentModeLabel.stringValue = @"模式：未配置";
        self.currentProfileLabel.stringValue = @"请选择一个 Profile 或使用 Official 登录";
        self.currentURLLabel.stringValue = @"";
    }
    
    // 更新 Profile 下拉框
    [self.profilePopup removeAllItems];
    for (CXProfile *profile in manager.allProfiles) {
        [self.profilePopup addItemWithTitle:profile.name];
        self.profilePopup.lastItem.representedObject = profile;
    }
    
    if (manager.activeProfile) {
        [self.profilePopup selectItemWithTitle:manager.activeProfile.name];
    }
}

#pragma mark - Actions

- (void)switchProfile:(id)sender {
    // 跳转到账号管理 Tab
    NSWindowController *wc = self.view.window.windowController;
    if ([wc isKindOfClass:[CXMainWindowController class]]) {
        [(CXMainWindowController *)wc selectTabAtIndex:1];
    }
}

- (void)applySelectedProfile:(id)sender {
    CXProfile *profile = self.profilePopup.selectedItem.representedObject;
    if (!profile) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"请先选择一个 Profile";
        [alert runModal];
        return;
    }
    
    NSString *apiKey = [[CXKeychainManager sharedManager] getAPIKeyForProfileId:profile.profileId error:nil];
    if (!apiKey) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"API Key 不存在";
        alert.informativeText = @"此 Profile 没有关联的 API Key";
        [alert runModal];
        return;
    }
    
    NSError *error = nil;
    BOOL success = [[CXConfigManager sharedManager] applyProfile:profile apiKey:apiKey error:&error];
    
    if (success) {
        [[CXProfileManager sharedManager] activateProfile:profile error:nil];
        [self refresh];
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"✅ 已切换";
        alert.informativeText = [NSString stringWithFormat:@"已切换到 %@", profile.name];
        [alert runModal];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"切换失败";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
    }
}

- (void)switchToOfficial:(id)sender {
    NSError *error = nil;
    BOOL success = [[CXConfigManager sharedManager] applyOfficialModeWithError:&error];
    
    if (success) {
        [[CXProfileManager sharedManager] switchToOfficialModeWithError:nil];
        [self refresh];
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"✅ 已切换到 Official 模式";
        alert.informativeText = @"现在可以使用 codex login 进行官方登录";
        [alert runModal];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"切换失败";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
    }
}

- (void)openTerminalAndLaunchCodex:(id)sender {
    (void)sender;

    // 1) Ensure config is applied for the selected profile (if any)
    CXProfile *selected = self.profilePopup.selectedItem.representedObject;
    CXProfileManager *profileManager = [CXProfileManager sharedManager];
    CXConfigManager *configManager = [CXConfigManager sharedManager];

    NSError *applyError = nil;
    if (selected) {
        NSString *apiKey = [[CXKeychainManager sharedManager] getAPIKeyForProfileId:selected.profileId error:nil];
        if (apiKey.length == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"API Key 不存在";
            alert.informativeText = @"此 Profile 没有关联的 API Key，请到“账号管理”页补充。";
            [alert runModal];
            return;
        }

        BOOL success = [configManager applyProfile:selected apiKey:apiKey error:&applyError];
        if (!success) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"切换失败";
            alert.informativeText = applyError.localizedDescription ?: @"未知错误";
            [alert runModal];
            return;
        }
        [profileManager activateProfile:selected error:nil];
        [self refresh];
    } else if (profileManager.isOfficialMode) {
        BOOL success = [configManager applyOfficialModeWithError:&applyError];
        if (!success) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"切换失败";
            alert.informativeText = applyError.localizedDescription ?: @"未知错误";
            [alert runModal];
            return;
        }
        [profileManager switchToOfficialModeWithError:nil];
        [self refresh];
    }

    // 2) Launch Terminal and run codex
    CXCodexRunner *runner = [CXCodexRunner sharedRunner];
    NSString *codexCmd = runner.codexPath.length > 0 ? [CXTerminalLauncher shellQuotedString:runner.codexPath] : @"codex";

    NSString *profileName = profileManager.isOfficialMode ? @"official" : (profileManager.activeProfile.name ?: @"profile");
    NSString *banner = [NSString stringWithFormat:@"printf '\\nCXSwitch: %%s\\n\\n' %@; ",
                        [CXTerminalLauncher shellQuotedString:profileName]];

    NSString *baseURL = profileManager.activeProfile ? [CXProfile normalizeBaseURL:profileManager.activeProfile.baseURL] : @"";
    NSString *envPrefix = nil;
    if (profileManager.isOfficialMode) {
        envPrefix = @"unset OPENAI_BASE_URL; unset OPENAI_API_KEY; ";
    } else if (baseURL.length > 0) {
        envPrefix = [NSString stringWithFormat:@"unset OPENAI_API_KEY; export OPENAI_BASE_URL=%@; ",
                     [CXTerminalLauncher shellQuotedString:baseURL]];
    } else {
        envPrefix = @"unset OPENAI_API_KEY; ";
    }

    NSString *command = [NSString stringWithFormat:@"cd \"$HOME\"; %@%@%@", envPrefix, banner, codexCmd];

    NSError *error = nil;
    if (![CXTerminalLauncher openTerminalAndRunCommand:command error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法打开 Terminal";
        alert.informativeText = error.localizedDescription ?: @"未知错误";
        [alert runModal];
    }
}

- (void)viewAllProfiles:(id)sender {
    NSWindowController *wc = self.view.window.windowController;
    if ([wc isKindOfClass:[CXMainWindowController class]]) {
        [(CXMainWindowController *)wc selectTabAtIndex:1];
    }
}

- (void)exportProfiles:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"json"]];
    panel.nameFieldStringValue = @"profiles_export.json";
    
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSData *data = [[CXProfileManager sharedManager] exportProfilesIncludeKeys:NO];
            if (data) {
                [data writeToURL:panel.URL atomically:YES];
            }
        }
    }];
}

- (void)importFromLocal:(id)sender {
    // 复用账号管理页的导入逻辑：用户选择 .env 或目录，然后跳转到账号管理页查看结果
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.message = @"选择 .env 文件、~/.codex 目录，或 codex_switch.sh（仅支持 Codex）";
    panel.prompt = @"导入";
    panel.directoryURL = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@".codex"]];

    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;

        NSMutableArray<CXLocalConfigImportCandidate *> *allCandidates = [NSMutableArray array];
        for (NSURL *url in panel.URLs) {
            NSArray<CXLocalConfigImportCandidate *> *candidates = [CXLocalConfigImporter candidatesFromPath:url.path];
            if (candidates.count > 0) {
                [allCandidates addObjectsFromArray:candidates];
            }
        }

        if (allCandidates.count == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"未发现可导入的配置";
            alert.informativeText = @"请确认选择的是 .env 文件、~/.codex 目录（含 config_*.toml），或 codex_switch.sh。";
            [alert runModal];
            return;
        }

        [CXImportPreviewWindowController beginSheetForWindow:self.view.window
                                                 candidates:allCandidates
                                            existingProfiles:[CXProfileManager sharedManager].allProfiles
                                                 completion:^(NSArray<CXLocalConfigImportCandidate *> *selectedCandidates) {
            if (selectedCandidates.count == 0) return;

            NSInteger imported = 0;
            NSInteger skipped = 0;

            for (CXLocalConfigImportCandidate *c in selectedCandidates) {
                if (c.baseURL.length == 0) {
                    skipped += 1;
                    continue;
                }

                NSString *apiKey = c.apiKey;
                NSString *model = c.model;
                if (apiKey.length == 0) {
                    apiKey = [self promptForAPIKeyWithName:c.name baseURL:c.baseURL];
                }
                if (apiKey.length == 0) {
                    skipped += 1;
                    continue;
                }

                NSError *error = nil;
                CXProfile *profile = [[CXProfileManager sharedManager] addProfileWithName:c.name
                                                                                  baseURL:c.baseURL
                                                                                    model:model
                                                                                   apiKey:apiKey
                                                                                    error:&error];
                if (!profile) {
                    skipped += 1;
                    continue;
                }
                if (c.httpHeaders.count > 0 || c.requiresOpenAIAuth) {
                    profile.httpHeaders = c.httpHeaders;
                    profile.requiresOpenAIAuth = c.requiresOpenAIAuth;
                    [[CXProfileManager sharedManager] updateProfile:profile apiKey:nil error:nil];
                }
                if (c.notes.length > 0) {
                    profile.notes = c.notes;
                    [[CXProfileManager sharedManager] updateProfile:profile apiKey:nil error:nil];
                }
                imported += 1;
            }

            [self refresh];

            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"导入完成";
            alert.informativeText = [NSString stringWithFormat:@"成功导入 %ld 个，跳过 %ld 个。", (long)imported, (long)skipped];
            [alert runModal];
        }];
    }];
}

- (nullable NSString *)promptForAPIKeyWithName:(NSString *)name baseURL:(NSString *)baseURL {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"需要 API Key";
    alert.informativeText = [NSString stringWithFormat:@"为“%@”输入 API Key（Base URL: %@）", name ?: @"导入项", baseURL ?: @""];

    NSSecureTextField *keyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    keyField.placeholderString = @"OPENAI_API_KEY";
    alert.accessoryView = keyField;

    [alert addButtonWithTitle:@"导入"];
    [alert addButtonWithTitle:@"跳过"];

    NSModalResponse r = [alert runModal];
    if (r != NSAlertFirstButtonReturn) return nil;
    
    NSString *normalized = [CXKeychainManager normalizedAPIKeyFromUserInput:keyField.stringValue];
    if (normalized.length == 0) {
        NSAlert *bad = [[NSAlert alloc] init];
        bad.messageText = @"API Key 无效";
        bad.informativeText = @"请确认只粘贴 key 本身（不要包含空格/换行/论坛引用等多余内容）。";
        [bad runModal];
        return nil;
    }
    return normalized;
}

#pragma mark - Notifications

- (void)profileDidChange:(NSNotification *)notification {
    [self refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
