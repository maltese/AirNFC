//
//  AirNFCErrors.h
//  AirNFC
//
//  Created by Matteo Cortonesi on 12/16/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const AirNFCErrorDomain;

typedef NS_ENUM (NSUInteger, AirNFCError) {
    AirNFCErrorUnableToStart,
    AirNFCErrorInsufficientCPUTime,
    AirNFCErrorInterruption
};