//
//  ADEAssert.h
//  Tester
//
//  Created by Matteo Cortonesi on 11/15/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import <Foundation/Foundation.h>

#define ADEAssert(aCondition, aDescription, ...) \
    do { \
        if (!(aCondition)) { \
            NSLog(@"*** Terminating App due to uncaught exception, reason: %@", (aDescription)); \
            [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd \
                                                                object:self \
                                                                  file:[NSString stringWithUTF8String:__FILE__] \
                                                            lineNumber:__LINE__ \
                                                           description:(aDescription), ##__VA_ARGS__]; \
        } \
    } while(0)