//
//  AppDelegate.h
//  CXSwitch
//
//  Created by 马聪聪 on 2026/1/10.
//

#import <Cocoa/Cocoa.h>

@class CXStatusItemController;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong, readonly) CXStatusItemController *statusItemController;

@end
