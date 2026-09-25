//
//  Document.m
//  Table Tool
//
//  Created by Andreas Aigner on 06.07.15.
//  Copyright (c) 2015 Egger Apps. All rights reserved.
//

#import "Constants.h"
#import "Document.h"
#import "CSVReader.h"
#import "CSVWriter.h"
#import "CSVHeuristic.h"
#import "TTErrorViewController.h"
#import "ToolbarIcons.h"
#import <math.h>

@interface Document () {
    NSCell *dataCell;
    NSData *savedData;
    NSArray *columnNames;
    
    NSError *readingError;
    NSView *errorControllerView;
    NSString *errorCode5;
    
    BOOL ignoreColumnDidMoveNotifications;
    BOOL newFile;
    BOOL enableEditing;
    
    NSArray *validPBoardTypes;
    
    TTErrorViewController *errorController;
    TTFormatViewController* accessoryViewController;
    NSSearchField *searchField;
    NSTextField *searchResultLabel;
    NSMutableArray<NSValue *> *searchMatches;
    NSInteger searchMatchIndex;
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *excludedFilterValues;
    NSArray<NSNumber *> *visibleRows;
}
@property BOOL didSave;

@end

@implementation Document 

- (instancetype)init {
    self = [super init];
    if (self) {
        _data = [[NSMutableArray alloc]init];
        _maxColumnNumber = 1;
        _csvConfig = [[CSVConfiguration alloc]init];
        excludedFilterValues = [NSMutableDictionary dictionary];
        newFile = YES;
        errorCode5 = @"Your are not allowed to save while the input format has an error. Configure the format manually, until no error occurs.";
        _didSave = NO;
        
        [self initValidPBoardTypes];
        
    }
    return self;
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController {
    [super windowControllerDidLoadNib:aController];
    dataCell = [self.tableView.tableColumns.firstObject dataCell];
    [self updateTableColumns];
    
    [self.tableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    [self.tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
    [self.tableView registerForDraggedTypes:[NSArray arrayWithObject:TTRowInternalPboardType]];
    
    if(newFile){
        _maxColumnNumber = 3;
        [self updateTableColumns];
        [_data addObject:[[NSMutableArray alloc]init]];
        [self.tableView reloadData];
    }
    
    [self enableToolbarButtons];
    
    if(readingError) dispatch_async(dispatch_get_main_queue(), ^{
        [self displayError:readingError];
    });
    
    [self updateToolbarIcons];
    [self configureDocumentAppearance];
    [self installToolbarSearch];
    [self installHeaderFilterMenu];

}

- (void)configureDocumentAppearance {
    NSWindow *window = self.tableView.window;
    window.titlebarAppearsTransparent = YES;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    window.minSize = NSMakeSize(560, 320);
    self.tableView.backgroundColor = NSColor.textBackgroundColor;
    self.tableView.gridColor = NSColor.separatorColor;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.rowHeight = 25;
    self.tableView.enclosingScrollView.drawsBackground = YES;
    self.tableView.enclosingScrollView.backgroundColor = NSColor.textBackgroundColor;
    dataCell.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    [(NSTextFieldCell *)dataCell setBackgroundColor:NSColor.textBackgroundColor];
    [(NSTextFieldCell *)dataCell setDrawsBackground:NO];
}

- (void)installToolbarSearch {
    NSView *container = self.toolbarItemSearch.view;
    searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    searchField.translatesAutoresizingMaskIntoConstraints = NO;
    searchField.placeholderString = @"Search values";
    searchField.toolTip = @"Search cell values (⌘F)";
    searchField.delegate = self;
    [container addSubview:searchField];

    searchResultLabel = [NSTextField labelWithString:@""];
    searchResultLabel.translatesAutoresizingMaskIntoConstraints = NO;
    searchResultLabel.textColor = NSColor.secondaryLabelColor;
    searchResultLabel.alignment = NSTextAlignmentRight;
    searchResultLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    searchResultLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [container addSubview:searchResultLabel];

    NSButton *previous = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:@"Previous match"] target:self action:@selector(findPrevious:)];
    NSButton *next = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Next match"] target:self action:@selector(findNext:)];
    previous.translatesAutoresizingMaskIntoConstraints = NO;
    next.translatesAutoresizingMaskIntoConstraints = NO;
    previous.bezelStyle = NSBezelStyleTexturedRounded;
    next.bezelStyle = NSBezelStyleTexturedRounded;
    previous.toolTip = @"Previous match (⇧⌘G)";
    next.toolTip = @"Next match (⌘G)";
    [container addSubview:previous];
    [container addSubview:next];

    [NSLayoutConstraint activateConstraints:@[
        [searchField.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [searchField.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [searchField.widthAnchor constraintEqualToConstant:175],
        [searchResultLabel.leadingAnchor constraintEqualToAnchor:searchField.trailingAnchor constant:8],
        [searchResultLabel.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [searchResultLabel.widthAnchor constraintEqualToConstant:90],
        [previous.leadingAnchor constraintEqualToAnchor:searchResultLabel.trailingAnchor constant:4],
        [previous.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [previous.widthAnchor constraintEqualToConstant:24],
        [next.leadingAnchor constraintEqualToAnchor:previous.trailingAnchor constant:4],
        [next.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [next.widthAnchor constraintEqualToConstant:24],
        [next.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor]
    ]];
    searchMatches = [NSMutableArray array];
    searchMatchIndex = NSNotFound;
}

- (void)installHeaderFilterMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Filter Column"];
    menu.delegate = self;
    self.tableView.headerView.menu = menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSEvent *event = NSApp.currentEvent;
    NSTableHeaderView *header = self.tableView.headerView;
    NSInteger columnIndex = -1;
    if (event.window == self.tableView.window) {
        columnIndex = [header columnAtPoint:[header convertPoint:event.locationInWindow fromView:nil]];
    }
    if (columnIndex < 0 || columnIndex >= self.tableView.numberOfColumns) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No column selected" action:NULL keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
        return;
    }

    NSTableColumn *column = self.tableView.tableColumns[columnIndex];
    NSArray<NSString *> *values = [self filterValuesForColumnIdentifier:column.identifier];
    if (values.count >= 2 && values.count <= 20) {
        [self addFilterValueItemsForColumn:column toMenu:menu];
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *clearColumn = [[NSMenuItem alloc] initWithTitle:@"Show All Values in This Column" action:@selector(clearFiltersForColumn:) keyEquivalent:@""];
        clearColumn.target = self;
        clearColumn.representedObject = column.identifier;
        clearColumn.enabled = excludedFilterValues[column.identifier].count > 0;
        [menu addItem:clearColumn];
    } else {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"Filtering requires 2–20 distinct values" action:NULL keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
    }
    NSMenuItem *clearAll = [[NSMenuItem alloc] initWithTitle:@"Clear All Filters" action:@selector(clearColumnFilters:) keyEquivalent:@""];
    clearAll.target = self;
    clearAll.enabled = [self hasActiveFilters];
    [menu addItem:clearAll];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == searchField) [self updateSearchMatches];
}

- (void)updateSearchMatches {
    if (!searchField || !self.tableView) return;
    [searchMatches removeAllObjects];
    NSString *query = searchField.stringValue;
    if (query.length > 0) {
        for (NSInteger row = 0; row < [self numberOfRowsInTableView:self.tableView]; row++) {
            for (NSInteger column = 0; column < self.tableView.numberOfColumns; column++) {
                id value = [self tableView:self.tableView objectValueForTableColumn:self.tableView.tableColumns[column] row:row];
                NSString *displayValue = [value description];
                if (displayValue.length > 0 && [displayValue rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [searchMatches addObject:[NSValue valueWithPoint:NSMakePoint(column, row)]];
                }
            }
        }
    }
    searchMatchIndex = searchMatches.count > 0 ? 0 : NSNotFound;
    [self showCurrentSearchMatch];
    [self.tableView reloadData];
}

- (void)showCurrentSearchMatch {
    if (searchField.stringValue.length == 0) {
        searchResultLabel.stringValue = [self hasActiveFilters] ? [NSString stringWithFormat:@"%ld of %ld rows shown", (long)visibleRows.count, (long)_data.count] : @"";
        return;
    }
    if (searchMatchIndex == NSNotFound) {
        searchResultLabel.stringValue = @"No matches";
        return;
    }
    NSPoint match = searchMatches[searchMatchIndex].pointValue;
    NSInteger row = (NSInteger)match.y;
    NSInteger column = (NSInteger)match.x;
    searchResultLabel.stringValue = [NSString stringWithFormat:@"%ld of %ld", (long)searchMatchIndex + 1, (long)searchMatches.count];
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.tableView selectColumnIndexes:[NSIndexSet indexSetWithIndex:column] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:row];
    [self.tableView scrollColumnToVisible:column];
}

- (IBAction)find:(id)sender {
    [self.tableView.window makeFirstResponder:searchField];
    [searchField.currentEditor selectAll:sender];
}

- (IBAction)findNext:(id)sender {
    if (searchMatches.count == 0) return;
    searchMatchIndex = (searchMatchIndex + 1) % searchMatches.count;
    [self showCurrentSearchMatch];
}

- (IBAction)findPrevious:(id)sender {
    if (searchMatches.count == 0) return;
    searchMatchIndex = (searchMatchIndex + searchMatches.count - 1) % searchMatches.count;
    [self showCurrentSearchMatch];
}

- (void)close {
    [super close];
}


+ (BOOL)autosavesInPlace {
    return YES;
}

- (NSString *)windowNibName {
    return @"Document";
}

- (void)updateChangeCountWithToken:(id)changeCountToken forSaveOperation:(NSSaveOperationType)saveOperation {
    if (saveOperation == NSSaveOperation || saveOperation == NSSaveAsOperation ) {
        self.didSave = YES;
    }
    [super updateChangeCountWithToken:changeCountToken forSaveOperation:saveOperation];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
	return [self dataWithCSVConfig:self.csvConfig error:outError];
}

-(NSData*)dataWithCSVConfig:(CSVConfiguration*)config error:(NSError**)outError {
	if(readingError){
		NSError *error = [NSError errorWithDomain:@"at.eggerapps.Table-Tool" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Could not save", NSLocalizedRecoverySuggestionErrorKey:errorCode5}];
		[self displayError:error];
		return nil;
	}
	
	NSArray *exportData = _data;
	
	if(self.csvConfig.firstRowAsHeader){
		NSMutableArray *headerRow = [[NSMutableArray alloc]init];
		for(int i = 0; i < _maxColumnNumber; i++){
			[headerRow addObject:@""];
		}
		for(NSTableColumn * col in self.tableView.tableColumns){
			[headerRow replaceObjectAtIndex:col.identifier.integerValue withObject:col.headerCell.stringValue];
		}
		exportData = [@[headerRow] arrayByAddingObjectsFromArray:exportData];
	}
	
	NSError *error;
	
	CSVWriter *writer = [[CSVWriter alloc] initWithDataArray:exportData columnsOrder:[self getColumnsOrder] configuration:config];
	NSData *finalData = [writer writeDataWithError:&error];
	if(finalData == nil){
		if(error) {
			*outError = error;
			[self displayError:error];
		}
	}
	
	return finalData;
}

-(BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError * _Nullable __autoreleasing *)outError {
    [self.undoManager removeAllActions];
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:outError];
	if (!data) {
		return NO;
	}
	CSVHeuristic *formatHeuristic = [[CSVHeuristic alloc]initWithData:data];
	for (NSString *language in [[NSUserDefaults standardUserDefaults] arrayForKey:@"AppleLanguages"]) {
		if ([language isKindOfClass:[NSString class]] && [language hasPrefix:@"zh"]) {
			formatHeuristic.preferChineseEncoding = YES;
		}
	}
	NSStringEncoding usedEncoding;
	if ([[NSString alloc] initWithContentsOfURL:url usedEncoding:&usedEncoding error:nil]) {
		formatHeuristic.encoding = usedEncoding;
	}
    newFile = NO;
    self.csvConfig = [formatHeuristic calculatePossibleFormat];
    
    savedData = data;
	
	NSError *error = nil;
	if (![self reloadDataWithError:&error]) {
		readingError = error;
		if (dataCell) [self displayError:error];
	}
	
	return YES;
}

-(BOOL)reloadDataWithError:(NSError**)error {
	[self.undoManager removeAllActions];
	[excludedFilterValues removeAllObjects];
	visibleRows = nil;
	
	_maxColumnNumber = 1;
	[_data removeAllObjects];
	
	NSError *outError;
	CSVReader *reader = [[CSVReader alloc ]initWithData:savedData configuration: self.csvConfig];
	columnNames = nil;
	while(!reader.isAtEnd) {
		NSArray *line = [reader readLineWithError:&outError];
		if (!line) {
			if (error) *error = outError;
			[self updateTableColumns];
			[self rebuildVisibleRows];
			return NO;
		}
		_maxColumnNumber = MAX(_maxColumnNumber, line.count);
		if (self.csvConfig.firstRowAsHeader && !columnNames) {
			columnNames = line;
		} else {
			[_data addObject:line];
		}
	}
	
	[self updateTableColumns];
	[self rebuildVisibleRows];
	return YES;
}


-(void)displayError:(NSError *)error {
    
    errorController = [[TTErrorViewController alloc]initWithMessage:error.localizedDescription information:error.localizedRecoverySuggestion];
    
    NSView *errorContainerView = self.tableView.enclosingScrollView.superview;
    if(errorControllerView){
        [errorContainerView replaceSubview:errorControllerView with:errorController.view];
        errorControllerView = errorController.view;
    }else{
        errorControllerView = errorController.view;
        [errorContainerView addSubview:errorControllerView positioned:NSWindowAbove relativeTo:nil];
    }
    
    [errorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:errorController.view attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:errorContainerView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    [errorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:errorController.view attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:errorContainerView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
    [errorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:errorControllerView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationLessThanOrEqual toItem:errorContainerView attribute:NSLayoutAttributeBottom multiplier:1 constant:-20]];
    [errorController.view setWantsLayer:YES];
}

#pragma mark - tableViewDataSource, delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return visibleRows ? visibleRows.count : _data.count;
}

- (NSInteger)modelRowForVisibleRow:(NSInteger)row {
    return visibleRows ? visibleRows[row].integerValue : row;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex {
    rowIndex = [self modelRowForVisibleRow:rowIndex];
    if(_data.count >= rowIndex+1) {
        NSArray *rowArray = _data[rowIndex];
        if(rowArray.count >= tableColumn.identifier.integerValue+1){
            if([rowArray[tableColumn.identifier.integerValue] isKindOfClass:[NSDecimalNumber class]]) {
                return [(NSDecimalNumber *)rowArray[tableColumn.identifier.integerValue] descriptionWithLocale:@{NSLocaleDecimalSeparator:self.csvConfig.decimalMark}];
            }
            return rowArray[tableColumn.identifier.integerValue];
        }
    }
    return nil;
}

-(void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex {
    [self restoreObjectValue:object forTableColumn:tableColumn row:[self modelRowForVisibleRow:rowIndex] reload:NO];
    [self.undoManager setActionName:@"Edit Cell"];
    
}

-(void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex {
    NSInteger modelRow = [self modelRowForVisibleRow:rowIndex];
    if(_data.count <= modelRow) return;
    NSTextFieldCell *textCell = cell;
    BOOL matchesSearch = NO;
    if (searchField.stringValue.length > 0) {
        NSString *value = [[self tableView:tableView objectValueForTableColumn:tableColumn row:rowIndex] description];
        matchesSearch = value.length > 0 && [value rangeOfString:searchField.stringValue options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    textCell.drawsBackground = matchesSearch;
    textCell.backgroundColor = matchesSearch ? [NSColor.controlAccentColor colorWithAlphaComponent:0.20] : NSColor.textBackgroundColor;
    NSArray *rowArray = [_data objectAtIndex:modelRow];
    if(rowArray.count > tableColumn.identifier.integerValue){
        if([rowArray[tableColumn.identifier.integerValue] isKindOfClass:[NSDecimalNumber class]]){
            textCell.alignment = NSRightTextAlignment;
        }else{
            textCell.alignment = NSLeftTextAlignment;
        }
    }
}

-(void)restoreObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex reload:(BOOL)shouldReload {
    
    NSMutableArray *rowArray = _data[rowIndex];
    if([rowArray count] <= tableColumn.identifier.integerValue) {
        for(NSUInteger i = rowArray.count; i <= tableColumn.identifier.integerValue+1; ++i){
            [rowArray addObject:@""];
        }
    }
    
    [[self.undoManager prepareWithInvocationTarget:self] restoreObjectValue:rowArray[tableColumn.identifier.integerValue] forTableColumn:tableColumn row:rowIndex reload:YES];
    
    if(![object isEqualTo:rowArray[tableColumn.identifier.integerValue]]){
        [self dataGotEdited];
    }
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^\\s*[+-]?(\\d+\\%@?\\d*|\\d*\\%@?\\d+)([eE][+-]?\\d+)?\\s*$",self.csvConfig.decimalMark,self.csvConfig.decimalMark] options:0 error:NULL];
    NSString *userInputValue = (NSString *)object;
    if([regex numberOfMatchesInString:userInputValue options:0 range:NSMakeRange(0, [userInputValue length])] == 1){
        rowArray[tableColumn.identifier.integerValue] = [NSDecimalNumber decimalNumberWithString:userInputValue locale:@{NSLocaleDecimalSeparator:self.csvConfig.decimalMark}];
    }else{
        rowArray[tableColumn.identifier.integerValue] = userInputValue;
    }
    
    _data[rowIndex] = rowArray;
    [self rebuildVisibleRows];
    [self resizeColumnToFitContents:tableColumn];
}

-(void)tableViewColumnDidMove:(NSNotification *)aNotification {
    if(!ignoreColumnDidMoveNotifications){
        [self.undoManager setActionName:@"Move Column"];
        NSNumber *oldIndex = [aNotification.userInfo valueForKey:@"NSOldColumn"];
        NSNumber *newIndex = [aNotification.userInfo valueForKey:@"NSNewColumn"];
        [self dataGotEdited];
        [[self.undoManager prepareWithInvocationTarget:self] moveColumnFrom:newIndex.longValue toIndex:oldIndex.longValue];
    }
    [self updateTableColumnsNames];
}

-(NSArray *)getColumnsOrder{
    NSMutableArray *columnsOrder = [[NSMutableArray alloc] init];
    for(NSTableColumn *col in self.tableView.tableColumns) {
        [columnsOrder addObject:col.identifier];
    }
    return columnsOrder.copy;
}

#pragma mark - tableViewDataSource (optional methods) - drag & drop

-(void)initValidPBoardTypes
{
    validPBoardTypes = [NSArray arrayWithObjects:TTRowInternalPboardType,
                                                 NSPasteboardTypeTabularText,
                                                 NSStringPboardType,
                                                 nil];
}

- (BOOL)tableView:(NSTableView *)tableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard *)pboard
{
    if (rowIndexes == nil)
        return NO;
    
    [pboard declareTypes:validPBoardTypes owner: nil];
    
    // TTRowInternalPboardType is used for app internal movement of rows
    NSData *serializedRowIndexes = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
    [pboard setData:serializedRowIndexes forType:TTRowInternalPboardType];

    NSMutableArray *rowDataAtIndexes = [NSMutableArray array];
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        [rowDataAtIndexes addObject:_data[[self modelRowForVisibleRow:index]]];
    }];
    
    // tab-separated text, for supporting drag & drop from Table Tool to table based apps like Numbers or TextEdit
    CSVConfiguration *tabSeparatedCSVConfiguration = [self.csvConfig copy];
    tabSeparatedCSVConfiguration.columnSeparator = @"\t";
    tabSeparatedCSVConfiguration.quoteCharacter = @"";
    CSVWriter *writer = [[CSVWriter alloc] initWithDataArray:rowDataAtIndexes
                                                columnsOrder:[self getColumnsOrder]
                                               configuration:tabSeparatedCSVConfiguration];
    NSString *tabSeparatedCSV = [writer writeString];
    [pboard setString:tabSeparatedCSV forType:NSPasteboardTypeTabularText];
    [pboard setString:tabSeparatedCSV forType:NSPasteboardTypeString];
    
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
    if ([self hasActiveFilters]) return NSDragOperationNone;
    NSPasteboard *pboard = [info draggingPasteboard];
    NSString *type = [pboard availableTypeFromArray:validPBoardTypes];
    if ([type isEqualToString:TTRowInternalPboardType] &&
        [info draggingSource] == self.tableView &&
        tableView == self.tableView)
    { // NOTE: for now, only drag & drop within the same tableView is supported
        switch (dropOperation) {
            case NSTableViewDropAbove: return NSDragOperationMove;
            case NSTableViewDropOn:    return NSDragOperationNone;
        }
    }
    
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)destinationRow
    dropOperation:(NSTableViewDropOperation)dropOperation
{
    NSPasteboard *pboard = [info draggingPasteboard];

    NSString *type = [pboard availableTypeFromArray:validPBoardTypes];
    if ([type isEqualToString:TTRowInternalPboardType]) {
        if ([info draggingSource] == self.tableView &&
            tableView == self.tableView)
        { // NOTE: for now, only drag & drop within the same tableView is supported
            NSData *serializedDraggedRowIndexes = [pboard dataForType:TTRowInternalPboardType];
            NSIndexSet *draggedRowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:serializedDraggedRowIndexes];
            
            return [self moveRowsAtIndexes:draggedRowIndexes toIndex:destinationRow];
        }
    }
    
    return NO;
}

- (void)addRedoStackOperationForMovingRowsAtIndexes:(NSIndexSet *)rowIndexes
                                            toIndex:(NSInteger)row
{
    [[self.undoManager prepareWithInvocationTarget:self] moveRowsAtIndexes:rowIndexes toIndex:row];
	[[self.undoManager prepareWithInvocationTarget:self.tableView] selectRowIndexes:rowIndexes byExtendingSelection:NO];
}

- (void)findLowerDropDestination:(NSInteger *)lowerDropDestination
            upperDropDestination:(NSInteger *)upperDropDestination
            forDraggedRowIndexes:(NSIndexSet *)draggedRowIndexes
               droppedAtLocation:(NSInteger)dropLocation
{
    *lowerDropDestination = dropLocation;
    *upperDropDestination = dropLocation;
    
    BOOL isRowAtDropLocationDragged = [draggedRowIndexes containsIndex:dropLocation];
    BOOL isRowBeforeDropLocationDragged = [draggedRowIndexes containsIndex:dropLocation-1];
    if (isRowAtDropLocationDragged || isRowBeforeDropLocationDragged)
    {
        NSUInteger lastIndex = (isRowAtDropLocationDragged ? dropLocation : dropLocation-1);
        NSUInteger nextIndex = dropLocation;
        while ((nextIndex = [draggedRowIndexes indexGreaterThanIndex:nextIndex]) != NSNotFound) {
            if (nextIndex > lastIndex+1)
                break;
            
            lastIndex = nextIndex;
            *upperDropDestination = nextIndex+1;
        }
        
        nextIndex = dropLocation;
        while ((nextIndex = [draggedRowIndexes indexLessThanIndex:nextIndex]) != NSNotFound) {
            if (nextIndex < (*lowerDropDestination)-1)
                break;
            
            *lowerDropDestination = nextIndex;
        }
    }
}



- (BOOL)moveRowsAtIndexes:(NSIndexSet *)draggedRowIndexes
                  toIndex:(NSInteger)dropLocation
{
    // NOTE: no need to move the destination row to itself, as it lands at the same place anyway
    //       no need also for contiguous multi-selections at and around the destination row
    
    NSInteger lowerDropDestination = dropLocation;
    NSInteger upperDropDestination = dropLocation;
    [self findLowerDropDestination:&lowerDropDestination
              upperDropDestination:&upperDropDestination
              forDraggedRowIndexes:draggedRowIndexes
                 droppedAtLocation:dropLocation];
    
    NSRange rangeOfUnmovedIndexes = NSMakeRange(lowerDropDestination, upperDropDestination-lowerDropDestination+1);

    const NSUInteger draggedRowCount = [draggedRowIndexes count];
    
    NSUInteger countOfRowsBeforeDropLocation = [draggedRowIndexes countOfIndexesInRange:NSMakeRange(0, dropLocation)];
    
    NSInteger destinationRow = dropLocation - countOfRowsBeforeDropLocation;
    
    NSIndexSet *finalIndexesAfterDropping = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(destinationRow, draggedRowCount)];
    
    NSArray *draggedRowData = [_data objectsAtIndexes:draggedRowIndexes];
    
    NSIndexSet *lowerDraggedIndexes;
    if (lowerDropDestination == 0) {
        lowerDraggedIndexes = [NSIndexSet indexSet];
    } else {
        lowerDraggedIndexes = [draggedRowIndexes indexesInRange:NSMakeRange(0, dropLocation-1)
                                                        options:NSEnumerationConcurrent
                                                    passingTest:^BOOL(NSUInteger idx, BOOL * _Nonnull stop) { return YES; }];
    }
    
    NSIndexSet *upperDraggedIndexes = [draggedRowIndexes indexesInRange:NSMakeRange(dropLocation, [_data count])
                                                                       options:NSEnumerationConcurrent
                                                                   passingTest:^BOOL(NSUInteger idx, BOOL * _Nonnull stop) { return YES; }];
    
    if ([lowerDraggedIndexes count] == 0 && [upperDraggedIndexes count] == 0) {
        // NOTE: nothing to do
        return NO;
    }
    
    if (![self.undoManager isUndoing]) {
        [self.undoManager setActionName:(draggedRowCount >= 2) ? @"Move Rows" : @"Move Row"];
    }
	[[self.undoManager prepareWithInvocationTarget:self.tableView] selectRowIndexes:draggedRowIndexes byExtendingSelection:NO];
    [[self.undoManager prepareWithInvocationTarget:self] addRedoStackOperationForMovingRowsAtIndexes:draggedRowIndexes toIndex:dropLocation];
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [self.tableView beginUpdates];
        
        [[self.undoManager prepareWithInvocationTarget:self] dataGotEdited];
        
        [[self.undoManager prepareWithInvocationTarget:NSAnimationContext.self] endGrouping];
        [[self.undoManager prepareWithInvocationTarget:self.tableView] endUpdates];
        
        //
        // update model
        //
        
        [_data removeObjectsAtIndexes:draggedRowIndexes];
        
        NSEnumerator *reverseEnumerator = [draggedRowData reverseObjectEnumerator];
        id nextRowToInsert = nil;
        while (nextRowToInsert = [reverseEnumerator nextObject]) {
            NSUInteger insertionIndex = (dropLocation - countOfRowsBeforeDropLocation);
            [_data insertObject:nextRowToInsert atIndex:insertionIndex];
        }
        
        //
        // update view
        //
        
        NSUInteger draggedIndex = [lowerDraggedIndexes firstIndex];
        NSUInteger numberOfRowsMoved = 0;
        while (draggedIndex != NSNotFound) {
            if (!NSLocationInRange(draggedIndex, rangeOfUnmovedIndexes))
            {
                NSUInteger translatedOldIndex = (draggedIndex - numberOfRowsMoved);
                [self.tableView moveRowAtIndex:translatedOldIndex toIndex:lowerDropDestination-1];
                [[self.undoManager prepareWithInvocationTarget:self.tableView] moveRowAtIndex:lowerDropDestination-1 toIndex:translatedOldIndex];
            }
            
            numberOfRowsMoved++;
            draggedIndex = [lowerDraggedIndexes indexGreaterThanIndex:draggedIndex];
        }
        
        NSUInteger destinationRow = upperDropDestination;
        draggedIndex = [upperDraggedIndexes firstIndex];
        while (draggedIndex != NSNotFound) {
            if (!NSLocationInRange(draggedIndex, rangeOfUnmovedIndexes))
            {
                [self.tableView moveRowAtIndex:draggedIndex toIndex:destinationRow];
                [[self.undoManager prepareWithInvocationTarget:self.tableView] moveRowAtIndex:destinationRow toIndex:draggedIndex];
            }
            
            destinationRow++;
            draggedIndex = [upperDraggedIndexes indexGreaterThanIndex:draggedIndex];
        }
        
        [[self.undoManager prepareWithInvocationTarget:_data] insertObjects:[draggedRowData copy] atIndexes:[draggedRowIndexes copy]];
        [[self.undoManager prepareWithInvocationTarget:_data] removeObjectsAtIndexes:finalIndexesAfterDropping];
        
        [self.tableView endUpdates];
        
        [[self.undoManager prepareWithInvocationTarget:self.tableView] beginUpdates];
        [[self.undoManager prepareWithInvocationTarget:NSAnimationContext.self] beginGrouping];
    } completionHandler:^{
        [self dataGotEdited];
    }];
    
    return YES;
}

#pragma mark - updateTableView

-(void)updateTableColumns {
    if (!self.tableView) return;
    
    for(NSTableColumn *col in self.tableView.tableColumns.mutableCopy) {
        [self.tableView removeTableColumn:col];
    }
    for(int i = 0; i < _maxColumnNumber; ++i) {
        NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%d",i]];
        tableColumn.dataCell = dataCell;
		tableColumn.headerCell.stringValue = i < columnNames.count ? columnNames[i] : [self generateColumnName:i];
        ((NSCell *)tableColumn.headerCell).alignment = NSCenterTextAlignment;
        [self.tableView addTableColumn: tableColumn];
    }
    [self resizeTableColumnsToFitContents];
}

-(void)resizeColumnToFitContents:(NSTableColumn *)column {
    NSCell *sizingCell = [column.dataCell copy];
    CGFloat width = [column.headerCell cellSize].width;
    NSMutableArray<NSNumber *> *valueWidths = [NSMutableArray array];

    for (NSInteger row = 0; row < [self numberOfRowsInTableView:self.tableView]; row++) {
        id value = [self tableView:self.tableView objectValueForTableColumn:column row:row];
        NSString *displayValue = [value description];
        if (displayValue.length == 0) continue;
        sizingCell.stringValue = displayValue;
        [valueWidths addObject:@([sizingCell cellSize].width)];
    }

    if (valueWidths.count > 0) {
        [valueWidths sortUsingSelector:@selector(compare:)];
        width = MAX(width, valueWidths[valueWidths.count / 2].doubleValue);
    }

    width = MAX(40, ceil(width + 12));
    column.maxWidth = MAX(column.maxWidth, width);
    column.width = width;
}

-(void)resizeTableColumnsToFitContents {
    for (NSTableColumn *column in self.tableView.tableColumns) {
        [self resizeColumnToFitContents:column];
    }
}

-(void)updateTableColumnsNames {
    if(!self.csvConfig.firstRowAsHeader){
        for(int i = 0; i < [self.tableView.tableColumns count]; i++) {
            NSTableColumn *tableColumn = self.tableView.tableColumns[i];
            tableColumn.headerCell.stringValue = [self generateColumnName:i];
            ((NSCell *)tableColumn.headerCell).alignment = NSCenterTextAlignment;
        }
    }
    [self resizeTableColumnsToFitContents];
}

-(NSString *)generateColumnName:(int)index {
    int columnBase = 26;
    int digitMax = 7; // ceil(log26(Int32.Max))
    NSString *digits = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    
    if (index < columnBase) {
        return [digits substringWithRange:NSMakeRange(index, 1)];
    }
    
    NSMutableArray *columnName = [[NSMutableArray alloc]initWithCapacity:digitMax];
    for(int i = 0; i < digitMax; i++) {
        columnName[i] = @"";
    }
    
    index++;
    int offset = digitMax;
    while (index > 0) {
        [columnName replaceObjectAtIndex:--offset withObject:[digits substringWithRange:NSMakeRange(--index % columnBase, 1)]];
        index /= columnBase;
    }
    
    return [columnName componentsJoinedByString:@""];
}

#pragma mark - buttonActions


- (IBAction)addRow:(id)sender {
    switch ([self.toolBarButtonsAddRow selectedSegment]) {
        case 0:
            [self addRowAbove:sender];
            break;
        case 1:
            [self addRowBelow:sender];
        default:
            break;
    }
}

- (IBAction)addColumn:(id)sender {
    switch ([self.toolBarButtonsAddColumn selectedSegment]) {
        case 0:
            [self addColumnLeft:sender];
            break;
        case 1:
            [self addColumnRight:sender];
        default:
            break;
    }
}

-(void)addRowAbove:(id)sender {
    if ([self hasActiveFilters]) return;
    
    if(![self.tableView.window makeFirstResponder:self.tableView]) {
        NSBeep();
        return;
    }
    
    long rowIndex;
    NSIndexSet *rowIndexes = [self.tableView selectedRowIndexes];
    if(rowIndexes.count != 0){
        rowIndex = [rowIndexes firstIndex] > [rowIndexes lastIndex] ? [rowIndexes lastIndex] : [rowIndexes firstIndex];
    }else{
        rowIndex = 0;
    }
    
    [self addRowAtIndex:rowIndex];
    [self.undoManager setActionName:@"Add Line Above"];
}

-(void)addRowBelow:(id)sender {
    if ([self hasActiveFilters]) return;
    
    if(![self.tableView.window makeFirstResponder:self.tableView]) {
        NSBeep();
        return;
    }
    
    long rowIndex;
    NSIndexSet *rowIndexes = [self.tableView selectedRowIndexes];
    if(rowIndexes.count != 0){
        rowIndex = [rowIndexes firstIndex] > [rowIndexes lastIndex] ? [rowIndexes firstIndex]+1 : [rowIndexes lastIndex]+1;
    }else{
        rowIndex = [self.tableView numberOfRows];
    }
    
    [self addRowAtIndex:rowIndex];
    [self.undoManager setActionName:@"Add Line below"];
}

-(void)addColumnLeft:(id)sender {
    if ([self hasActiveFilters]) return;
    
    if(![self.tableView.window makeFirstResponder:self.tableView]) {
        NSBeep();
        return;
    }
    
    long columnIndex;
    if([self.tableView selectedColumn] == -1){
        if([self.tableView editedColumn] == -1){
            columnIndex = 0;
        } else {
            columnIndex = [self.tableView editedColumn];
        }
    } else {
        NSIndexSet *columnIndexes = [self.tableView selectedColumnIndexes];
        columnIndex = [columnIndexes firstIndex] > [columnIndexes lastIndex] ? [columnIndexes lastIndex] : [columnIndexes firstIndex];
    }
    [self addColumnAtIndex:columnIndex];
    [self.undoManager setActionName:@"Add Column left"];
}

-(void)addColumnRight:(id)sender {
    if ([self hasActiveFilters]) return;
    
    if(![self.tableView.window makeFirstResponder:self.tableView]) {
        NSBeep();
        return;
    }
    
    long columnIndex;
    if([self.tableView selectedColumn] == -1){
        if([self.tableView editedColumn] == -1){
            columnIndex = [self.tableView numberOfColumns];
        } else {
            columnIndex = [self.tableView editedColumn]+1;
        }
    } else {
        NSIndexSet *columnIndexes = [self.tableView selectedColumnIndexes];
        columnIndex = [columnIndexes firstIndex] > [columnIndexes lastIndex] ? [columnIndexes firstIndex]+1 : [columnIndexes lastIndex]+1;
    }
    [self addColumnAtIndex:columnIndex];
    [self.undoManager setActionName:@"Add Column right"];
}

-(IBAction)deleteColumn:(id)sender {
    if ([self hasActiveFilters]) return;
    
    long selectedIndex = [self.tableView selectedColumn];
    if(selectedIndex == -1 || ![self.tableView.window makeFirstResponder:self.tableView]) {
        NSBeep();
        return;
    }
    
    NSIndexSet *columnIndexes = [self.tableView selectedColumnIndexes];
    [self deleteColumnsAtIndexes:columnIndexes];
    [self.undoManager setActionName:@"Delete Column(s)"];
}

-(IBAction)deleteRow:(id)sender {
    if ([self hasActiveFilters]) return;
    
    long selectedIndex = [self.tableView selectedRow];
    if(selectedIndex == -1 || ![self.tableView.window makeFirstResponder:self.tableView]) {
        NSBeep();
        return;
    }
    
    NSIndexSet *rowIndexes = [self.tableView selectedRowIndexes];
    [self deleteRowsAtIndexes:rowIndexes];
    [self.undoManager setActionName:@"Delete Row(s)"];
}

-(void)updateToolbarIcons {
    self.toolBarButtonsAddColumn.segmentStyle = NSSegmentStyleSeparated;
    self.toolBarButtonsAddRow.segmentStyle = NSSegmentStyleSeparated;
    [self.toolBarButtonsAddColumn setImage:[ToolbarIcons imageOfAddLeftColumnIcon] forSegment:0];
    [self.toolBarButtonsAddColumn setImage:[ToolbarIcons imageOfAddRightColumnIcon] forSegment:1];
    [self.toolBarButtonsAddColumn setToolTip:@"Add column to the left" forSegment:0];
    [self.toolBarButtonsAddColumn setToolTip:@"Add column to the right" forSegment:1];
    NSSize addColumnSize = self.toolBarButtonsAddColumn.intrinsicContentSize;
    addColumnSize.height = 30;
    self.toolbarItemAddColumn.minSize = addColumnSize;
    self.toolbarItemAddColumn.maxSize = addColumnSize;
    [self.toolBarButtonsAddRow setImage:[ToolbarIcons imageOfAddRowAboveIcon] forSegment:0];
    [self.toolBarButtonsAddRow setImage:[ToolbarIcons imageOfAddRowBelowIcon] forSegment:1];
    [self.toolBarButtonsAddRow setToolTip:@"Add row above" forSegment:0];
    [self.toolBarButtonsAddRow setToolTip:@"Add row below" forSegment:1];
    NSSize addRowSize = self.toolBarButtonsAddRow.intrinsicContentSize;
    addRowSize.height = 30;
    self.toolbarItemAddRow.minSize = addRowSize;
    self.toolbarItemAddRow.maxSize = addRowSize;
    self.toolBarButtonDeleteColumn.image = [ToolbarIcons imageOfDeleteColumnIcon];
    self.toolBarButtonDeleteColumn.toolTip = @"Delete selected column";
    NSSize deleteColumnSize = self.toolBarButtonDeleteColumn.intrinsicContentSize;
    deleteColumnSize.width = 35;
    deleteColumnSize.height = 30;
    self.toolbarItemDeleteColumn.minSize = deleteColumnSize;
    self.toolbarItemDeleteColumn.maxSize = deleteColumnSize;
    self.toolBarButtonDeleteRow.image = [ToolbarIcons imageOfDeleteRowIcon];
    self.toolBarButtonDeleteRow.toolTip = @"Delete selected row";
    NSSize deleteRowSize = self.toolBarButtonDeleteRow.intrinsicContentSize;
    deleteRowSize.width = 35;
    deleteRowSize.height = 30;
    self.toolbarItemDeleteRow.minSize = deleteRowSize;
    self.toolbarItemDeleteRow.maxSize = deleteRowSize;
}

-(void)enableToolbarButtons{
    enableEditing = YES;
    _toolBarButtonDeleteColumn.enabled = YES;
    _toolBarButtonDeleteRow.enabled = YES;
    _toolBarButtonsAddColumn.enabled = YES;
    _toolBarButtonsAddRow.enabled = YES;
    for (NSToolbarItem *item in [(NSWindowController*)self.windowControllers.firstObject window].toolbar.visibleItems) {
        item.enabled = YES;
    }
}


#pragma mark - buttonActionImplementations

-(void)deleteRowsAtIndexes:(NSIndexSet *)rowIndexes{
    
    NSMutableArray *toDeleteRows = [[NSMutableArray alloc]initWithArray:[_data objectsAtIndexes:rowIndexes]];
    [[self.undoManager prepareWithInvocationTarget:self] restoreRowsWithContent:toDeleteRows atIndexes:rowIndexes];
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [self.tableView beginUpdates];
        [_data removeObjectsAtIndexes:rowIndexes];
        [self.tableView removeRowsAtIndexes:rowIndexes withAnimation:NSTableViewAnimationSlideUp];
        [self.tableView endUpdates];
        [self resizeTableColumnsToFitContents];
    } completionHandler:^{
        [self dataGotEdited];
    }];
}

