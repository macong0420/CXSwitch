//
//  CXProfileListViewController.m
//  CXSwitch
//
//  Created by Claude on 2026/1/10.
//

#import "CXProfileListViewController.h"
#import "CXProfileManager.h"
#import "CXConfigManager.h"
#import "CXKeychainManager.h"
#import "CXLocalConfigImporter.h"
#import "CXImportPreviewWindowController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface CXProfileListViewController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>

@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;

@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) NSButton *refreshButton;
@property (nonatomic, strong) NSButton *exportButton;
@property (nonatomic, strong) NSButton *importButton;

@property (nonatomic, strong) NSArray<CXProfile *> *filteredProfiles;
@property (nonatomic, copy) NSString *searchText;

@end

@implementation CXProfileListViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    [self refresh];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(profileDidChange:) 
                                                 name:CXProfileDidChangeNotification 
                                               object:nil];
}

- (void)setupUI {
    // 工具栏
    NSStackView *toolbar = [[NSStackView alloc] init];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 12;
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:toolbar];
    
    // 搜索框
    self.searchField = [[NSSearchField alloc] init];
    self.searchField.placeholderString = @"搜索 Profile...";
    self.searchField.delegate = self;
    self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchField.widthAnchor constraintEqualToConstant:200].active = YES;
    [toolbar addArrangedSubview:self.searchField];
    
    // 弹性空间
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [toolbar addArrangedSubview:spacer];
    
    // 添加按钮
    self.addButton = [NSButton buttonWithTitle:@"+ 添加 Profile" target:self action:@selector(addProfile:)];
    self.addButton.bezelStyle = NSBezelStyleRounded;
    [toolbar addArrangedSubview:self.addButton];
    
    // 刷新按钮
    self.refreshButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:nil] 
                                            target:self 
                                            action:@selector(refresh)];
    self.refreshButton.bezelStyle = NSBezelStyleRounded;
    [toolbar addArrangedSubview:self.refreshButton];
    
    // 导出按钮
    self.exportButton = [NSButton buttonWithTitle:@"导出" target:self action:@selector(exportProfiles:)];
    self.exportButton.bezelStyle = NSBezelStyleRounded;
    [toolbar addArrangedSubview:self.exportButton];

    // 导入按钮
    self.importButton = [NSButton buttonWithTitle:@"导入" target:self action:@selector(importFromLocal:)];
    self.importButton.bezelStyle = NSBezelStyleRounded;
    [toolbar addArrangedSubview:self.importButton];
    
    // 表格
    self.scrollView = [[NSScrollView alloc] init];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSBezelBorder;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    
    self.tableView = [[NSTableView alloc] init];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 50;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.target = self;
    self.tableView.doubleAction = @selector(handleTableDoubleClick:);
    
    // 列定义
    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"名称";
    nameColumn.width = 200;
    [self.tableView addTableColumn:nameColumn];
    
    NSTableColumn *urlColumn = [[NSTableColumn alloc] initWithIdentifier:@"url"];
    urlColumn.title = @"Base URL";
    urlColumn.width = 300;
    [self.tableView addTableColumn:urlColumn];
    
    NSTableColumn *lastUsedColumn = [[NSTableColumn alloc] initWithIdentifier:@"lastUsed"];
    lastUsedColumn.title = @"最后使用";
    lastUsedColumn.width = 120;
    [self.tableView addTableColumn:lastUsedColumn];
    
    NSTableColumn *actionsColumn = [[NSTableColumn alloc] initWithIdentifier:@"actions"];
    actionsColumn.title = @"操作";
    actionsColumn.width = 150;
    [self.tableView addTableColumn:actionsColumn];
    
    self.scrollView.documentView = self.tableView;
    
    // 布局
    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:16],
        [toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        
        [self.scrollView.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor constant:16],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16]
    ]];
}

#pragma mark - Refresh

- (void)refresh {
    [self filterProfiles];
    [self.tableView reloadData];
}

- (void)filterProfiles {
    NSArray<CXProfile *> *allProfiles = [CXProfileManager sharedManager].allProfiles;
    
    if (self.searchText.length == 0) {
        self.filteredProfiles = allProfiles;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR baseURL CONTAINS[cd] %@", 
                                  self.searchText, self.searchText];
        self.filteredProfiles = [allProfiles filteredArrayUsingPredicate:predicate];
    }
}

