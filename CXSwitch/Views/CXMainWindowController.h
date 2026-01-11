//
//  CXMainWindowController.h
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * CXMainWindowController - 主窗口控制器
 * 包含仪表盘、账号管理、设置三个 Tab
 */
@interface CXMainWindowController : NSWindowController

/// 切换到指定 Tab
/// @param index Tab 索引（0=仪表盘, 1=账号管理, 2=设置）
- (void)selectTabAtIndex:(NSInteger)index;

/// 刷新所有视图
- (void)refreshAll;

@end

NS_ASSUME_NONNULL_END