-(void)restoreRowsWithContent:(NSArray *)rowContents atIndexes:(NSIndexSet *)rowIndexes {
    
    [[self.undoManager prepareWithInvocationTarget:self] deleteRowsAtIndexes:rowIndexes];
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [self.tableView scrollRowToVisible:[rowIndexes firstIndex]];
        [self.tableView beginUpdates];
        [_data insertObjects:rowContents atIndexes:rowIndexes];
		[self.tableView insertRowsAtIndexes:rowIndexes withAnimation:NSTableViewAnimationSlideDown];
		[self.tableView selectRowIndexes:rowIndexes byExtendingSelection:NO];
        [self.tableView endUpdates];
        [self resizeTableColumnsToFitContents];
    } completionHandler:^{
        [self updateSearchMatches];
    }];
}

-(void)addRowAtIndex:(long)rowIndex {
    
    if([self.tableView numberOfColumns] == 0){
        [self addColumnAtIndex:0];
    }
    
    NSMutableArray *toInsertArray = [[NSMutableArray alloc]init];
    for (int i = 0; i < _maxColumnNumber; ++i) {
        [toInsertArray addObject:@""];
    }
    
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [self.tableView beginUpdates];
        [_data insertObject:toInsertArray atIndex:rowIndex];
		[self.tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:rowIndex] withAnimation:NSTableViewAnimationSlideDown];
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection:NO];
        [self.tableView endUpdates];
    } completionHandler:^{
        [self dataGotEdited];
    }];
    
    NSIndexSet *toRedoIndexSet = [NSIndexSet indexSetWithIndex:rowIndex];
    [[self.undoManager prepareWithInvocationTarget:self] deleteRowsAtIndexes:toRedoIndexSet];
}

