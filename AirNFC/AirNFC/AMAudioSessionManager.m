//
//  AMAudioSessionManager.m
//  AirNFC
//
//  Created by Matteo Cortonesi on 12/16/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import "AMAudioSessionManager.h"
#import "AirNFCConfiguration.h"
#import "AirNFCErrors.h"
#import <AVFoundation/AVFoundation.h>

@interface AMAudioSessionManager () <AVAudioSessionDelegate>

@property (nonatomic, assign, getter = isRunning, readwrite) BOOL running;

@property (nonatomic, strong) NSThread *invokingThread;

@end

@implementation AMAudioSessionManager

//------------------------------------------------------------------------------
#pragma mark - Getting the Singleton
//------------------------------------------------------------------------------

+ (AMAudioSessionManager *)audioSessionManager {
    static AMAudioSessionManager *audioSessionManager;
    static dispatch_once_t done;
    dispatch_once(&done, ^{
                      audioSessionManager = [AMAudioSessionManager new];
                  });
    return audioSessionManager;
}

//------------------------------------------------------------------------------
#pragma mark - Starting and Stopping an Audio Session
//------------------------------------------------------------------------------

- (BOOL)startWithError:(NSError **)error {
    AMAssert(!self.isRunning, @"Cannot start audio session because it is already running.");

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *localError = nil;

    // Remember the invoking thread.
    self.invokingThread = [NSThread currentThread];

    // If AVAudioSessionInterruptionNotification is available, register for the
    // session interruption notification.
    if (&AVAudioSessionInterruptionNotification) {
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self
                               selector:@selector(audioSessionInterruptionNotification:)
                                   name:AVAudioSessionInterruptionNotification object:nil];
    } else {
        // Deprecated: receive interruption messages by setting the delegate.
        audioSession.delegate = self;
    }

    // Set audio session Category
    if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                             error:&localError]) {
        // Clean up.
        [self cleanUp];

        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart",
                NSUnderlyingErrorKey: localError
            };
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:userInfo];
        }
        return NO;
    }

    // Set audio session mode
    if (![audioSession setMode:AVAudioSessionModeMeasurement
                         error:&localError]) {
        // Clean up.
        [self cleanUp];

        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart",
                NSUnderlyingErrorKey: localError
            };
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:userInfo];
        }
        return NO;
    }

    NSString *errorMessage = @"AirNFCErrorUnableToStart: Cannot set desired sample rate.";
    // Set audio session sample rate
    if ([audioSession
         respondsToSelector:@selector(setPreferredSampleRate:error:)]) {
        if (![audioSession setPreferredSampleRate:kSampleRate
                                            error:&localError]) {
            // Clean up.
            [self cleanUp];

            if (error) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart",
                    NSUnderlyingErrorKey: localError
                };
                *error = [NSError errorWithDomain:AirNFCErrorDomain
                                             code:AirNFCErrorUnableToStart
                                         userInfo:userInfo];
            }
            return NO;
        }

        if ([audioSession preferredSampleRate] != kSampleRate) {
            // Clean up.
            [self cleanUp];

            if (error) {
                *error = [NSError errorWithDomain:AirNFCErrorDomain
                                             code:AirNFCErrorUnableToStart
                                         userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            }
            return NO;
        }
    } else {
        if (![audioSession setPreferredHardwareSampleRate:kSampleRate error:&localError]) {
            // Clean up.
            [self cleanUp];

            if (error) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart",
                    NSUnderlyingErrorKey: localError
                };
                *error = [NSError errorWithDomain:AirNFCErrorDomain
                                             code:AirNFCErrorUnableToStart
                                         userInfo:userInfo];
            }
            return NO;
        }

        if ([audioSession preferredHardwareSampleRate] != kSampleRate) {
            // Clean up.
            [self cleanUp];

            if (error) {
                *error = [NSError errorWithDomain:AirNFCErrorDomain
                                             code:AirNFCErrorUnableToStart
                                         userInfo:@{NSLocalizedDescriptionKey: errorMessage}];
            }
            return NO;
        }
    }

    // Set audio session IO buffer duration
    if (![audioSession setPreferredIOBufferDuration:kAudioPacketSampleCount / kSampleRate
                                              error:&localError]) {
        // Clean up.
        [self cleanUp];

        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart",
                NSUnderlyingErrorKey: localError
            };
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:userInfo];
        }
        return NO;
    }

    // Override the output audio port.
    if (![audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&localError]) {
        // Clean up.
        [self cleanUp];

        if (error) {
            NSDictionary *userInfo = @{
                                       NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart",
                                       NSUnderlyingErrorKey: localError
                                       };
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:userInfo];
        }
        return NO;
    }

    // Activate the audio session
    if (![audioSession setActive:YES error:&localError]) {
        // Clean up.
        [self cleanUp];

        if (error) {
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart",
                NSUnderlyingErrorKey: localError
            };
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:userInfo];
        }
        return NO;
    }

    // At the end, update the state.
    self.running = YES;

    return YES;
}

- (void)cleanUp {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    self.invokingThread = nil;

    // If AVAudioSessionInterruptionNotification is available, unregister for
    // the session interruption notification.
    if (&AVAudioSessionInterruptionNotification) {
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter removeObserver:self];
    } else {
        // Deprecated: stop receiving interruption messages by unsetting the
        // delegate.
        audioSession.delegate = nil;
    }

    // Deactivate the audio session.
    AMAssert([[AVAudioSession sharedInstance] setActive:NO
                                            withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                                  error:nil], @"Could not deactivate Audio Session");

    // At the end, update the state.
    self.running = NO;
}

- (void)stop {
    AMAssert(self.invokingThread == nil || [NSThread currentThread] == self.invokingThread, @"This method must be called on the same thread that called the `-[%@ startWithError:]` method, unless it has not been ever called yet.", [self class]);

    // If we are not already stopped...
    if (self.isRunning) {
        [self cleanUp];
    }
}

//------------------------------------------------------------------------------
#pragma mark - Handling Audio Session Interruptions
//------------------------------------------------------------------------------

- (void)audioSessionInterruptionNotification:(NSNotification *)notification {
    AVAudioSessionInterruptionType interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        // Got interrupted.
        [self handleInterruption];
    }
}

// Deprecated.
// Sent by the audio session.
- (void)beginInterruption {
    [self handleInterruption];
}

- (void)handleInterruption {
    AMAssert([NSThread currentThread] == [NSThread mainThread], @"");

    // The following check is needed because `invokingThread` might have become
    // nil meanwhile.
    NSThread *invokingThread = self.invokingThread;
    if (invokingThread) {
        [self performSelector:@selector(handleInterruptionOnInvokingThread) onThread:invokingThread withObject:nil waitUntilDone:NO];
    }
}

- (void)handleInterruptionOnInvokingThread {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    // The following check is needed because we might already be in the
    // stoppped state.
    if (self.isRunning) {
        [self stop];

        // Inform the delegate about the interruption.
        if ([self.delegate respondsToSelector:@selector(audioSessionManagerDidReceiveAudioSessionInterruption:)]) {
            [self.delegate audioSessionManagerDidReceiveAudioSessionInterruption:self];
        }
    }
}

@end
