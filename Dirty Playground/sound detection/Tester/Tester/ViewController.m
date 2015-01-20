//
//  ViewController.m
//  Tester
//
//  Created by Matteo Cortonesi on 10/22/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import "ViewController.h"
#import "ADEAudioEngine.h"
#import "ADECanvas.h"

typedef NS_ENUM(NSUInteger, AppState) {
    AppStateStopped,
    AppStateStarted
};

@interface ViewController () <ADEAudioEngineDelegate>

@property (nonatomic, strong) ADEAudioEngine *audioEngine;
@property (nonatomic, assign) AppState appState;

@end

@implementation ViewController

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initialize];
    }
    return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self initialize];
    }
    return self;
}

- (void)initialize {
    self.audioEngine = [ADEAudioEngine new];
    self.audioEngine.delegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
}

- (void)audioEngineDidGetInterrupted:(ADEAudioEngine *)audioEngine {
    self.appState = AppStateStopped;
    [self.button setTitle:@"Start" forState:UIControlStateNormal];
}

- (IBAction)buttonTapped:(UIButton *)sender {
    NSError *error;
    
    if (self.appState == AppStateStopped) {
        if ([self.audioEngine startWithError:&error]) {
            [sender setTitle:@"Stop" forState:UIControlStateNormal];
        } else {
            NSLog(@"Error starting the audio session! %@", error);
        }
    } else if (self.appState == AppStateStarted) {
        if ([self.audioEngine stopWithError:&error]) {
            [sender setTitle:@"Start" forState:UIControlStateNormal];
        } else {
            NSLog(@"Error stopping the audio session! %@", error);
        }
    } else {
        assert(NO);
    }
    
}

- (void)audioEngineDidGetInterrupted:(ADEAudioEngine *)audioEngine hasData:(float *)data {
    self.canvas.data = data;
    self.canvas.numberOfCarriers = 101;
    self.canvas.pilotSpacing = 25;
    [self.canvas setNeedsDisplay];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidUnload {
    [self setCanvas:nil];
    [super viewDidUnload];
}
@end