-(void)addColumnAtIndex:(long) columnIndex {
    
    ignoreColumnDidMoveNotifications = YES;
    long columnIdentifier = _maxColumnNumber;
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%ld",columnIdentifier]];
    col.dataCell = dataCell;
    [self.tableView addTableColumn:col];
    col.headerCell.stringValue = @"";
    [self.tableView moveColumn:[self.tableView numberOfColumns]-1 toColumn:columnIndex];
    
    for(NSMutableArray *rowArray in _data) {
        [rowArray addObject:@""];
    }
    
    _maxColumnNumber++;
    
    [self.tableView selectColumnIndexes:[NSIndexSet indexSetWithIndex:columnIndex] byExtendingSelection:NO];
    [self updateTableColumnsNames];
    [self.tableView scrollColumnToVisible:columnIndex];
    ignoreColumnDidMoveNotifications = NO;
    
    [self dataGotEdited];
    [[self.undoManager prepareWithInvocationTarget:self] deleteColumnsAtIndexes:[NSIndexSet indexSetWithIndex:columnIndex]];
}

-(void)deleteColumnsAtIndexes:(NSIndexSet *) columnIndexes{
    
    ignoreColumnDidMoveNotifications = YES;
    NSMutableArray *columnIds = [[NSMutableArray alloc]init];
    NSArray *tableColumns = self.tableView.tableColumns.copy;
    [columnIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSTableColumn *col = tableColumns[idx];
        [columnIds addObject:col.identifier];
        [self.tableView removeTableColumn:col];
    }];
    ignoreColumnDidMoveNotifications = NO;
    [self updateTableColumnsNames];
    
    long selectedIndex = [columnIndexes firstIndex] > [columnIndexes lastIndex] ? [columnIndexes lastIndex] : [columnIndexes firstIndex];
    
    if(selectedIndex == [self.tableView numberOfColumns]){
        [self.tableView selectColumnIndexes:[NSIndexSet indexSetWithIndex: [self.tableView numberOfColumns]-1] byExtendingSelection:NO];
    }else{
        [self.tableView selectColumnIndexes:[NSIndexSet indexSetWithIndex: selectedIndex] byExtendingSelection:NO];
    }
    
    [self dataGotEdited];
    [[self.undoManager prepareWithInvocationTarget:self] restoreColumns:columnIds atIndexes:columnIndexes];
    
}

