//
//  CXStatusItemController.m
//  CXSwitch
//
//  Created by Mr.C on 2026/1/10.
//

#import "CXStatusItemController.h"
#import "CXPopoverViewController.h"
#import "CXMainWindowController.h"
#import "CXProfileManager.h"
#import "CXConfigManager.h"
#import "CXKeychainManager.h"
#import "CXTerminalLauncher.h"
#import "CXCodexRunner.h"

@interface CXStatusItemController ()

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) CXPopoverViewController *popoverViewController;
@property (nonatomic, strong) CXMainWindowController *mainWindowController;
@property (nonatomic, strong) id eventMonitor;

@end

@implementation CXStatusItemController

- (void)setup {
    // 创建状态栏项
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    if (self.statusItem.button) {
        // 设置图标
        NSImage *image = [NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath" 
                                   accessibilityDescription:@"CXSwitch"];
        if (!image) {
            // 后备方案：使用文本
            image = [self createTextImage:@"CX"];
        }
        [image setTemplate:YES];
        self.statusItem.button.image = image;
        self.statusItem.button.imagePosition = NSImageLeft;
        
        // 点击事件
        self.statusItem.button.action = @selector(statusItemClicked:);
        self.statusItem.button.target = self;
        
        // 右键菜单
        [self setupMenu];
    }
    
    // 创建 Popover
    [self setupPopover];
    
    // 监听 Profile 变化
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(profileDidChange:) 
                                                 name:CXActiveProfileDidChangeNotification 
                                               object:nil];
    
    // 更新初始状态
    [self updateStatus];
}

- (NSImage *)createTextImage:(NSString *)text {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    NSSize size = [text sizeWithAttributes:attrs];
    
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [text drawAtPoint:NSZeroPoint withAttributes:attrs];
    [image unlockFocus];
    
    return image;
}

- (void)setupPopover {
    self.popover = [[NSPopover alloc] init];
    self.popoverViewController = [[CXPopoverViewController alloc] init];
    self.popoverViewController.statusItemController = self;
    
    self.popover.contentViewController = self.popoverViewController;
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.animates = YES;
}

- (void)setupMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    
    [menu addItemWithTitle:@"打开主窗口" action:@selector(openMainWindow) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出" action:@selector(quit) keyEquivalent:@"q"];
    
    for (NSMenuItem *item in menu.itemArray) {
        item.target = self;
    }
    
    // 右键显示菜单
    self.statusItem.menu = nil; // 左键不显示菜单
}

#pragma mark - Actions

- (void)statusItemClicked:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    
    if (event.type == NSEventTypeRightMouseUp || 
        (event.modifierFlags & NSEventModifierFlagControl)) {
        // 右键或 Ctrl+点击：显示菜单
        [self showMenu];
    } else {
        // 左键：切换 Popover
        [self togglePopover];
    }
}

- (void)showMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    
    [menu addItemWithTitle:@"打开主窗口" action:@selector(openMainWindow) keyEquivalent:@""];
    [menu addItemWithTitle:@"打开 Terminal 并启动 Codex" action:@selector(openTerminalAndLaunchCodex) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    
    // 快速切换 Profiles
    CXProfileManager *manager = [CXProfileManager sharedManager];
    if (manager.allProfiles.count > 0) {
        [menu addItemWithTitle:@"切换 Profile" action:nil keyEquivalent:@""];
        for (CXProfile *profile in manager.allProfiles) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:profile.name 
                                                          action:@selector(switchToProfile:) 
                                                   keyEquivalent:@""];
            item.target = self;
            item.representedObject = profile;
            if (profile.isActive) {
                item.state = NSControlStateValueOn;
            }
            [menu addItem:item];
        }
        [menu addItem:[NSMenuItem separatorItem]];
    }
    
    // Official 模式
    NSMenuItem *officialItem = [[NSMenuItem alloc] initWithTitle:@"Official 登录" 
                                                          action:@selector(switchToOfficial) 
                                                   keyEquivalent:@""];
    officialItem.target = self;
    if (manager.isOfficialMode) {
        officialItem.state = NSControlStateValueOn;
    }
    [menu addItem:officialItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出" action:@selector(quit) keyEquivalent:@"q"];
    
    for (NSMenuItem *item in menu.itemArray) {
        if (!item.target) {
            item.target = self;
        }
    }
    
    [self.statusItem.button performClick:nil];
    [self.statusItem popUpStatusItemMenu:menu];
}

