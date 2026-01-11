//
//  CXImportPreviewWindowController.m
//  CXSwitch
//
//  Created by Codex CLI on 2026/1/10.
//

#import "CXImportPreviewWindowController.h"

#import "CXLocalConfigImporter.h"
#import "CXProfile.h"

@interface CXImportPreviewItem : NSObject
@property(nonatomic, strong) CXLocalConfigImportCandidate *candidate;
@property(nonatomic, assign) BOOL selected;
@property(nonatomic, assign) BOOL disabled;
@property(nonatomic, assign) BOOL duplicate;
@property(nonatomic, copy, nullable) NSString *statusText;
@property(nonatomic, copy, nullable) NSString *normalizedBaseURL;
@end

@implementation CXImportPreviewItem
@end

@interface CXImportPreviewWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property(nonatomic, copy) CXImportPreviewCompletion completion;
@property(nonatomic, strong) NSArray<CXProfile *> *existingProfiles;
@property(nonatomic, strong) NSMutableArray<CXImportPreviewItem *> *items;
@property(nonatomic, assign) CXImportDedupeStrategy dedupeStrategy;

@property(nonatomic, strong) NSTextField *summaryLabel;
@property(nonatomic, strong) NSPopUpButton *dedupePopup;
@property(nonatomic, strong) NSTableView *tableView;
@property(nonatomic, strong) NSButton *selectAllButton;
@property(nonatomic, strong) NSButton *selectNoneButton;
@property(nonatomic, strong) NSButton *importButton;
@property(nonatomic, strong) NSButton *cancelButton;

@end

@implementation CXImportPreviewWindowController

+ (void)beginSheetForWindow:(NSWindow *)window
                 candidates:(NSArray<CXLocalConfigImportCandidate *> *)candidates
            existingProfiles:(NSArray<CXProfile *> *)existingProfiles
                 completion:(CXImportPreviewCompletion)completion {
    CXImportPreviewWindowController *wc = [[CXImportPreviewWindowController alloc] initWithCandidates:candidates existingProfiles:existingProfiles];
    wc.completion = completion;

    [window beginSheet:wc.window completionHandler:^(NSModalResponse returnCode) {
        (void)returnCode;
        // Completion is triggered by buttons; if user closes via window close, treat as cancel.
        if (wc.completion) {
            wc.completion(@[]);
            wc.completion = nil;
        }
    }];
}

- (instancetype)initWithCandidates:(NSArray<CXLocalConfigImportCandidate *> *)candidates
                   existingProfiles:(NSArray<CXProfile *> *)existingProfiles {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 720, 420)
                                                styleMask:(NSWindowStyleMaskTitled |
                                                           NSWindowStyleMaskClosable)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = @"导入预览";
    panel.floatingPanel = NO;
    panel.hidesOnDeactivate = NO;

    self = [super initWithWindow:panel];
    if (self) {
        _existingProfiles = existingProfiles ?: @[];
        _items = [[NSMutableArray alloc] init];
        _dedupeStrategy = CXImportDedupeStrategySkipByBaseURL;

        [self buildItemsFromCandidates:candidates ?: @[]];
        [self setupUI];
        [self.dedupePopup selectItemAtIndex:0];
        [self applyDedupeAndRefreshSelectionDefaults];
        [self updateSummary];
    }
    return self;
}

#pragma mark - UI

