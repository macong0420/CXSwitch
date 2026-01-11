//
//  CXSettingsViewController.m
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import "CXSettingsViewController.h"
#import "CXCodexRunner.h"
#import "CXConfigManager.h"
#import <ServiceManagement/ServiceManagement.h>

static NSString * const kCodexPathDefaultsKey = @"CXSwitch.CodexPath";

@interface CXSettingsViewController ()

// Codex 路径
@property (nonatomic, strong) NSTextField *codexPathField;
@property (nonatomic, strong) NSButton *detectButton;
@property (nonatomic, strong) NSTextField *codexStatusLabel;

// 通用设置
@property (nonatomic, strong) NSPopUpButton *themePopup;
@property (nonatomic, strong) NSButton *launchAtLoginCheckbox;

// 关于
@property (nonatomic, strong) NSTextField *versionLabel;

@end

@implementation CXSettingsViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self refresh];
}

- (void)setupUI {
    // 主滚动视图
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:scrollView];
    
    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
    scrollView.documentView = contentView;
    
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
    
    // Codex 路径设置
    [mainStack addArrangedSubview:[self createCodexPathSection]];
    
    // 通用设置
    [mainStack addArrangedSubview:[self createGeneralSection]];
    
    // 关于
    [mainStack addArrangedSubview:[self createAboutSection]];
}

- (NSView *)createCodexPathSection {
    NSBox *section = [[NSBox alloc] init];
    section.title = @"Codex 路径";
    section.titleFont = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    section.boxType = NSBoxPrimary;
    section.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 路径输入行
    NSStackView *pathRow = [[NSStackView alloc] init];
    pathRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    pathRow.spacing = 8;
    
    self.codexPathField = [[NSTextField alloc] init];
    self.codexPathField.placeholderString = @"/path/to/codex";
    self.codexPathField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.codexPathField.widthAnchor constraintEqualToConstant:400].active = YES;
    [pathRow addArrangedSubview:self.codexPathField];
    
    NSButton *browseButton = [NSButton buttonWithTitle:@"浏览..." target:self action:@selector(browseCodexPath:)];
    browseButton.bezelStyle = NSBezelStyleRounded;
    [pathRow addArrangedSubview:browseButton];
    
    self.detectButton = [NSButton buttonWithTitle:@"自动检测" target:self action:@selector(detectCodexPath:)];
    self.detectButton.bezelStyle = NSBezelStyleRounded;
    [pathRow addArrangedSubview:self.detectButton];
    
    [stack addArrangedSubview:pathRow];
    
    // 状态显示
    self.codexStatusLabel = [NSTextField labelWithString:@"状态：检测中..."];
    self.codexStatusLabel.font = [NSFont systemFontOfSize:12];
    self.codexStatusLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:self.codexStatusLabel];
    
    // 说明
    NSTextField *helpText = [NSTextField wrappingLabelWithString:@"如果自动检测失败，请手动指定 codex 可执行文件的路径。常见位置：\n• /opt/homebrew/lib/node_modules/@openai/codex/vendor/.../codex/codex (Homebrew)\n• ~/.n/lib/node_modules/@openai/codex/vendor/.../codex/codex (n)\n• /opt/homebrew/bin/codex (可能是 JS wrapper，Node 版本不匹配时会不可用)"];
    helpText.font = [NSFont systemFontOfSize:11];
    helpText.textColor = [NSColor tertiaryLabelColor];
    [stack addArrangedSubview:helpText];
    
    [section.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:section.contentView.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:section.contentView.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:section.contentView.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:section.contentView.bottomAnchor constant:-12],
        [section.widthAnchor constraintEqualToConstant:700]
    ]];
    
    return section;
}

- (NSView *)createGeneralSection {
    NSBox *section = [[NSBox alloc] init];
    section.title = @"通用设置";
    section.titleFont = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    section.boxType = NSBoxPrimary;
    section.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 主题
    NSStackView *themeRow = [[NSStackView alloc] init];
    themeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    themeRow.spacing = 8;
    
    NSTextField *themeLabel = [NSTextField labelWithString:@"主题："];
    themeLabel.font = [NSFont systemFontOfSize:13];
    [themeRow addArrangedSubview:themeLabel];
    
    self.themePopup = [[NSPopUpButton alloc] init];
    [self.themePopup addItemsWithTitles:@[@"跟随系统", @"浅色", @"深色"]];
    self.themePopup.target = self;
    self.themePopup.action = @selector(themeChanged:);
    [themeRow addArrangedSubview:self.themePopup];
    
    [stack addArrangedSubview:themeRow];
    
    // 开机启动
    self.launchAtLoginCheckbox = [NSButton checkboxWithTitle:@"开机自动启动 CXSwitch" 
                                                      target:self 
                                                      action:@selector(launchAtLoginChanged:)];
    [stack addArrangedSubview:self.launchAtLoginCheckbox];
    
    [section.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:section.contentView.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:section.contentView.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:section.contentView.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:section.contentView.bottomAnchor constant:-12],
        [section.widthAnchor constraintEqualToConstant:700]
    ]];
    
    return section;
}

