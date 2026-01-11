//
//  CXStatusItemController.h
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * CXStatusItemController - 菜单栏状态项控制器
 * 负责菜单栏图标和 Popover 的显示
 */
@interface CXStatusItemController : NSObject

/// 设置菜单栏项
- (void)setup;

/// 显示 Popover
- (void)showPopover;

/// 隐藏 Popover
- (void)hidePopover;

/// 切换 Popover 显示状态
- (void)togglePopover;

/// 打开主窗口
- (void)openMainWindow;

/// 更新状态显示
- (void)updateStatus;

@end

NS_ASSUME_NONNULL_END