- (void)setupUI {
    NSView *content = self.window.contentView;
    content.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *main = [[NSStackView alloc] init];
    main.orientation = NSUserInterfaceLayoutOrientationVertical;
    main.spacing = 10;
    main.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    main.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:main];

    [NSLayoutConstraint activateConstraints:@[
        [main.topAnchor constraintEqualToAnchor:content.topAnchor],
        [main.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [main.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [main.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    self.summaryLabel = [NSTextField labelWithString:@"-"];
    self.summaryLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    [main addArrangedSubview:self.summaryLabel];

    NSStackView *controls = [[NSStackView alloc] init];
    controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controls.spacing = 10;
    controls.distribution = NSStackViewDistributionFill;
    [main addArrangedSubview:controls];

    NSTextField *dedupeLabel = [NSTextField labelWithString:@"去重策略："];
    dedupeLabel.font = [NSFont systemFontOfSize:12];
    [controls addArrangedSubview:dedupeLabel];

    self.dedupePopup = [[NSPopUpButton alloc] init];
    [self.dedupePopup addItemWithTitle:@"跳过重复（按 Base URL）"];
    [self.dedupePopup addItemWithTitle:@"允许重复导入"];
    self.dedupePopup.target = self;
    self.dedupePopup.action = @selector(dedupeChanged:);
    [controls addArrangedSubview:self.dedupePopup];

    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [controls addArrangedSubview:spacer];

    self.selectAllButton = [NSButton buttonWithTitle:@"全选（非重复）" target:self action:@selector(selectAll:)];
    self.selectAllButton.bezelStyle = NSBezelStyleRounded;
    self.selectAllButton.controlSize = NSControlSizeSmall;
    [controls addArrangedSubview:self.selectAllButton];

    self.selectNoneButton = [NSButton buttonWithTitle:@"全不选" target:self action:@selector(selectNone:)];
    self.selectNoneButton.bezelStyle = NSBezelStyleRounded;
    self.selectNoneButton.controlSize = NSControlSizeSmall;
    [controls addArrangedSubview:self.selectNoneButton];

    // Table
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;

    self.tableView = [[NSTableView alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.headerView = nil;
    self.tableView.rowHeight = 28;
    self.tableView.usesAlternatingRowBackgroundColors = YES;

    NSTableColumn *colSelect = [[NSTableColumn alloc] initWithIdentifier:@"select"];
    colSelect.width = 70;
    [self.tableView addTableColumn:colSelect];

    NSTableColumn *colName = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    colName.width = 190;
    [self.tableView addTableColumn:colName];

    NSTableColumn *colURL = [[NSTableColumn alloc] initWithIdentifier:@"url"];
    colURL.width = 320;
    [self.tableView addTableColumn:colURL];

    NSTableColumn *colStatus = [[NSTableColumn alloc] initWithIdentifier:@"status"];
    colStatus.width = 120;
    [self.tableView addTableColumn:colStatus];

    scroll.documentView = self.tableView;
    [main addArrangedSubview:scroll];

    [scroll.heightAnchor constraintEqualToConstant:270].active = YES;

    // Bottom buttons
    NSStackView *bottom = [[NSStackView alloc] init];
    bottom.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bottom.spacing = 10;
    bottom.distribution = NSStackViewDistributionFill;
    [main addArrangedSubview:bottom];

    NSView *bottomSpacer = [[NSView alloc] init];
    [bottomSpacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bottom addArrangedSubview:bottomSpacer];

    self.cancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancel:)];
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    [bottom addArrangedSubview:self.cancelButton];

    self.importButton = [NSButton buttonWithTitle:@"导入所选" target:self action:@selector(importSelected:)];
    self.importButton.bezelStyle = NSBezelStyleTexturedRounded;
    self.importButton.keyEquivalent = @"\r";
    [bottom addArrangedSubview:self.importButton];
}

#pragma mark - Data

- (void)buildItemsFromCandidates:(NSArray<CXLocalConfigImportCandidate *> *)candidates {
    [self.items removeAllObjects];
    for (CXLocalConfigImportCandidate *c in candidates) {
        if (![c isKindOfClass:[CXLocalConfigImportCandidate class]]) continue;

        CXImportPreviewItem *item = [[CXImportPreviewItem alloc] init];
        item.candidate = c;
        item.selected = YES;
        item.disabled = NO;
        item.duplicate = NO;
        item.normalizedBaseURL = [CXProfile normalizeBaseURL:c.baseURL ?: @""];
        [self.items addObject:item];
    }
}

- (void)applyDedupeAndRefreshSelectionDefaults {
    // Build existing base URL set
    NSMutableSet<NSString *> *existingURLs = [NSMutableSet set];
    for (CXProfile *p in self.existingProfiles) {
        NSString *url = [CXProfile normalizeBaseURL:p.baseURL ?: @""];
        if (url.length > 0) [existingURLs addObject:url.lowercaseString];
    }

    // Reset flags
    for (CXImportPreviewItem *item in self.items) {
        item.duplicate = NO;
        item.disabled = NO;
        item.statusText = nil;
    }

    // Mark invalid (missing baseURL)
    for (CXImportPreviewItem *item in self.items) {
        if (item.normalizedBaseURL.length == 0) {
            item.disabled = YES;
            item.selected = NO;
            item.statusText = @"缺少 Base URL";
        }
    }

    if (self.dedupeStrategy == CXImportDedupeStrategyAllowDuplicates) {
        // only mark missing key
        for (CXImportPreviewItem *item in self.items) {
            if (item.disabled) continue;
            if (item.candidate.apiKey.length == 0) {
                item.statusText = @"缺少 API Key";
            } else {
                item.statusText = @"";
            }
        }
        [self.tableView reloadData];
        return;
    }

    // Skip duplicates by baseURL (existing)
    for (CXImportPreviewItem *item in self.items) {
        if (item.disabled) continue;
        if (item.normalizedBaseURL.length == 0) continue;

        if ([existingURLs containsObject:item.normalizedBaseURL.lowercaseString]) {
            item.duplicate = YES;
            item.selected = NO;
            item.statusText = @"已存在";
        }
    }

    // Skip duplicates within candidates: keep first non-duplicate
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (CXImportPreviewItem *item in self.items) {
        if (item.disabled) continue;
        if (item.duplicate) continue;
        NSString *key = item.normalizedBaseURL.lowercaseString;
        if (key.length == 0) continue;
        if ([seen containsObject:key]) {
            item.duplicate = YES;
            item.selected = NO;
            item.statusText = @"重复";
        } else {
            [seen addObject:key];
        }
    }

    // Mark missing key (still selectable)
    for (CXImportPreviewItem *item in self.items) {
        if (item.disabled) continue;
        if (item.duplicate) continue;
        if (item.candidate.apiKey.length == 0) {
            item.statusText = @"缺少 API Key";
        } else {
            item.statusText = @"";
        }
    }

    [self.tableView reloadData];
}

- (void)updateSummary {
    NSInteger total = self.items.count;
    NSInteger selected = 0;
    NSInteger duplicates = 0;
    NSInteger missingKey = 0;
    for (CXImportPreviewItem *item in self.items) {
        if (item.duplicate) duplicates += 1;
        if (!item.disabled && item.candidate.apiKey.length == 0) missingKey += 1;
        if (item.selected) selected += 1;
    }

    NSString *dedupeText = self.dedupeStrategy == CXImportDedupeStrategySkipByBaseURL ? @"跳过重复" : @"允许重复";
    self.summaryLabel.stringValue = [NSString stringWithFormat:@"发现 %ld 条候选，已选 %ld 条（重复 %ld，缺 key %ld，策略：%@）",
                                     (long)total, (long)selected, (long)duplicates, (long)missingKey, dedupeText];
    self.importButton.enabled = selected > 0;
}

#pragma mark - Actions

- (void)dedupeChanged:(id)sender {
    (void)sender;
    self.dedupeStrategy = (CXImportDedupeStrategy)self.dedupePopup.indexOfSelectedItem;
    [self applyDedupeAndRefreshSelectionDefaults];
    [self updateSummary];
}

- (void)selectAll:(id)sender {
    (void)sender;
    for (CXImportPreviewItem *item in self.items) {
        if (item.disabled) continue;
        if (self.dedupeStrategy == CXImportDedupeStrategySkipByBaseURL && item.duplicate) continue;
        item.selected = YES;
    }
    [self.tableView reloadData];
    [self updateSummary];
}

- (void)selectNone:(id)sender {
    (void)sender;
    for (CXImportPreviewItem *item in self.items) {
        item.selected = NO;
    }
    [self.tableView reloadData];
    [self updateSummary];
}

- (void)importSelected:(id)sender {
    (void)sender;
    NSMutableArray<CXLocalConfigImportCandidate *> *selected = [NSMutableArray array];
    for (CXImportPreviewItem *item in self.items) {
        if (!item.selected) continue;
        if (item.disabled) continue;
        [selected addObject:item.candidate];
    }

    if (self.completion) {
        self.completion([selected copy]);
        self.completion = nil;
    }

    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
    (void)sender;
    if (self.completion) {
        self.completion(@[]);
        self.completion = nil;
    }
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}

#pragma mark - NSTableView

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return self.items.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableView;
    if (row < 0 || row >= self.items.count) return nil;
    CXImportPreviewItem *item = self.items[row];

    NSString *identifier = tableColumn.identifier;
    if ([identifier isEqualToString:@"select"]) {
        NSButton *checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleRow:)];
        checkbox.tag = row;
        checkbox.state = item.selected ? NSControlStateValueOn : NSControlStateValueOff;
        checkbox.enabled = !item.disabled;
        return checkbox;
    }

    NSTextField *label = [NSTextField labelWithString:@""];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.font = [NSFont systemFontOfSize:12];

    if ([identifier isEqualToString:@"name"]) {
        label.stringValue = item.candidate.name ?: @"";
    } else if ([identifier isEqualToString:@"url"]) {
        label.stringValue = item.candidate.baseURL ?: @"";
        label.textColor = [NSColor secondaryLabelColor];
    } else if ([identifier isEqualToString:@"status"]) {
        label.stringValue = item.statusText ?: @"";
        if (item.duplicate) {
            label.textColor = [NSColor systemOrangeColor];
        } else if ([item.statusText containsString:@"缺少"]) {
            label.textColor = [NSColor systemRedColor];
        } else {
            label.textColor = [NSColor tertiaryLabelColor];
        }
    }

    return label;
}

- (void)toggleRow:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= self.items.count) return;
    CXImportPreviewItem *item = self.items[row];
    if (item.disabled) return;

    item.selected = sender.state == NSControlStateValueOn;
    [self updateSummary];
}

@end
