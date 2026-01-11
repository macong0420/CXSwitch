//
//  CXPopoverViewController.h
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import <Cocoa/Cocoa.h>

@class CXStatusItemController;

NS_ASSUME_NONNULL_BEGIN

/**
 * CXPopoverViewController - Popover 快速切换视图控制器
 */
@interface CXPopoverViewController : NSViewController

/// 关联的状态栏控制器
@property (nonatomic, weak, nullable) CXStatusItemController *statusItemController;

/// 刷新视图
- (void)refresh;

@end

NS_ASSUME_NONNULL_END
