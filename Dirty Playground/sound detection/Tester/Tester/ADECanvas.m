//
//  ADECanvas.m
//  Tester
//
//  Created by Matteo Cortonesi on 11/25/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import "ADECanvas.h"

@implementation ADECanvas

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // Find maximum
    float dataMax = -FLT_MAX;
    for (NSUInteger index = 0; index < _numberOfCarriers; index++) {
        if (_data[index] > dataMax) {
            dataMax = _data[index];
        }
    }

    CGFloat selfWidth = CGRectGetWidth(self.bounds);
    CGFloat selfHeight = CGRectGetHeight(self.bounds);
    for (NSUInteger index = 0; index < _numberOfCarriers; index++) {
        CGFloat width = (selfWidth + 1) / (2 * _numberOfCarriers);
        CGFloat x = 0 + index * 2 * width;
        CGFloat height = _data[index] * selfHeight / dataMax;
        CGFloat y = selfHeight - height;
        CGRect dataRect = CGRectMake(x, y, width, height);
        
        if (index % _pilotSpacing == 0) {
            CGFloat redColor[] = {1, 0, 0, 1};
            CGContextSetFillColor(context, redColor);
        } else {
            CGFloat blackColor[] = {0, 0, 0, 1};
            CGContextSetFillColor(context, blackColor);
        }
        
        CGContextFillRect(context, dataRect);
    }
        
//    if (_data) {
//        free(_data);
//    }
}

@end
