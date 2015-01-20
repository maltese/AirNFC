//
//  AirNFC.m
//  AirNFC
//
//  Created by Matteo Cortonesi on 12/16/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import "AirNFC.h"
#import "AMAudioConnectionEngine.h"

#define informDelegateAboutError(error) \
    do { \
        if ([self.delegate respondsToSelector:@selector(airNFC:didFailWithError:)]) { \
            [self.delegate airNFC:self didFailWithError:error]; \
        } \
    } while (0)

@interface AirNFC () <AMAudioConnectionEngineDelegate>

@property (nonatomic, assign, readwrite) AirNFCState state;

@property (nonatomic, strong) NSThread *invokingThread;

@end

@implementation AirNFC

//------------------------------------------------------------------------------
#pragma mark - Initializing an AirNFC Object
//------------------------------------------------------------------------------

- (id)init {
    self = [super init];
    if (self) {
    }
    return self;
}

//------------------------------------------------------------------------------
#pragma mark - Getting the Singleton
//------------------------------------------------------------------------------

+ (AirNFC *)airNFC {
    static AirNFC *airNFC;
    static dispatch_once_t done;
    dispatch_once(&done, ^{
                      airNFC = [AirNFC new];
                  });
    return airNFC;
}

//------------------------------------------------------------------------------
#pragma mark - Connecting and Disconnecting
//------------------------------------------------------------------------------

- (BOOL)connectWithError:(NSError **)error {
    AMAssert(self.state == AirNFCStateDisconnected, @"Could not start AirNFC because it has already been started.");

    self.invokingThread = [NSThread currentThread];

    AMAudioConnectionEngine *audioConnectionEngine = [AMAudioConnectionEngine audioConnectionEngine];
    audioConnectionEngine.delegate = self;

    // Start the audio connection engine.
    if (![audioConnectionEngine startWithError:error]) {
        [self cleanUp];

        return NO;
    }

    // Update the state.
    self.state = AirNFCStateLookingForOtherDevice;

    return YES;
}

- (void)cleanUp {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    // Stop the audio connection engine.
    AMAudioConnectionEngine *audioConnectionEngine = [AMAudioConnectionEngine audioConnectionEngine];
    [audioConnectionEngine stop];
    audioConnectionEngine.delegate = nil;

    self.invokingThread = nil;

    // At the end, update the state.
    self.state = AirNFCStateDisconnected;
}

- (void)disconnect {
    AMAssert(self.invokingThread == nil || [NSThread currentThread] == self.invokingThread, @"This method must be called on the same thread that called the `-[%@ connectWithError:]` method, unless it has not been ever called yet.", [self class]);

    // If we are not already disconnected...
    if (self.state != AirNFCStateDisconnected) {
        [self cleanUp];
    }
}

//------------------------------------------------------------------------------
#pragma mark - Writing Data
//------------------------------------------------------------------------------

- (void)write:(NSData *)data {
    AMAssert(self.state == AirNFCStateConnected, @"Cannot write data because AirNFC is not connected yet.");
}

//------------------------------------------------------------------------------
#pragma mark - AMAudioConnectionEngineDelegate
//------------------------------------------------------------------------------

- (void)audioConnectionEngine:(AMAudioConnectionEngine *)audioConnectionEngine didUpdateConnectingProgress:(CGFloat)progress {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    // Inform the delegate about the progress.
    if ([self.delegate respondsToSelector:@selector(airNFC:didUpdateConnectingProgress:)]) {
        [self.delegate airNFC:self didUpdateConnectingProgress:progress];
    }
}

- (void)audioConnectionEngine:(AMAudioConnectionEngine *)audioConnectionEngine didFailWithError:(NSError *)error {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    [self disconnect];

    informDelegateAboutError(error);
}

@end
