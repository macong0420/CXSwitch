//
//  CXMainWindowController.m
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import "CXMainWindowController.h"
#import "CXDashboardViewController.h"
#import "CXProfileListViewController.h"
#import "CXSettingsViewController.h"

@interface CXMainWindowController () <NSToolbarDelegate>

@property (nonatomic, strong) NSTabViewController *tabViewController;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic, strong) NSSegmentedControl *tabControl;

@end

@implementation CXMainWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 600)
                                                   styleMask:NSWindowStyleMaskTitled | 
                                                             NSWindowStyleMaskClosable | 
                                                             NSWindowStyleMaskMiniaturizable | 
                                                             NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    
    self = [super initWithWindow:window];
    if (self) {
        [self setupWindow];
        [self setupTabViewController];
        [self setupToolbar];
    }
    return self;
}

- (void)setupWindow {
    self.window.title = @"CXSwitch";
    self.window.minSize = NSMakeSize(700, 500);
    [self.window center];
    
    // 设置窗口样式
    self.window.titlebarAppearsTransparent = NO;
    self.window.movableByWindowBackground = YES;
}

- (void)setupTabViewController {
    self.tabViewController = [[NSTabViewController alloc] init];
    self.tabViewController.tabStyle = NSTabViewControllerTabStyleUnspecified;
    
    // 仪表盘
    CXDashboardViewController *dashboardVC = [[CXDashboardViewController alloc] init];
    NSTabViewItem *dashboardItem = [NSTabViewItem tabViewItemWithViewController:dashboardVC];
    dashboardItem.label = @"仪表盘";
    dashboardItem.image = [NSImage imageWithSystemSymbolName:@"gauge" accessibilityDescription:nil];
    [self.tabViewController addTabViewItem:dashboardItem];
    
    // 账号管理
    CXProfileListViewController *profileVC = [[CXProfileListViewController alloc] init];
    NSTabViewItem *profileItem = [NSTabViewItem tabViewItemWithViewController:profileVC];
    profileItem.label = @"账号管理";
    profileItem.image = [NSImage imageWithSystemSymbolName:@"person.2" accessibilityDescription:nil];
    [self.tabViewController addTabViewItem:profileItem];
    
    // 设置
    CXSettingsViewController *settingsVC = [[CXSettingsViewController alloc] init];
    NSTabViewItem *settingsItem = [NSTabViewItem tabViewItemWithViewController:settingsVC];
    settingsItem.label = @"设置";
    settingsItem.image = [NSImage imageWithSystemSymbolName:@"gear" accessibilityDescription:nil];
    [self.tabViewController addTabViewItem:settingsItem];
    
    self.window.contentViewController = self.tabViewController;
}

- (void)setupToolbar {
    self.toolbar = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
    self.toolbar.delegate = self;
    self.toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    self.toolbar.allowsUserCustomization = NO;
    
    self.window.toolbar = self.toolbar;
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarFlexibleSpaceItemIdentifier, @"TabSwitcher", NSToolbarFlexibleSpaceItemIdentifier];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarFlexibleSpaceItemIdentifier, @"TabSwitcher", NSToolbarFlexibleSpaceItemIdentifier];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar 
     itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier 
 willBeInsertedIntoToolbar:(BOOL)flag {
    
    if ([itemIdentifier isEqualToString:@"TabSwitcher"]) {
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
        
        self.tabControl = [[NSSegmentedControl alloc] init];
        self.tabControl.segmentStyle = NSSegmentStyleSeparated;
        self.tabControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
        self.tabControl.segmentCount = 3;
        
        [self.tabControl setLabel:@"仪表盘" forSegment:0];
        [self.tabControl setLabel:@"账号管理" forSegment:1];
        [self.tabControl setLabel:@"设置" forSegment:2];
        
        [self.tabControl setImage:[NSImage imageWithSystemSymbolName:@"gauge" accessibilityDescription:nil] forSegment:0];
        [self.tabControl setImage:[NSImage imageWithSystemSymbolName:@"person.2" accessibilityDescription:nil] forSegment:1];
        [self.tabControl setImage:[NSImage imageWithSystemSymbolName:@"gear" accessibilityDescription:nil] forSegment:2];
        
        [self.tabControl setWidth:100 forSegment:0];
        [self.tabControl setWidth:100 forSegment:1];
        [self.tabControl setWidth:100 forSegment:2];
        
        self.tabControl.selectedSegment = 0;
        self.tabControl.target = self;
        self.tabControl.action = @selector(tabControlChanged:);
        
        item.view = self.tabControl;
        item.label = @"";
        
        return item;
    }
    
    return nil;
}

- (void)tabControlChanged:(NSSegmentedControl *)sender {
    [self selectTabAtIndex:sender.selectedSegment];
}

#pragma mark - Public Methods

- (void)selectTabAtIndex:(NSInteger)index {
    if (index >= 0 && index < self.tabViewController.tabViewItems.count) {
        self.tabViewController.selectedTabViewItemIndex = index;
        self.tabControl.selectedSegment = index;
    }
}

- (void)refreshAll {
    for (NSTabViewItem *item in self.tabViewController.tabViewItems) {
        NSViewController *vc = item.viewController;
        if ([vc respondsToSelector:@selector(refresh)]) {
            [vc performSelector:@selector(refresh)];
        }
    }
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self refreshAll];
}

@end