- (void)openTerminalAndLaunchCodex {
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

    CXCodexRunner *runner = [CXCodexRunner sharedRunner];
    NSString *codexCmd = runner.codexPath.length > 0 ? [CXTerminalLauncher shellQuotedString:runner.codexPath] : @"codex";

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

    NSString *command = [NSString stringWithFormat:@"cd \"$HOME\"; %@%@%@", envPrefix, banner, codexCmd];

    NSError *error = nil;
    if (![CXTerminalLauncher openTerminalAndRunCommand:command error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法打开 Terminal";
        alert.informativeText = error.localizedDescription ?: @"未知错误";
        [alert runModal];
    }
}

- (void)switchToProfile:(NSMenuItem *)sender {
    CXProfile *profile = sender.representedObject;
    if (profile) {
        NSString *apiKey = [[CXKeychainManager sharedManager] getAPIKeyForProfileId:profile.profileId error:nil];
        if (!apiKey) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"无法切换";
            alert.informativeText = @"找不到此 Profile 的 API Key";
            [alert runModal];
            return;
        }

        NSError *error = nil;
        BOOL applied = [[CXConfigManager sharedManager] applyProfile:profile apiKey:apiKey error:&error];
        if (!applied) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"切换失败";
            alert.informativeText = error.localizedDescription ?: @"未知错误";
            [alert runModal];
            return;
        }

        [[CXProfileManager sharedManager] activateProfile:profile error:nil];
        [self updateStatus];
    }
}

- (void)switchToOfficial {
    NSError *error = nil;
    BOOL applied = [[CXConfigManager sharedManager] applyOfficialModeWithError:&error];
    if (!applied) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"切换失败";
        alert.informativeText = error.localizedDescription ?: @"未知错误";
        [alert runModal];
        return;
    }

    [[CXProfileManager sharedManager] switchToOfficialModeWithError:nil];
    [self updateStatus];
}

- (void)quit {
    [NSApp terminate:nil];
}

#pragma mark - Popover

- (void)showPopover {
    if (self.statusItem.button) {
        [self.popoverViewController refresh];
        [self.popover showRelativeToRect:self.statusItem.button.bounds 
                                  ofView:self.statusItem.button 
                           preferredEdge:NSRectEdgeMinY];
        
        // 添加事件监听器，点击外部时关闭
        [self addEventMonitor];
    }
}

- (void)hidePopover {
    [self.popover close];
    [self removeEventMonitor];
}

- (void)togglePopover {
    if (self.popover.isShown) {
        [self hidePopover];
    } else {
        [self showPopover];
    }
}

- (void)addEventMonitor {
    if (self.eventMonitor) return;
    
    __weak typeof(self) weakSelf = self;
    self.eventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:
                         (NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown)
                                                               handler:^(NSEvent *event) {
        [weakSelf hidePopover];
    }];
}

- (void)removeEventMonitor {
    if (self.eventMonitor) {
        [NSEvent removeMonitor:self.eventMonitor];
        self.eventMonitor = nil;
    }
}

#pragma mark - Main Window

- (void)openMainWindow {
    [self hidePopover];
    
    if (!self.mainWindowController) {
        self.mainWindowController = [[CXMainWindowController alloc] init];
    }
    
    [self.mainWindowController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - Status Update

- (void)updateStatus {
    CXProfileManager *manager = [CXProfileManager sharedManager];
    
    if (self.statusItem.button) {
        if (manager.isOfficialMode) {
            self.statusItem.button.toolTip = @"CXSwitch - Official 模式";
        } else if (manager.activeProfile) {
            self.statusItem.button.toolTip = [NSString stringWithFormat:@"CXSwitch - %@", 
                                              manager.activeProfile.name];
        } else {
            self.statusItem.button.toolTip = @"CXSwitch - 未配置";
        }
    }
}

#pragma mark - Notifications

- (void)profileDidChange:(NSNotification *)notification {
    [self updateStatus];
}

- (void)dealloc {
    [self removeEventMonitor];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
