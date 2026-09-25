//
//  Document.h
//  Table Tool
//
//  Created by Andreas Aigner on 06.07.15.
//  Copyright (c) 2015 Egger Apps. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "CSVConfiguration.h"
#import "TTFormatViewController.h"

@interface Document : NSDocument <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate, TTFormatViewControllerDelegate>

@property NSMutableArray *data;
@property long maxColumnNumber;
@property CSVConfiguration *csvConfig;

@property IBOutlet NSTableView *tableView;
@property IBOutlet NSSplitView *splitView;
@property (strong) IBOutlet NSButton *toolBarButtonDeleteColumn;
@property (strong) IBOutlet NSSegmentedControl *toolBarButtonsAddColumn;
@property (strong) IBOutlet NSSegmentedControl *toolBarButtonsAddRow;
@property (strong) IBOutlet NSToolbarItem *toolbarItemAddColumn;
@property (strong) IBOutlet NSToolbarItem *toolbarItemAddRow;
@property (strong) IBOutlet NSButton *toolBarButtonDeleteRow;
@property (strong) IBOutlet NSToolbarItem *toolbarItemDeleteColumn;
@property (strong) IBOutlet NSToolbarItem *toolbarItemDeleteRow;
@property (strong) IBOutlet NSToolbarItem *toolbarItemSearch;

-(IBAction)addColumn:(id)sender;
-(IBAction)addRow:(id)sender;
-(void)addRowAbove:(id)sender;
-(void)addRowBelow:(id)sender;
-(void)addColumnLeft:(id)sender;
-(void)addColumnRight:(id)sender;
-(IBAction)deleteRow:(id)sender;
-(IBAction)deleteColumn:(id)sender;
-(IBAction)exportFile:(id)sender;
-(IBAction)find:(id)sender;
-(IBAction)findNext:(id)sender;
-(IBAction)findPrevious:(id)sender;
-(IBAction)changeCSVEncoding:(NSMenuItem *)sender;
-(IBAction)changeCSVSeparator:(NSMenuItem *)sender;
-(IBAction)changeCSVDecimalMark:(NSMenuItem *)sender;
-(IBAction)changeCSVQuoteStyle:(NSMenuItem *)sender;
-(IBAction)toggleCSVHeader:(id)sender;
-(NSArray<NSTableColumn *> *)filterableColumns;
-(NSArray<NSString *> *)filterValuesForColumnIdentifier:(NSString *)identifier;
-(BOOL)isFilterValueIncluded:(NSString *)value forColumnIdentifier:(NSString *)identifier;
-(BOOL)hasActiveFilters;
-(IBAction)toggleColumnFilterValue:(NSMenuItem *)sender;
-(IBAction)clearColumnFilters:(id)sender;
-(IBAction)clearFiltersForColumn:(NSMenuItem *)sender;
-(void)addFilterValueItemsForColumn:(NSTableColumn *)column toMenu:(NSMenu *)menu;

-(void)configurationChangedForFormatViewController:(TTFormatViewController *)formatViewController;

@end
