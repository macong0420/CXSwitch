//
//  CXPopoverViewController.m
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import "CXPopoverViewController.h"
#import "CXStatusItemController.h"
#import "CXProfileManager.h"
#import "CXConfigManager.h"
#import "CXCodexRunner.h"
#import "CXKeychainManager.h"
#import "CXTerminalLauncher.h"

@interface CXPopoverViewController () <NSTableViewDataSource, NSTableViewDelegate>

// 状态卡片
@property (nonatomic, strong) NSView *statusCard;
@property (nonatomic, strong) NSTextField *modeLabel;
@property (nonatomic, strong) NSTextField *profileLabel;
@property (nonatomic, strong) NSTextField *urlLabel;

// Profile 列表
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTableView *tableView;

// 底部按钮
@property (nonatomic, strong) NSButton *checkButton;
@property (nonatomic, strong) NSButton *mainWindowButton;
@property (nonatomic, strong) NSButton *quitButton;

@end

@implementation CXPopoverViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
    [self setupUI];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refresh];
}

- (void)setupUI {
    // 主容器
    NSStackView *mainStack = [[NSStackView alloc] init];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.spacing = 12;
    mainStack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mainStack];
    
    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [mainStack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    // 1. 状态卡片
    [mainStack addArrangedSubview:[self createStatusCard]];
    
    // 2. 分隔线
    [mainStack addArrangedSubview:[self createSeparator]];
    
    // 3. 快速切换标题
    NSTextField *switchTitle = [NSTextField labelWithString:@"快速切换"];
    switchTitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    switchTitle.textColor = [NSColor secondaryLabelColor];
    [mainStack addArrangedSubview:switchTitle];
    
    // 4. Profile 列表
    [mainStack addArrangedSubview:[self createProfileList]];
    
    // 5. Official 选项
    [mainStack addArrangedSubview:[self createOfficialOption]];
    
    // 6. 分隔线
    [mainStack addArrangedSubview:[self createSeparator]];
    
    // 7. 底部按钮
    [mainStack addArrangedSubview:[self createBottomButtons]];
}

- (NSView *)createStatusCard {
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
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 模式标签
    self.modeLabel = [NSTextField labelWithString:@"当前模式：-"];
    self.modeLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    [stack addArrangedSubview:self.modeLabel];
    
    // Profile 名称
    self.profileLabel = [NSTextField labelWithString:@"Profile：-"];
    self.profileLabel.font = [NSFont systemFontOfSize:12];
    self.profileLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:self.profileLabel];
    
    // URL
    self.urlLabel = [NSTextField labelWithString:@"URL：-"];
    self.urlLabel.font = [NSFont systemFontOfSize:11];
    self.urlLabel.textColor = [NSColor tertiaryLabelColor];
    self.urlLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [stack addArrangedSubview:self.urlLabel];
    
    [card.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.contentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor]
    ]];
    
    self.statusCard = card;
    
    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:80]
    ]];
    
    return card;
}

- (NSView *)createSeparator {
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    return separator;
}

- (NSView *)createProfileList {
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.tableView = [[NSTableView alloc] init];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.headerView = nil;
    self.tableView.rowHeight = 36;
    self.tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    self.tableView.backgroundColor = [NSColor clearColor];
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"ProfileColumn"];
    column.width = 260;
    [self.tableView addTableColumn:column];
    
    self.scrollView.documentView = self.tableView;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.heightAnchor constraintEqualToConstant:120]
    ]];
    
    return self.scrollView;
}

- (NSView *)createOfficialOption {
    NSButton *officialButton = [NSButton buttonWithTitle:@"Official 登录" 
                                                  target:self 
                                                  action:@selector(switchToOfficial:)];
    officialButton.bezelStyle = NSBezelStyleRecessed;
    officialButton.controlSize = NSControlSizeRegular;
    
    return officialButton;
}

- (NSView *)createBottomButtons {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.spacing = 8;
    stack.distribution = NSStackViewDistributionFillEqually;
    
    self.checkButton = [NSButton buttonWithTitle:@"启动 Codex"
                                          target:self
                                          action:@selector(launchCodexInTerminal:)];
    self.checkButton.bezelStyle = NSBezelStyleRounded;
    self.checkButton.controlSize = NSControlSizeSmall;
    
    self.mainWindowButton = [NSButton buttonWithTitle:@"主窗口" 
                                               target:self 
                                               action:@selector(openMainWindow:)];
    self.mainWindowButton.bezelStyle = NSBezelStyleRounded;
    self.mainWindowButton.controlSize = NSControlSizeSmall;
    
    self.quitButton = [NSButton buttonWithTitle:@"退出" 
                                         target:self 
                                         action:@selector(quit:)];
    self.quitButton.bezelStyle = NSBezelStyleRounded;
    self.quitButton.controlSize = NSControlSizeSmall;
    
    [stack addArrangedSubview:self.checkButton];
    [stack addArrangedSubview:self.mainWindowButton];
    [stack addArrangedSubview:self.quitButton];
    
    return stack;
}