#pragma mark - Actions

- (void)addProfile:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"添加新 Profile";
    alert.informativeText = @"请输入 Profile 信息";
    
    // 创建输入视图
    NSStackView *inputView = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 300, 132)];
    inputView.orientation = NSUserInterfaceLayoutOrientationVertical;
    inputView.spacing = 8;
    
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    nameField.placeholderString = @"名称";
    
    NSTextField *urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    urlField.placeholderString = @"Base URL (例如: https://api.openai.com/v1)";

    NSTextField *modelField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    modelField.placeholderString = @"Model（可选，留空则使用默认 gpt-5.2）";

    NSSecureTextField *keyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    keyField.placeholderString = @"API Key";
    
    [inputView addArrangedSubview:nameField];
    [inputView addArrangedSubview:urlField];
    [inputView addArrangedSubview:modelField];
    [inputView addArrangedSubview:keyField];
    
    alert.accessoryView = inputView;
    [alert addButtonWithTitle:@"添加"];
    [alert addButtonWithTitle:@"取消"];
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        NSString *name = nameField.stringValue;
        NSString *url = urlField.stringValue;
        NSString *model = modelField.stringValue;
        NSString *key = keyField.stringValue;
        
        if (name.length == 0 || url.length == 0 || key.length == 0) {
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = @"输入不完整";
            errorAlert.informativeText = @"请填写所有字段";
            [errorAlert runModal];
            return;
        }
        
        NSError *error = nil;
        CXProfile *profile = [[CXProfileManager sharedManager] addProfileWithName:name
                                                                          baseURL:url
                                                                            model:model
                                                                           apiKey:key
                                                                            error:&error];
        if (profile) {
            [self refresh];
        } else {
            NSAlert *errorAlert = [[NSAlert alloc] init];
            errorAlert.messageText = @"添加失败";
            errorAlert.informativeText = error.localizedDescription;
            [errorAlert runModal];
        }
    }
}

- (void)exportProfiles:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"json"]];
    panel.nameFieldStringValue = @"profiles_export.json";
    
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSData *data = [[CXProfileManager sharedManager] exportProfilesIncludeKeys:NO];
            if (data) {
                [data writeToURL:panel.URL atomically:YES];
            }
        }
    }];
}

- (void)importFromLocal:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.message = @"选择 .env 文件、~/.codex 目录，或 codex_switch.sh（仅支持 Codex）";
    panel.prompt = @"导入";
    panel.directoryURL = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@".codex"]];

    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;

        NSMutableArray<CXLocalConfigImportCandidate *> *allCandidates = [NSMutableArray array];
        for (NSURL *url in panel.URLs) {
            NSArray<CXLocalConfigImportCandidate *> *candidates = [CXLocalConfigImporter candidatesFromPath:url.path];
            if (candidates.count > 0) {
                [allCandidates addObjectsFromArray:candidates];
            }
        }

        if (allCandidates.count == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"未发现可导入的配置";
            alert.informativeText = @"请确认选择的是 .env 文件、~/.codex 目录（含 config_*.toml），或 codex_switch.sh。";
            [alert runModal];
            return;
        }

        [CXImportPreviewWindowController beginSheetForWindow:self.view.window
                                                 candidates:allCandidates
                                            existingProfiles:[CXProfileManager sharedManager].allProfiles
                                                 completion:^(NSArray<CXLocalConfigImportCandidate *> *selectedCandidates) {
            if (selectedCandidates.count == 0) return;
            [self importCandidates:selectedCandidates];
        }];
    }];
}

