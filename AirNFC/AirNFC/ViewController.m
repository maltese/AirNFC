//
//  ViewController.m
//  AirNFC
//
//  Created by Matteo Cortonesi on 12/16/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import "ViewController.h"

#import "AirNFC.h"

@interface ViewController () <AirNFCDelegate>

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)boom:(id)sender {
    [AirNFC airNFC].delegate = self;
    NSError *error = nil;
    if (![[AirNFC airNFC] connectWithError:&error]) {
        NSLog(@"Error Connecting! %@", error);
    }
}
- (IBAction)stopButton:(id)sender {
    [[AirNFC airNFC] disconnect];
}

- (void)airNFCDidConnect:(AirNFC *)airNFC {
    NSLog(@"Connected");
}

- (void)airNFC:(AirNFC *)airNFC didFailWithError:(NSError *)error {
    NSLog(@"Error! %@", error);
}

- (void)viewDidUnload {
    [self setLabel:nil];
    [super viewDidUnload];
}
@end