#pragma mark - Refresh

- (void)refresh {
    CXProfileManager *manager = [CXProfileManager sharedManager];
    
    if (manager.isOfficialMode) {
        self.modeLabel.stringValue = @"当前模式：Official";
        self.modeLabel.textColor = [NSColor systemGreenColor];
        self.profileLabel.stringValue = @"使用官方登录";
        self.urlLabel.stringValue = @"api.openai.com";
    } else if (manager.activeProfile) {
        CXProfile *profile = manager.activeProfile;
        self.modeLabel.stringValue = @"当前模式：API Key";
        self.modeLabel.textColor = [NSColor labelColor];
        self.profileLabel.stringValue = [NSString stringWithFormat:@"Profile：%@", profile.name];
        self.urlLabel.stringValue = [NSString stringWithFormat:@"URL：%@", profile.baseURL];
    } else {
        self.modeLabel.stringValue = @"当前模式：未配置";
        self.modeLabel.textColor = [NSColor secondaryLabelColor];
        self.profileLabel.stringValue = @"请添加 Profile 或使用 Official 登录";
        self.urlLabel.stringValue = @"";
    }
    
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)switchToOfficial:(id)sender {
    NSError *error = nil;
    BOOL success = [[CXConfigManager sharedManager] applyOfficialModeWithError:&error];
    
    if (success) {
        [[CXProfileManager sharedManager] switchToOfficialModeWithError:nil];
        [self refresh];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"切换失败";
        alert.informativeText = error.localizedDescription ?: @"未知错误";
        [alert runModal];
    }
}

- (void)checkStatus:(id)sender {
    CXCodexRunner *runner = [CXCodexRunner sharedRunner];
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Codex 状态";
    
    NSMutableString *info = [NSMutableString string];
    
    if (runner.isCodexAvailable) {
        [info appendFormat:@"Codex 路径: %@\n", runner.codexPath];
        if (runner.detectedVersion) {
            [info appendFormat:@"版本: %@\n", runner.detectedVersion];
        }
    } else {
        [info appendString:@"未找到可用的 Codex\n"];
    }
    
    NSDictionary *configStatus = [[CXConfigManager sharedManager] currentConfigStatus];
    [info appendFormat:@"\n配置状态:\n"];
    if ([configStatus[@"authJsonExists"] boolValue]) {
        if (configStatus[@"authJsonValid"] != nil && ![configStatus[@"authJsonValid"] boolValue]) {
            [info appendString:@"auth.json: 已配置（疑似无效：包含空格/换行等）\n"];
        } else {
            [info appendString:@"auth.json: 已配置\n"];
        }
    } else {
        [info appendString:@"auth.json: 未配置\n"];
    }
    [info appendFormat:@"config.toml: %@\n", [configStatus[@"configTomlExists"] boolValue] ? @"已配置" : @"未配置"];
    
    if (configStatus[@"baseURL"]) {
        [info appendFormat:@"Base URL: %@\n", configStatus[@"baseURL"]];
    }
    
    alert.informativeText = info;
    [alert runModal];
}