- (void)importCandidates:(NSArray<CXLocalConfigImportCandidate *> *)candidates {
    NSInteger imported = 0;
    NSInteger skipped = 0;

    for (CXLocalConfigImportCandidate *c in candidates) {
        NSString *baseURL = c.baseURL ?: @"";
        NSString *apiKey = c.apiKey;
        NSString *model = c.model;

        // 必须有 baseURL；如果缺失则跳过
        if (baseURL.length == 0) {
            skipped += 1;
            continue;
        }

        // 允许导入时补填 apiKey
        if (apiKey.length == 0) {
            apiKey = [self promptForAPIKeyWithName:c.name baseURL:baseURL];
            if (apiKey.length == 0) {
                skipped += 1;
                continue;
            }
        }

        NSError *error = nil;
        NSString *name = c.name.length > 0 ? c.name : @"导入 Profile";
        CXProfile *profile = [[CXProfileManager sharedManager] addProfileWithName:name
                                                                          baseURL:baseURL
                                                                            model:model
                                                                           apiKey:apiKey
                                                                            error:&error];
        if (!profile) {
            skipped += 1;
            continue;
        }

        if (c.httpHeaders.count > 0 || c.requiresOpenAIAuth) {
            profile.httpHeaders = c.httpHeaders;
            profile.requiresOpenAIAuth = c.requiresOpenAIAuth;
            [[CXProfileManager sharedManager] updateProfile:profile apiKey:nil error:nil];
        }

        if (c.notes.length > 0) {
            profile.notes = c.notes;
            [[CXProfileManager sharedManager] updateProfile:profile apiKey:nil error:nil];
        }

        imported += 1;
    }

    [self refresh];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"导入完成";
    alert.informativeText = [NSString stringWithFormat:@"成功导入 %ld 个，跳过 %ld 个。", (long)imported, (long)skipped];
    [alert runModal];
}

- (nullable NSString *)promptForAPIKeyWithName:(NSString *)name baseURL:(NSString *)baseURL {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"需要 API Key";
    alert.informativeText = [NSString stringWithFormat:@"为“%@”输入 API Key（Base URL: %@）", name ?: @"导入项", baseURL ?: @""];

    NSSecureTextField *keyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    keyField.placeholderString = @"OPENAI_API_KEY";
    alert.accessoryView = keyField;

    [alert addButtonWithTitle:@"导入"];
    [alert addButtonWithTitle:@"跳过"];

    NSModalResponse r = [alert runModal];
    if (r != NSAlertFirstButtonReturn) return nil;

    NSString *normalized = [CXKeychainManager normalizedAPIKeyFromUserInput:keyField.stringValue];
    if (normalized.length == 0) {
        NSAlert *bad = [[NSAlert alloc] init];
        bad.messageText = @"API Key 无效";
        bad.informativeText = @"请确认只粘贴 key 本身（不要包含空格/换行/论坛引用等多余内容）。";
        [bad runModal];
        return nil;
    }
    return normalized;
}

