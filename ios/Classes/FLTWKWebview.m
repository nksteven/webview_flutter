//
//  FLTWKWebview.m
//  Pods-Runner
//
//  Created by songsong on 2019/8/15.
//

#import "FLTWKWebview.h"

@implementation FLTWKWebview

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {

    if (!CGRectContainsPoint(self.bounds, point)) {
        CGPoint newPoint = [self convertPoint:point toView:self.toolBar];
        if (CGRectContainsPoint(self.toolBar.bounds, newPoint)) {
            return YES;
        }
        return NO;
    }
    return YES;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

@end