-(void)restoreColumns:(NSMutableArray *)columnIds atIndexes:(NSIndexSet *)columnIndexes{
    
    ignoreColumnDidMoveNotifications = YES;
    for(int i = 0; i < columnIds.count; i++){
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:columnIds[i]];
        col.dataCell = dataCell;
        if(self.csvConfig.firstRowAsHeader){
            col.headerCell.stringValue = [columnNames objectAtIndex:((NSString *)columnIds[i]).integerValue];
        }
        ((NSCell *)col.headerCell).alignment = NSCenterTextAlignment;
        [self.tableView addTableColumn:col];
        [self.tableView moveColumn:[self.tableView numberOfColumns]-1 toColumn:[columnIndexes firstIndex]+i];
    }
    ignoreColumnDidMoveNotifications = NO;
    
    [self updateTableColumnsNames];
    [self.tableView selectColumnIndexes:columnIndexes byExtendingSelection:NO];
    [self updateSearchMatches];
    [[self.undoManager prepareWithInvocationTarget:self]deleteColumnsAtIndexes:columnIndexes];
    
}

-(void)moveColumnFrom:(long)oldIndex toIndex:(long)newIndex {
    [self.tableView moveColumn:oldIndex toColumn:newIndex];
    [self updateTableColumnsNames];
}

