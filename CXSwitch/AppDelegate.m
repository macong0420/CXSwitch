//
//  AppDelegate.m
//  CXSwitch
//
//  Created by 马聪聪 on 2026/1/10.
//

#import "AppDelegate.h"
#import "CXStatusItemController.h"
#import "CXProfileManager.h"
#import "CXCodexRunner.h"
#import "CXConfigManager.h"

@interface AppDelegate ()

@property (nonatomic, strong) CXStatusItemController *statusItemController;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // 设置主菜单（启用 Edit 菜单以支持复制粘贴）
    [self setupMainMenu];
    
    // 初始化菜单栏控制器
    self.statusItemController = [[CXStatusItemController alloc] init];
    [self.statusItemController setup];
    
    // 加载 Profiles
    [CXProfileManager sharedManager];
    
    // 检测 Codex 路径
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[CXCodexRunner sharedRunner] detectCodexPath];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.statusItemController updateStatus];
        });
    });
    
    NSLog(@"CXSwitch 已启动");
}

- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    
    // 1. 应用菜单
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"关于 CXSwitch" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"隐藏 CXSwitch" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthersItem = [appMenu addItemWithTitle:@"隐藏其他" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthersItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"显示全部" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"退出 CXSwitch" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];
    
    // 2. Edit 菜单（关键：复制粘贴等）
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"拷贝" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"粘贴并匹配样式" action:@selector(pasteAsPlainText:) keyEquivalent:@"V"];
    [editMenu addItemWithTitle:@"删除" action:@selector(delete:) keyEquivalent:@""];
    [editMenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;
    [mainMenu addItem:editMenuItem];
    
    // 3. Window 菜单
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"窗口"];
    [windowMenu addItemWithTitle:@"最小化" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"缩放" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"前置全部窗口" action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowMenuItem.submenu = windowMenu;
    [mainMenu addItem:windowMenuItem];
    
    [NSApp setMainMenu:mainMenu];
    [NSApp setWindowsMenu:windowMenu];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // 保存 Profiles
    [[CXProfileManager sharedManager] saveWithError:nil];
    NSLog(@"CXSwitch 已退出");
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

// 点击 Dock 图标时显示主窗口（如果启用了 Dock 图标）
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        [self.statusItemController openMainWindow];
    }
    return YES;
}

@end

