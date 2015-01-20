//
//  ViewController.h
//  Tester
//
//  Created by Matteo Cortonesi on 10/22/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ADECanvas;

@interface ViewController : UIViewController
@property (weak, nonatomic) IBOutlet UIButton *button;
@property (weak, nonatomic) IBOutlet ADECanvas *canvas;
@property (weak, nonatomic) IBOutlet UILabel *errorCountLabel;

@end