#pragma mark - configuration

-(void)configurationChangedForFormatViewController:(TTFormatViewController*)formatViewController {
	self.csvConfig = formatViewController.config;
	[self reloadForConfigurationChange];
}

-(BOOL)canChangeCSVFormat {
    return !self.fileURL || (!self.didSave && !self.documentEdited);
}

-(IBAction)changeCSVEncoding:(NSMenuItem *)sender {
    if (![self canChangeCSVFormat]) return;
    self.csvConfig.encoding = sender.tag;
    [self reloadForConfigurationChange];
}

-(IBAction)changeCSVSeparator:(NSMenuItem *)sender {
    if (![self canChangeCSVFormat]) return;
    self.csvConfig.columnSeparator = @[@",", @";", @"\t", @"|"][sender.tag];
    [self reloadForConfigurationChange];
}

-(IBAction)changeCSVDecimalMark:(NSMenuItem *)sender {
    if (![self canChangeCSVFormat]) return;
    self.csvConfig.decimalMark = sender.tag == 0 ? @"." : @",";
    [self reloadForConfigurationChange];
}

-(IBAction)changeCSVQuoteStyle:(NSMenuItem *)sender {
    if (![self canChangeCSVFormat]) return;
    self.csvConfig.quoteCharacter = sender.tag == 2 ? @"" : @"\"";
    self.csvConfig.escapeCharacter = sender.tag == 0 ? @"\"" : sender.tag == 1 ? @"\\" : @"";
    [self reloadForConfigurationChange];
}

