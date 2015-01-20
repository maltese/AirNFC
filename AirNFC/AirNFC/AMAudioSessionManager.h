//
//  AMAudioSessionManager.h
//  AirNFC
//
//  Created by Matteo Cortonesi on 12/16/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol AMAudioSessionManagerDelegate;

@interface AMAudioSessionManager : NSObject

+ (AMAudioSessionManager *)audioSessionManager;

// Methods called on the delegate are always posted on the same thread that
// called the `-[AMAudioSessionManager startWithError:]` method.
@property (nonatomic, weak) id <AMAudioSessionManagerDelegate> delegate;

// Returns errors belonging to the AirNFC domain
- (BOOL)startWithError:(NSError **)error;

// Must be called on the same thread that called the
// `-[AMAudioSessionManager startWithError:]` method, unless it has not been
// ever called yet.
// To ease clean up, can be called even if we are already stopped.
- (void)stop;

// Observable, changes on the same thread that called the
// `-[AMAudioSessionManager startWithError:]` method.
@property (nonatomic, assign, getter = isRunning, readonly) BOOL running;

@end

@protocol AMAudioSessionManagerDelegate <NSObject>

@optional;

- (void)audioSessionManagerDidReceiveAudioSessionInterruption:(AMAudioSessionManager *)audioSessionManager;

@end