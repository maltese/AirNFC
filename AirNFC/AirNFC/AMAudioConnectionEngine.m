//
//  AMAudioConnectionEngine.m
//  AirNFC
//
//  Created by Matteo Cortonesi on 2/5/13.
//  Copyright (c) 2013 Matteo Cortonesi. All rights reserved.
//

#import "AMAudioConnectionEngine.h"
#import "AMAudioPort.h"
#import "AMDeviceDiscovererModem.h"

#define informDelegateAboutError(error) \
    do { \
        if ([self.delegate respondsToSelector:@selector(audioConnectionEngine:didFailWithError:)]) { \
            [self.delegate audioConnectionEngine:self didFailWithError:error]; \
        } \
    } while (0)

@interface AMAudioConnectionEngine () <AMAudioPortDelegate, AMDeviceDiscovererModemDelegate>

@property (nonatomic, assign, readwrite) AMAudioConnectionEngineState state;

@property (nonatomic, strong) NSThread *invokingThread;

@property (nonatomic, strong) AMDeviceDiscovererModem *deviceDiscovererModem;

@end

@implementation AMAudioConnectionEngine

//------------------------------------------------------------------------------
#pragma mark - Initializing an Audio Connection Engine Object
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

+ (AMAudioConnectionEngine *)audioConnectionEngine {
    static AMAudioConnectionEngine *audioConnectionEngine;
    static dispatch_once_t done;
    dispatch_once(&done, ^{
                      audioConnectionEngine = [AMAudioConnectionEngine new];
                  });
    return audioConnectionEngine;
}

//------------------------------------------------------------------------------
#pragma mark - Connecting and Disconnecting
//------------------------------------------------------------------------------

- (BOOL)startWithError:(NSError **)error {
    AMAssert(self.state == AMAudioConnectionEngineStateInactive, @"Could not start AMAudioConnectionEngine because it has already been started.");

    // Remember the invoking thread.
    self.invokingThread = [NSThread currentThread];

    // Set ourselves as the delegate of audio port such that we will be
    // notified of errors.
    AMAudioPort *audioPort = [AMAudioPort audioPort];
    audioPort.delegate = self;

    // Plug the device discoverer modem into to audio port.
    self.deviceDiscovererModem = [AMDeviceDiscovererModem new];
    self.deviceDiscovererModem.delegate = self;
    audioPort.modem = self.deviceDiscovererModem;

    // Start the audio port.
    if (![audioPort startWithError:error]) {
        [self cleanUp];

        return NO;
    }

    // Update the state.
    self.state = AMAudioConnectionEngineStateLookingForOtherDevice;

    return YES;
}

- (void)cleanUp {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    // Stop the audio port.
    AMAudioPort *audioPort = [AMAudioPort audioPort];
    [audioPort stop];
    audioPort.delegate = nil;
    audioPort.modem = nil;

    self.invokingThread = nil;

    // At the end, update the state.
    self.state = AMAudioConnectionEngineStateInactive;
}

- (void)stop {
    AMAssert(self.invokingThread == nil || [NSThread currentThread] == self.invokingThread, @"This method must be called on the same thread that called the `-[%@ startWithError:]` method, unless it has not been ever called yet.", [self class]);

    // If we are not already inactive...
    if (self.state != AMAudioConnectionEngineStateInactive) {
        [self cleanUp];
    }
}

//------------------------------------------------------------------------------
#pragma mark - AMAudioPortDelegate
//------------------------------------------------------------------------------

- (void)audioPort:(AMAudioPort *)audioPort didFailWithError:(NSError *)error {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    [self stop];

    informDelegateAboutError(error);
}

//------------------------------------------------------------------------------
#pragma mark - AMDeviceDiscovererModemDelegate
//------------------------------------------------------------------------------

- (void)deviceDiscovererModemDidDiscoverDevice:(AMDeviceDiscovererModem *)deviceDiscovererModem {
    // Running on a grand central dispatch thread.

//    [AMAudioPort audioPort].modem = ...;
}

@end