-(IBAction)toggleCSVHeader:(id)sender {
    if (![self canChangeCSVFormat]) return;
    self.csvConfig.firstRowAsHeader = !self.csvConfig.firstRowAsHeader;
    [self reloadForConfigurationChange];
}

-(void)reloadForConfigurationChange {
	if (!newFile) {
		NSError *outError;
		BOOL didReload = [self reloadDataWithError:&outError];
		if (!didReload) {
			readingError = outError;
			[self displayError:outError];
		} else {
			readingError = nil;
			[errorControllerView removeFromSuperview];
			errorControllerView = nil;
		}
	}
}

-(void)dataGotEdited {
    if([self.tableView selectedColumn] != -1){
        [self.tableView scrollColumnToVisible: [[self.tableView selectedColumnIndexes] firstIndex]];
    }else if([self.tableView selectedRow] != -1){
        [self.tableView scrollRowToVisible:[[self.tableView selectedRowIndexes] firstIndex]];
    }
    if (searchField.stringValue.length > 0) [self updateSearchMatches];
}

#pragma mark - Column filtering

- (NSString *)filterValueForRow:(NSArray *)row columnIdentifier:(NSString *)identifier {
    NSInteger index = identifier.integerValue;
    if (index >= row.count) return @"";
    id value = row[index];
    if ([value isKindOfClass:[NSDecimalNumber class]]) {
        return [value descriptionWithLocale:@{NSLocaleDecimalSeparator:self.csvConfig.decimalMark}];
    }
    return [value description] ?: @"";
}