- (NSView *)createAboutSection {
    NSBox *section = [[NSBox alloc] init];
    section.title = @"关于";
    section.titleFont = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    section.boxType = NSBoxPrimary;
    section.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    NSTextField *appName = [NSTextField labelWithString:@"CXSwitch"];
    appName.font = [NSFont systemFontOfSize:16 weight:NSFontWeightBold];
    [stack addArrangedSubview:appName];
    
    self.versionLabel = [NSTextField labelWithString:@"版本 1.0.0"];
    self.versionLabel.font = [NSFont systemFontOfSize:12];
    self.versionLabel.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:self.versionLabel];
    
    NSTextField *description = [NSTextField wrappingLabelWithString:@"一个 macOS 菜单栏工具，用于快速切换 Codex 配置。"];
    description.font = [NSFont systemFontOfSize:12];
    description.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:description];
    
    [section.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:section.contentView.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:section.contentView.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:section.contentView.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:section.contentView.bottomAnchor constant:-12],
        [section.widthAnchor constraintEqualToConstant:700]
    ]];
    
    return section;
}

#pragma mark - Refresh

- (void)refresh {
    CXCodexRunner *runner = [CXCodexRunner sharedRunner];
    
    // Codex 路径
    self.codexPathField.stringValue = runner.codexPath ?: @"";
    
    if (runner.isCodexAvailable) {
        NSString *version = runner.detectedVersion ?: @"未知版本";
        self.codexStatusLabel.stringValue = [NSString stringWithFormat:@"✅ 已检测到：%@", version];
        self.codexStatusLabel.textColor = [NSColor systemGreenColor];
    } else {
        self.codexStatusLabel.stringValue = @"❌ 未检测到可用的 Codex";
        self.codexStatusLabel.textColor = [NSColor systemRedColor];
    }
    
    // 版本
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"1";
    self.versionLabel.stringValue = [NSString stringWithFormat:@"版本 %@ (%@)", version, build];
}

#pragma mark - Actions

- (void)browseCodexPath:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = @"选择 codex 可执行文件";
    
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *url = panel.URLs.firstObject;
            if (url) {
                self.codexPathField.stringValue = url.path;
                [CXCodexRunner sharedRunner].codexPath = url.path;
                [[NSUserDefaults standardUserDefaults] setObject:url.path forKey:kCodexPathDefaultsKey];
                [self refresh];
            }
        }
    }];
}

- (void)detectCodexPath:(id)sender {
    self.codexStatusLabel.stringValue = @"🔍 正在检测...";
    self.codexStatusLabel.textColor = [NSColor secondaryLabelColor];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *path = [[CXCodexRunner sharedRunner] detectCodexPath];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (path) {
                self.codexPathField.stringValue = path;
                [[NSUserDefaults standardUserDefaults] setObject:path forKey:kCodexPathDefaultsKey];
                [self refresh];
            } else {
                self.codexStatusLabel.stringValue = @"❌ 自动检测失败，请手动指定路径";
                self.codexStatusLabel.textColor = [NSColor systemRedColor];
            }
        });
    });
}

- (void)themeChanged:(id)sender {
    NSInteger index = self.themePopup.indexOfSelectedItem;
    
    NSAppearance *appearance = nil;
    switch (index) {
        case 0: // 跟随系统
            appearance = nil;
            break;
        case 1: // 浅色
            appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            break;
        case 2: // 深色
            appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            break;
    }
    
    [NSApp setAppearance:appearance];
}

- (void)launchAtLoginChanged:(id)sender {
    // 注意：需要配置 Login Items 或使用 ServiceManagement
    // 这里提供基本框架
    BOOL enabled = self.launchAtLoginCheckbox.state == NSControlStateValueOn;
    
    // 保存设置
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"LaunchAtLogin"];
    
    if (enabled) {
        // 启用开机启动（需要额外配置）
        NSLog(@"Enable launch at login");
    } else {
        // 禁用开机启动
        NSLog(@"Disable launch at login");
    }
}

@end
