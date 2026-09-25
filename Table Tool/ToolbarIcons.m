//
//  ToolbarIcons.m
//  Table Tool
//
//  Vector assets adapted from Lucide columns-3 and rows-3.
//  See Artwork/ToolbarIcons/LUCIDE-LICENSE.txt.
//

#import "ToolbarIcons.h"

@implementation ToolbarIcons

+ (NSImage *)templateImageNamed:(NSString *)name {
    NSImage *image = [[NSImage imageNamed:name] copy];
    image.template = YES;
    return image;
}

+ (NSImage *)imageOfAddLeftColumnIcon { return [self templateImageNamed:@"AddColumnLeft"]; }
+ (NSImage *)imageOfAddRightColumnIcon { return [self templateImageNamed:@"AddColumnRight"]; }
+ (NSImage *)imageOfDeleteColumnIcon { return [self templateImageNamed:@"DeleteColumn"]; }
+ (NSImage *)imageOfAddRowAboveIcon { return [self templateImageNamed:@"AddRowAbove"]; }
+ (NSImage *)imageOfAddRowBelowIcon { return [self templateImageNamed:@"AddRowBelow"]; }
+ (NSImage *)imageOfDeleteRowIcon { return [self templateImageNamed:@"DeleteRow"]; }

@end