- (NSArray<NSString *> *)filterValuesForColumnIdentifier:(NSString *)identifier {
    NSMutableSet<NSString *> *values = [NSMutableSet set];
    for (NSArray *row in _data) {
        [values addObject:[self filterValueForRow:row columnIdentifier:identifier]];
        if (values.count > 20) return @[];
    }
    return [[values allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (NSArray<NSTableColumn *> *)filterableColumns {
    NSMutableArray<NSTableColumn *> *columns = [NSMutableArray array];
    for (NSTableColumn *column in self.tableView.tableColumns) {
        NSUInteger count = [self filterValuesForColumnIdentifier:column.identifier].count;
        if (count >= 2 && count <= 20) [columns addObject:column];
    }
    return columns;
}

- (BOOL)hasActiveFilters {
    return excludedFilterValues.count > 0;
}

- (BOOL)isFilterValueIncluded:(NSString *)value forColumnIdentifier:(NSString *)identifier {
    return ![excludedFilterValues[identifier] containsObject:value];
}

- (void)addFilterValueItemsForColumn:(NSTableColumn *)column toMenu:(NSMenu *)menu {
    for (NSString *value in [self filterValuesForColumnIdentifier:column.identifier]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:value.length ? value : @"(Empty)" action:@selector(toggleColumnFilterValue:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = @{ @"column": column.identifier, @"value": value };
        item.state = [self isFilterValueIncluded:value forColumnIdentifier:column.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
}

- (void)rebuildVisibleRows {
    [self.tableView deselectAll:nil];
    if (![self hasActiveFilters]) {
        visibleRows = nil;
    } else {
        NSMutableArray<NSNumber *> *rows = [NSMutableArray array];
        for (NSUInteger index = 0; index < _data.count; index++) {
            NSArray *row = _data[index];
            BOOL included = YES;
            for (NSString *identifier in excludedFilterValues) {
                if ([excludedFilterValues[identifier] containsObject:[self filterValueForRow:row columnIdentifier:identifier]]) {
                    included = NO;
                    break;
                }
            }
            if (included) [rows addObject:@(index)];
        }
        visibleRows = rows;
    }
    [self.tableView reloadData];
    [self updateSearchMatches];
    BOOL canChangeStructure = enableEditing && ![self hasActiveFilters];
    self.toolBarButtonDeleteColumn.enabled = canChangeStructure;
    self.toolBarButtonDeleteRow.enabled = canChangeStructure;
    self.toolBarButtonsAddColumn.enabled = canChangeStructure;
    self.toolBarButtonsAddRow.enabled = canChangeStructure;
}

- (IBAction)toggleColumnFilterValue:(NSMenuItem *)sender {
    NSDictionary *selection = sender.representedObject;
    NSString *identifier = selection[@"column"];
    NSString *value = selection[@"value"];
    NSMutableSet<NSString *> *excluded = excludedFilterValues[identifier];
    if (!excluded) {
        excluded = [NSMutableSet set];
        excludedFilterValues[identifier] = excluded;
    }
    if ([excluded containsObject:value]) [excluded removeObject:value];
    else [excluded addObject:value];
    if (excluded.count == 0) [excludedFilterValues removeObjectForKey:identifier];
    [self rebuildVisibleRows];
}

- (IBAction)clearColumnFilters:(id)sender {
    [excludedFilterValues removeAllObjects];
    [self rebuildVisibleRows];
}

- (IBAction)clearFiltersForColumn:(NSMenuItem *)sender {
    [excludedFilterValues removeObjectForKey:sender.representedObject];
    [self rebuildVisibleRows];
}

#pragma mark - copy,paste,delete

-(BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(clearColumnFilters:)) return [self hasActiveFilters];
    if (menuItem.action == @selector(clearFiltersForColumn:)) return excludedFilterValues[menuItem.representedObject].count > 0;
    if (menuItem.action == @selector(changeCSVEncoding:)) {
        menuItem.state = menuItem.tag == self.csvConfig.encoding ? NSControlStateValueOn : NSControlStateValueOff;
        return [self canChangeCSVFormat];
    }
    if (menuItem.action == @selector(changeCSVSeparator:)) {
        NSArray<NSString *> *separators = @[@",", @";", @"\t", @"|"];
        menuItem.state = [self.csvConfig.columnSeparator isEqualToString:separators[menuItem.tag]] ? NSControlStateValueOn : NSControlStateValueOff;
        return [self canChangeCSVFormat];
    }
    if (menuItem.action == @selector(changeCSVDecimalMark:)) {
        menuItem.state = [self.csvConfig.decimalMark isEqualToString:(menuItem.tag == 0 ? @"." : @",")] ? NSControlStateValueOn : NSControlStateValueOff;
        return [self canChangeCSVFormat];
    }
    if (menuItem.action == @selector(changeCSVQuoteStyle:)) {
        BOOL selected = menuItem.tag == 0 ? [self.csvConfig.quoteCharacter isEqualToString:@"\""] && [self.csvConfig.escapeCharacter isEqualToString:@"\""] :
                        menuItem.tag == 1 ? [self.csvConfig.quoteCharacter isEqualToString:@"\""] && [self.csvConfig.escapeCharacter isEqualToString:@"\\"] :
                        self.csvConfig.quoteCharacter.length == 0;
        menuItem.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        return [self canChangeCSVFormat];
    }
    if (menuItem.action == @selector(toggleCSVHeader:)) {
        menuItem.state = self.csvConfig.firstRowAsHeader ? NSControlStateValueOn : NSControlStateValueOff;
        return [self canChangeCSVFormat];
    }
    if (menuItem.action == @selector(copy:)){
       if([self.tableView selectedRow] == -1 && [self.tableView selectedColumn] == -1){
           return NO;
       }
    }
    if (menuItem.action == @selector(paste:)) {
        if(!enableEditing || [self hasActiveFilters]) {
            return NO;
        }
    }
    if (menuItem.action == @selector(delete:)) {
        if(([self.tableView selectedRow] == -1 && [self.tableView selectedColumn] == -1)|| !enableEditing || [self hasActiveFilters]){
            return NO;
        }
    }
    return YES;
}

-(IBAction)copy:(id)sender {
    if([self.tableView selectedRow] != -1){
        [self copyRowIndexes:[self.tableView selectedRowIndexes]];
    }else if([self.tableView selectedColumn] != -1){
        [self copyColumnIndexes:[self.tableView selectedColumnIndexes]];
    }else{
        NSBeep();
    }
    return;
}

-(void)copyRowIndexes:(NSIndexSet *)rowIndexes {
    NSMutableString *copyString = [NSMutableString string];
    
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSMutableString *rowString = [NSMutableString string];
        NSArray *row = _data[[self modelRowForVisibleRow:idx]];
        for(NSString *columnId in [self getColumnsOrder]) {
            if(row.count <= columnId.integerValue) break;
            NSString *cellValue;
            if([row[columnId.integerValue] isKindOfClass:[NSDecimalNumber class]]){
                cellValue = [row[columnId.integerValue] descriptionWithLocale:[NSLocale currentLocale]];
            }else{
                cellValue = row[columnId.integerValue];
            }
            [self appendCell:cellValue toString:rowString];
        }
        [rowString deleteCharactersInRange:NSMakeRange(rowString.length-1, 1)];
        [copyString appendString:rowString];
        [copyString appendString:@"\n"];
    }];
    if (copyString.length > 0) [copyString deleteCharactersInRange:NSMakeRange(copyString.length-1, 1)];
    
    NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
    [generalPasteboard clearContents];
    [generalPasteboard writeObjects:@[copyString]];
}

-(void)copyColumnIndexes:(NSIndexSet *)columnIndexes {
    NSMutableString *copyString = [NSMutableString string];
    
    for(int i = 0; i < [self.tableView numberOfRows];i++){
        NSMutableString *rowString = [[NSMutableString alloc]init];
        NSArray *row = _data[[self modelRowForVisibleRow:i]];
        [columnIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            NSUInteger columnIndex = ((NSTableColumn *)self.tableView.tableColumns[idx]).identifier.integerValue;
            NSString *cellValue;
            if(row.count <= columnIndex) return;
            if([row[columnIndex] isKindOfClass:[NSDecimalNumber class]]){
                cellValue = [row[columnIndex] descriptionWithLocale:[NSLocale currentLocale]];
            }else{
                cellValue = row[columnIndex];
            }
            [self appendCell:cellValue toString:rowString];
        }];
        if(rowString.length > 0)[rowString deleteCharactersInRange:NSMakeRange(rowString.length-1, 1)];
        [copyString appendString:rowString];
        [copyString appendString:@"\n"];
    }
    if (copyString.length > 0) [copyString deleteCharactersInRange:NSMakeRange(copyString.length-1, 1)];
    
    NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
    [generalPasteboard clearContents];
    [generalPasteboard writeObjects:@[copyString]];
}

-(void)appendCell:(NSString *)cell toString:(NSMutableString *)rowString {
    NSMutableString *cellValue = cell.mutableCopy;
    [cellValue replaceOccurrencesOfString:@"\t" withString:@" " options:0 range:NSMakeRange(0,cellValue.length)];
    [cellValue replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0,cellValue.length)];
    [rowString appendString:cellValue];
    [rowString appendString:@"\t"];
}

-(IBAction)paste:(id)sender {
    if ([self hasActiveFilters]) return;
    long toInsertIndex;
    if([self.tableView selectedRow] == -1){
        toInsertIndex = [self.tableView numberOfRows];
    } else {
        NSIndexSet *selectedRowIndexes = [self.tableView selectedRowIndexes];
        toInsertIndex = [selectedRowIndexes lastIndex] > [selectedRowIndexes firstIndex] ? [selectedRowIndexes lastIndex] + 1 : [selectedRowIndexes firstIndex] + 1;
    }
    long firstIndex = toInsertIndex;
    
    NSArray *classes = [[NSArray alloc]initWithObjects:[NSString class], nil];
    NSDictionary *options = [NSDictionary dictionary];
    NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
    NSArray *toInsert = [generalPasteboard readObjectsForClasses:classes options:options];
    CSVReader *reader = [[CSVReader alloc]initWithString:[toInsert lastObject] configuration:self.csvConfig];
    
    while(!reader.isAtEnd) {
        NSArray *oneReadLine = [reader readLineForPastingTo:[self getColumnsOrder] maxColumnIndex:_maxColumnNumber];
        
        for(long i = _maxColumnNumber; i < oneReadLine.count;i++){
            [self addColumnAtIndex:self.tableView.tableColumns.count];
        }
        
        [_data insertObject:oneReadLine atIndex:toInsertIndex];
        toInsertIndex++;
    }
    [self.tableView reloadData];
    [self resizeTableColumnsToFitContents];
    
    NSIndexSet *toSelectRowIndexes = [[NSIndexSet alloc]initWithIndexesInRange:NSMakeRange(firstIndex, toInsertIndex-firstIndex)];
    [self.tableView selectRowIndexes:toSelectRowIndexes byExtendingSelection:NO];
    [[self.undoManager prepareWithInvocationTarget:self] deleteRowsAtIndexes:toSelectRowIndexes];
    [self.undoManager setActionName:@"Paste Data"];
    [self dataGotEdited];
}

-(IBAction)delete:(id)sender {
    if ([self hasActiveFilters]) return;
    long selectedIndex = [self.tableView selectedRow];
    if(selectedIndex == -1){
        selectedIndex = [self.tableView selectedColumn];
        if(selectedIndex == -1) {
            NSBeep();
            return;
        }
        NSIndexSet *columnIndexes = [self.tableView selectedColumnIndexes];
        [self deleteColumnsAtIndexes:columnIndexes];
        [self.undoManager setActionName:@"Delete Column(s)"];
    }else{
        NSIndexSet *rowIndexes = [self.tableView selectedRowIndexes];
        [self deleteRowsAtIndexes:rowIndexes];
        [self.undoManager setActionName:@"Delete Row(s)"];
    }
    [self dataGotEdited];
}

#pragma mark - Menu Item Actions

-(IBAction)exportFile:(id)sender {
    
    accessoryViewController = [[TTFormatViewController alloc] initWithNibName:@"TTFormatViewControllerAccessory" bundle:nil];
    
    
    NSWindow *window = [[[self windowControllers] objectAtIndex: 0] window];
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.accessoryView = accessoryViewController.view;
    accessoryViewController.config.firstRowAsHeader = self.csvConfig.firstRowAsHeader;
    [accessoryViewController selectFormatByConfig];
    savePanel.allowedFileTypes = [NSArray arrayWithObject:@"csv"];
    [savePanel beginSheetModalForWindow:window completionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton)
        {
			NSError *error = nil;
			NSData *data = [self dataWithCSVConfig:accessoryViewController.config error:&error];
			if (!data) {
				[self presentError:error modalForWindow:window delegate:nil didPresentSelector:NULL contextInfo:NULL];
			}
			BOOL success = [data writeToURL:[savePanel URL] options:NSDataWritingAtomic error:&error];
			if (!success) {
				[self presentError:error modalForWindow:window delegate:nil didPresentSelector:NULL contextInfo:NULL];
			}
        }
    }];
}

-(IBAction)openReadme:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/jakob/TableTool/blob/master/README.md"]];
}
@end