#pragma mark - NSSearchFieldDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.searchField) {
        self.searchText = self.searchField.stringValue;
        [self refresh];
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.filteredProfiles.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row >= self.filteredProfiles.count) return nil;
    
    CXProfile *profile = self.filteredProfiles[row];
    NSString *identifier = tableColumn.identifier;
    
    if ([identifier isEqualToString:@"name"]) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"NameCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = @"NameCell";
            cell.wantsLayer = YES;
            cell.layer.cornerRadius = 4;
            
            NSStackView *stack = [[NSStackView alloc] init];
            stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            stack.spacing = 10;
            stack.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:stack];
            
            NSButton *iconButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"circle" accessibilityDescription:nil]
                                                     target:self
                                                     action:@selector(switchToProfile:)];
            iconButton.bordered = NO;
            iconButton.toolTip = @"切换到此 Profile";
            iconButton.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightMedium];
            iconButton.contentTintColor = [NSColor secondaryLabelColor];
            iconButton.tag = row;
            iconButton.translatesAutoresizingMaskIntoConstraints = NO;
            [stack addArrangedSubview:iconButton];
            
            NSTextField *textField = [NSTextField labelWithString:@""];
            [stack addArrangedSubview:textField];
            cell.textField = textField;
            
            [NSLayoutConstraint activateConstraints:@[
                [stack.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
                [stack.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [stack.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        
        NSStackView *stack = cell.subviews.firstObject;
        if ([stack isKindOfClass:[NSStackView class]]) {
            NSButton *iconButton = nil;
            if (stack.arrangedSubviews.count > 0 && [stack.arrangedSubviews.firstObject isKindOfClass:[NSButton class]]) {
                iconButton = (NSButton *)stack.arrangedSubviews.firstObject;
                iconButton.tag = row;
            }
            
            if (profile.isActive) {
                // 激活状态：醒目的绿色背景和边框
                cell.layer.backgroundColor = [[NSColor systemGreenColor] colorWithAlphaComponent:0.12].CGColor;
                cell.layer.borderColor = [NSColor systemGreenColor].CGColor;
                cell.layer.borderWidth = 1.5;
                
                iconButton.image = [NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:nil];
                iconButton.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:18 weight:NSFontWeightBold];
                iconButton.contentTintColor = [NSColor systemGreenColor];
                cell.textField.textColor = [NSColor systemGreenColor];
                cell.textField.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
                cell.textField.stringValue = [NSString stringWithFormat:@"%@  (当前激活)", profile.name];
            } else {
                // 未激活状态：普通外观
                cell.layer.backgroundColor = [NSColor clearColor].CGColor;
                cell.layer.borderColor = [NSColor clearColor].CGColor;
                cell.layer.borderWidth = 0;
                
                iconButton.image = [NSImage imageWithSystemSymbolName:@"circle" accessibilityDescription:nil];
                iconButton.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightRegular];
                iconButton.contentTintColor = [NSColor tertiaryLabelColor];
                cell.textField.textColor = [NSColor labelColor];
                cell.textField.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
                cell.textField.stringValue = profile.name;
            }
        }
        
        return cell;
    }
    
    if ([identifier isEqualToString:@"url"]) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"URLCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = @"URLCell";
            
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.lineBreakMode = NSLineBreakByTruncatingMiddle;
            textField.textColor = [NSColor secondaryLabelColor];
            textField.font = [NSFont systemFontOfSize:11];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:textField];
            cell.textField = textField;
            
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        
        cell.textField.stringValue = profile.baseURL ?: @"-";
        return cell;
    }
    
    if ([identifier isEqualToString:@"lastUsed"]) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"LastUsedCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = @"LastUsedCell";
            
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.textColor = [NSColor tertiaryLabelColor];
            textField.font = [NSFont systemFontOfSize:11];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:textField];
            cell.textField = textField;
            
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        
        if (profile.lastUsedAt) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyy/M/d HH:mm";
            cell.textField.stringValue = [formatter stringFromDate:profile.lastUsedAt];
        } else {
            cell.textField.stringValue = @"-";
        }
        
        return cell;
    }
    
    if ([identifier isEqualToString:@"actions"]) {
        NSTableCellView *cell = [tableView makeViewWithIdentifier:@"ActionsCell" owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = @"ActionsCell";
            
            NSStackView *stack = [[NSStackView alloc] init];
            stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            stack.spacing = 4;
            stack.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:stack];
            
            // 切换按钮
            NSButton *switchBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.triangle.2.circlepath" accessibilityDescription:nil] 
                                                     target:self 
                                                     action:@selector(switchToProfile:)];
            switchBtn.bezelStyle = NSBezelStyleInline;
            switchBtn.tag = row;
            [stack addArrangedSubview:switchBtn];
            
            // 编辑按钮
            NSButton *editBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"pencil" accessibilityDescription:nil] 
                                                   target:self 
                                                   action:@selector(editProfile:)];
            editBtn.bezelStyle = NSBezelStyleInline;
            editBtn.tag = row;
            [stack addArrangedSubview:editBtn];
            
            // 删除按钮
            NSButton *deleteBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:nil] 
                                                     target:self 
                                                     action:@selector(deleteProfile:)];
            deleteBtn.bezelStyle = NSBezelStyleInline;
            deleteBtn.contentTintColor = [NSColor systemRedColor];
            deleteBtn.tag = row;
            [stack addArrangedSubview:deleteBtn];
            
            [NSLayoutConstraint activateConstraints:@[
                [stack.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
                [stack.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        
        // 更新按钮 tag
        for (NSView *subview in cell.subviews) {
            if ([subview isKindOfClass:[NSStackView class]]) {
                for (NSView *btn in [(NSStackView *)subview arrangedSubviews]) {
                    if ([btn isKindOfClass:[NSButton class]]) {
                        [(NSButton *)btn setTag:row];
                    }
                }
            }
        }
        
        return cell;
    }
    
    return nil;
}

#pragma mark - Row Actions

- (void)switchToProfile:(NSButton *)sender {
    [self switchToProfileAtRow:sender.tag];
}

- (void)switchToProfileAtRow:(NSInteger)row {
    if (row < 0 || row >= self.filteredProfiles.count) return;

    CXProfile *profile = self.filteredProfiles[row];

    NSError *error = nil;
    NSString *apiKey = [[CXKeychainManager sharedManager] getAPIKeyForProfileId:profile.profileId error:&error];
    if (!apiKey) {
        NSString *entered = [self promptForAPIKeyWithName:profile.name baseURL:profile.baseURL];
        if (entered.length == 0) return;

        if (![[CXProfileManager sharedManager] updateProfile:profile apiKey:entered error:&error]) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"无法保存 API Key";
            alert.informativeText = error.localizedDescription ?: @"未知错误";
            [alert runModal];
            return;
        }
        apiKey = entered;
    }

    BOOL success = [[CXConfigManager sharedManager] applyProfile:profile apiKey:apiKey error:&error];
    if (success) {
        [[CXProfileManager sharedManager] activateProfile:profile error:nil];
        [self refresh];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"切换失败";
    alert.informativeText = error.localizedDescription ?: @"未知错误";
    [alert runModal];
}

- (void)handleTableDoubleClick:(id)sender {
    (void)sender;
    NSInteger row = self.tableView.clickedRow;
    if (row < 0) return;
    [self switchToProfileAtRow:row];
}

- (void)editProfile:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row >= 0 && row < self.filteredProfiles.count) {
        CXProfile *profile = self.filteredProfiles[row];
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"编辑 Profile";
        
        NSStackView *inputView = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 300, 132)];
        inputView.orientation = NSUserInterfaceLayoutOrientationVertical;
        inputView.spacing = 8;
        
        NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        nameField.stringValue = profile.name;
        
        NSTextField *urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        urlField.stringValue = profile.baseURL;

        NSTextField *modelField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        modelField.placeholderString = @"Model（可选，留空则使用默认 gpt-5.2）";
        modelField.stringValue = profile.model ?: @"";
        
        NSSecureTextField *keyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        keyField.placeholderString = @"新 API Key（留空则不修改）";
        
        [inputView addArrangedSubview:nameField];
        [inputView addArrangedSubview:urlField];
        [inputView addArrangedSubview:modelField];
        [inputView addArrangedSubview:keyField];
        
        alert.accessoryView = inputView;
        [alert addButtonWithTitle:@"保存"];
        [alert addButtonWithTitle:@"取消"];
        
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            profile.name = nameField.stringValue;
            profile.baseURL = [CXProfile normalizeBaseURL:urlField.stringValue];
            NSString *enteredModel = [modelField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            profile.model = enteredModel.length > 0 ? enteredModel : nil;
            
            NSString *newKey = keyField.stringValue.length > 0 ? keyField.stringValue : nil;
            
            NSError *error = nil;
            BOOL success = [[CXProfileManager sharedManager] updateProfile:profile 
                                                                    apiKey:newKey 
                                                                     error:&error];
            if (success) {
                [self refresh];
            } else {
                NSAlert *errorAlert = [[NSAlert alloc] init];
                errorAlert.messageText = @"保存失败";
                errorAlert.informativeText = error.localizedDescription;
                [errorAlert runModal];
            }
        }
    }
}

- (void)deleteProfile:(NSButton *)sender {
    NSInteger row = sender.tag;
    if (row >= 0 && row < self.filteredProfiles.count) {
        CXProfile *profile = self.filteredProfiles[row];
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"确认删除";
        alert.informativeText = [NSString stringWithFormat:@"是否删除 Profile \"%@\"？此操作不可撤销。", profile.name];
        [alert addButtonWithTitle:@"删除"];
        [alert addButtonWithTitle:@"取消"];
        alert.alertStyle = NSAlertStyleWarning;
        
        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            NSError *error = nil;
            BOOL success = [[CXProfileManager sharedManager] deleteProfile:profile error:&error];
            if (success) {
                [self refresh];
            } else {
                NSAlert *errorAlert = [[NSAlert alloc] init];
                errorAlert.messageText = @"删除失败";
                errorAlert.informativeText = error.localizedDescription;
                [errorAlert runModal];
            }
        }
    }
}

#pragma mark - Notifications

- (void)profileDidChange:(NSNotification *)notification {
    [self refresh];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
