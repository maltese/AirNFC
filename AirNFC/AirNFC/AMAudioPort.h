//
//  AMAudioPort.h
//  AirNFC
//
//  Created by Matteo Cortonesi on 1/7/13.
//  Copyright (c) 2013 Matteo Cortonesi. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TPCircularBuffer.h"

@protocol AMAudioPortDelegate, AMAudioPortModem;

@interface AMAudioPort : NSObject

+ (AMAudioPort *)audioPort;

@property (nonatomic, weak) id <AMAudioPortDelegate> delegate;

@property (nonatomic, weak) id <AMAudioPortModem> modem;

// Error code is always AirNFCErrorUnableToStart.
- (BOOL)startWithError:(NSError **)error;

// Must be called on the same thread that called the
// `-[AMAudioPort startWithError:]` method, unless it has not been ever called
// yet.
// You can safely assume no more calls to the delegate or modem will be made
// after this method returns.
// To ease clean up, can be called even if we are already stopped.
- (void)stop;

// Observable, changes on the same thread that called the
// `-[AMAudioPort startWithError:]` method.
@property (nonatomic, assign, getter = isRunning, readonly) BOOL running;

// Schedules `data` of length `sampleCount` to be reproduced at `startTime`.
// Notes:
// - A start time in the past is not allowed.
// - `startTime` can be at most 1 second in the future.
// - Can only be called from the thread that invoked
// `-[AMAudioPortModem audioPort:didReceiveNewDataInCircularBuffer:sampleTime:]`
// .
- (void)scheduleOutputData:(float *)data
               sampleCount:(UInt32)sampleCount
                 startTime:(Float64)startTime;

@end

@protocol AMAudioPortDelegate <NSObject>

@optional

// Called on the same thread that called the `-[AMAudioPort startWithError:]`
// method.
- (void)audioPort:(AMAudioPort *)audioPort didFailWithError:(NSError *)error;

@end

@protocol AMAudioPortModem <NSObject>

@optional

// Called whenever `kAudioPacketSampleCount` new samples are available in the
// circular buffer.
// Called serially on a grand central dispatch high-priority queue and thread.
// `sampleTime` is the sample time corresponding to the first new sample.
// The modem must consume the bytes in the circular buffer at some point, as
// the circular buffer has a limited size of 1 second worth of data.
- (void)audioPort:(AMAudioPort *)audioPort
didReceiveNewDataInCircularBuffer:(TPCircularBuffer *)circularBuffer
       sampleTime:(Float64)sampleTime;

@end