- (void)launchCodexInTerminal:(id)sender {
    (void)sender;

    CXCodexRunner *runner = [CXCodexRunner sharedRunner];
    NSString *codexCmd = runner.codexPath.length > 0 ? [CXTerminalLauncher shellQuotedString:runner.codexPath] : @"codex";

    // Ensure the on-disk Codex config is in sync with the current active profile.
    CXProfileManager *manager = [CXProfileManager sharedManager];
    CXConfigManager *configManager = [CXConfigManager sharedManager];
    NSError *applyError = nil;

    if (manager.isOfficialMode) {
        (void)[configManager applyOfficialModeWithError:&applyError];
    } else if (manager.activeProfile) {
        CXProfile *profile = manager.activeProfile;
        NSString *apiKey = [[CXKeychainManager sharedManager] getAPIKeyForProfileId:profile.profileId error:nil];
        if (apiKey.length > 0) {
            (void)[configManager applyProfile:profile apiKey:apiKey error:&applyError];
        }
    }

    NSString *profileName = manager.isOfficialMode ? @"official" : (manager.activeProfile.name ?: @"profile");
    NSString *banner = [NSString stringWithFormat:@"printf '\\nCXSwitch: %%s\\n\\n' %@; ",
                        [CXTerminalLauncher shellQuotedString:profileName]];

    NSString *baseURL = manager.activeProfile ? [CXProfile normalizeBaseURL:manager.activeProfile.baseURL] : @"";
    NSString *envPrefix = nil;
    if (manager.isOfficialMode) {
        envPrefix = @"unset OPENAI_BASE_URL; unset OPENAI_API_KEY; ";
    } else if (baseURL.length > 0) {
        envPrefix = [NSString stringWithFormat:@"unset OPENAI_API_KEY; export OPENAI_BASE_URL=%@; ",
                     [CXTerminalLauncher shellQuotedString:baseURL]];
    } else {
        envPrefix = @"unset OPENAI_API_KEY; ";
    }

    NSString *command = [NSString stringWithFormat:@"cd \"$HOME\"; %@%@%@",
                         envPrefix,
                         banner,
                         codexCmd];

    NSError *error = nil;
    if (![CXTerminalLauncher openTerminalAndRunCommand:command error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法打开 Terminal";
        alert.informativeText = error.localizedDescription ?: @"未知错误";
        [alert runModal];
    }
}

- (void)openMainWindow:(id)sender {
    [self.statusItemController openMainWindow];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [CXProfileManager sharedManager].allProfiles.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSArray<CXProfile *> *profiles = [CXProfileManager sharedManager].allProfiles;
    if (row >= profiles.count) return nil;
    
    CXProfile *profile = profiles[row];
    
    NSTableCellView *cellView = [tableView makeViewWithIdentifier:@"ProfileCell" owner:self];
    if (!cellView) {
        cellView = [[NSTableCellView alloc] init];
        cellView.identifier = @"ProfileCell";
        cellView.wantsLayer = YES;
        cellView.layer.cornerRadius = 6;
        
        NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(profileRowClicked:)];
        button.bezelStyle = NSBezelStyleRecessed;
        button.alignment = NSTextAlignmentLeft;
        button.imagePosition = NSImageLeft;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [cellView addSubview:button];
        
        [NSLayoutConstraint activateConstraints:@[
            [button.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor constant:4],
            [button.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor constant:-4],
            [button.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor],
            [button.heightAnchor constraintEqualToConstant:28]
        ]];
        
        cellView.textField = nil; // 使用按钮代替
    }
    
    NSButton *button = cellView.subviews.firstObject;
    if ([button isKindOfClass:[NSButton class]]) {
        NSString *title = profile.name;
        if (profile.isActive) {
            // 激活状态：醒目的绿色背景 + 白色勾选图标
            cellView.layer.backgroundColor = [[NSColor systemGreenColor] colorWithAlphaComponent:0.15].CGColor;
            cellView.layer.borderColor = [NSColor systemGreenColor].CGColor;
            cellView.layer.borderWidth = 1.5;
            
            button.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:nil];
            button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightBold];
            button.contentTintColor = [NSColor systemGreenColor];
            button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
            title = [NSString stringWithFormat:@"%@  ✓", title];
        } else {
            // 未激活状态：普通外观
            cellView.layer.backgroundColor = [NSColor clearColor].CGColor;
            cellView.layer.borderColor = [NSColor clearColor].CGColor;
            cellView.layer.borderWidth = 0;
            
            button.image = [NSImage imageWithSystemSymbolName:@"circle" accessibilityDescription:nil];
            button.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:14 weight:NSFontWeightRegular];
            button.contentTintColor = [NSColor secondaryLabelColor];
            button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
        }
        button.title = title;
        button.tag = row;
    }
    
    return cellView;
}

- (void)profileRowClicked:(NSButton *)sender {
    NSInteger row = sender.tag;
    NSArray<CXProfile *> *profiles = [CXProfileManager sharedManager].allProfiles;
    
    if (row >= 0 && row < profiles.count) {
        CXProfile *profile = profiles[row];
        [self applyProfile:profile];
    }
}

- (void)applyProfile:(CXProfile *)profile {
    // 获取 API Key
    NSString *apiKey = [[CXKeychainManager sharedManager] getAPIKeyForProfileId:profile.profileId error:nil];
    
    if (!apiKey) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法切换";
        alert.informativeText = @"找不到此 Profile 的 API Key";
        [alert runModal];
        return;
    }
    
    NSError *error = nil;
    BOOL success = [[CXConfigManager sharedManager] applyProfile:profile apiKey:apiKey error:&error];
    
    if (success) {
        [[CXProfileManager sharedManager] activateProfile:profile error:nil];
        [self refresh];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"切换失败";
        alert.informativeText = error.localizedDescription ?: @"未知错误";
        [alert runModal];
    }
}

@end
