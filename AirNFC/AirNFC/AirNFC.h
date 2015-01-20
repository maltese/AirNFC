//
//  AirNFC.h
//  AirNFC
//
//  Created by Matteo Cortonesi on 12/16/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM (NSUInteger, AirNFCState) {
    AirNFCStateDisconnected,
    AirNFCStateLookingForOtherDevice,
    AirNFCStateConnecting,
    AirNFCStateConnected
};

@protocol AirNFCDelegate;

@interface AirNFC : NSObject

+ (AirNFC *)airNFC;

// Observable, changes on the same thread that called the
// `-[AirNFC connectWithError:]` method.
@property (nonatomic, assign, readonly) AirNFCState state;

@property (nonatomic, weak) id <AirNFCDelegate> delegate;

- (BOOL)connectWithError:(NSError **)error;

// Must be called on the same thread that called the
// `-[AirNFC connectWithError:]` method, unless it has not been ever called yet.
// To ease clean up, can be called even if we are already disconnected.
- (void)disconnect;

- (void)write:(NSData *)data;

@end

@protocol AirNFCDelegate <NSObject>

// The following events are all delivered on the same thread that called the
// `-[AirNFC connectWithError:]` method.

@optional

- (void)airNFC:(AirNFC *)airNFC didUpdateConnectingProgress:(CGFloat)progress;

- (void)airNFCDidConnect:(AirNFC *)airNFC;

- (void)airNFC:(AirNFC *)airNFC didReceiveData:(NSData *)data;

- (void)airNFC:(AirNFC *)airNFC didFailWithError:(NSError *)error;

@end