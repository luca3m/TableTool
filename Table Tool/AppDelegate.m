//
//  AppDelegate.m
//  Table Tool
//
//  Created by Andreas Aigner on 06.07.15.
//  Copyright (c) 2015 Egger Apps. All rights reserved.
//

#import "AppDelegate.h"
#import "CSVConfiguration.h"
#import "Document.h"

@interface AppDelegate () <NSMenuDelegate>

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSMenu *editMenu = [[NSApp.mainMenu itemWithTitle:@"Edit"] submenu];
    [editMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *formatItem = [[NSMenuItem alloc] initWithTitle:@"CSV Format" action:NULL keyEquivalent:@""];
    NSMenu *formatMenu = [[NSMenu alloc] initWithTitle:@"CSV Format"];
    formatItem.submenu = formatMenu;
    [editMenu addItem:formatItem];

    NSMenu *encodingMenu = [[NSMenu alloc] initWithTitle:@"Encoding"];
    for (NSArray *encoding in [CSVConfiguration supportedEncodings]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:encoding[0] action:@selector(changeCSVEncoding:) keyEquivalent:@""];
        item.tag = [encoding[1] integerValue];
        [encodingMenu addItem:item];
    }
    [self addSubmenu:encodingMenu toMenu:formatMenu];

    NSMenu *separatorMenu = [[NSMenu alloc] initWithTitle:@"Separator"];
    NSArray<NSString *> *separatorTitles = @[@"Comma (,)", @"Semicolon (;)", @"Tab", @"Pipe (|)"];
    for (NSInteger index = 0; index < separatorTitles.count; index++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:separatorTitles[index] action:@selector(changeCSVSeparator:) keyEquivalent:@""];
        item.tag = index;
        [separatorMenu addItem:item];
    }
    [self addSubmenu:separatorMenu toMenu:formatMenu];

    NSMenu *decimalMenu = [[NSMenu alloc] initWithTitle:@"Decimal Mark"];
    for (NSInteger index = 0; index < 2; index++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:index == 0 ? @"Period (.)" : @"Comma (,)" action:@selector(changeCSVDecimalMark:) keyEquivalent:@""];
        item.tag = index;
        [decimalMenu addItem:item];
    }
    [self addSubmenu:decimalMenu toMenu:formatMenu];

    NSMenu *quoteMenu = [[NSMenu alloc] initWithTitle:@"Quote and Escape"];
    NSArray<NSString *> *quoteTitles = @[@"Double quote (\"\")", @"Backslash (\\\")", @"None"];
    for (NSInteger index = 0; index < quoteTitles.count; index++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:quoteTitles[index] action:@selector(changeCSVQuoteStyle:) keyEquivalent:@""];
        item.tag = index;
        [quoteMenu addItem:item];
    }
    [self addSubmenu:quoteMenu toMenu:formatMenu];

    [formatMenu addItem:[NSMenuItem separatorItem]];
    [formatMenu addItem:[[NSMenuItem alloc] initWithTitle:@"First Row as Header" action:@selector(toggleCSVHeader:) keyEquivalent:@""]];

    NSMenu *filterMenu = [[NSMenu alloc] initWithTitle:@"Filter Rows"];
    filterMenu.delegate = self;
    [self addSubmenu:filterMenu toMenu:editMenu];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    Document *document = (Document *)NSDocumentController.sharedDocumentController.currentDocument;
    if (![document isKindOfClass:[Document class]]) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:@"Open a document to filter rows" action:NULL keyEquivalent:@""];
        emptyItem.enabled = NO;
        [menu addItem:emptyItem];
        return;
    }

    NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:@"Clear All Filters" action:@selector(clearColumnFilters:) keyEquivalent:@""];
    clearItem.target = document;
    clearItem.enabled = [document hasActiveFilters];
    [menu addItem:clearItem];
    [menu addItem:[NSMenuItem separatorItem]];

    NSArray<NSTableColumn *> *columns = [document filterableColumns];
    if (columns.count == 0) {
        NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:@"No columns with 2–20 values" action:NULL keyEquivalent:@""];
        emptyItem.enabled = NO;
        [menu addItem:emptyItem];
    }
    for (NSTableColumn *column in columns) {
        NSMenu *valuesMenu = [[NSMenu alloc] initWithTitle:column.headerCell.stringValue];
        [document addFilterValueItemsForColumn:column toMenu:valuesMenu];
        [self addSubmenu:valuesMenu toMenu:menu];
    }
}

- (void)addSubmenu:(NSMenu *)submenu toMenu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:submenu.title action:NULL keyEquivalent:@""];
    item.submenu = submenu;
    [menu addItem:item];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

@end
