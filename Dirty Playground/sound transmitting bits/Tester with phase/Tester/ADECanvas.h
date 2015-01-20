//
//  ADECanvas.h
//  Tester
//
//  Created by Matteo Cortonesi on 11/25/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ADECanvas : UIView

@property (nonatomic, assign) NSUInteger pilotSpacing;
@property (nonatomic, assign) NSUInteger numberOfCarriers;
@property (nonatomic, assign) float *data;

@end
