//
//  AMAudioConnectionEngine.h
//  AirNFC
//
//  Created by Matteo Cortonesi on 2/5/13.
//  Copyright (c) 2013 Matteo Cortonesi. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM (NSUInteger, AMAudioConnectionEngineState) {
    AMAudioConnectionEngineStateInactive,
    AMAudioConnectionEngineStateLookingForOtherDevice,
    AMAudioConnectionEngineStateNegotiatingSharedSecret
};

@protocol AMAudioConnectionEngineDelegate;

@interface AMAudioConnectionEngine : NSObject

+ (AMAudioConnectionEngine *)audioConnectionEngine;

@property (nonatomic, assign, readonly) AMAudioConnectionEngineState state;

@property (nonatomic, weak) id <AMAudioConnectionEngineDelegate> delegate;

- (BOOL)startWithError:(NSError **)error;

- (void)stop;

@end

@protocol AMAudioConnectionEngineDelegate <NSObject>

@optional

- (void)audioConnectionEngine:(AMAudioConnectionEngine *)audioConnectionEngine didUpdateConnectingProgress:(CGFloat)progress;

- (void)audioConnectionEngine:(AMAudioConnectionEngine *)audioConnectionEngine didConnectWithSharedSecret:(void *)sharedSecret;

- (void)audioConnectionEngine:(AMAudioConnectionEngine *)audioConnectionEngine didFailWithError:(NSError *)error;

@end