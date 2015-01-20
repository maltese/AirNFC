//
//  AudioEngine.h
//  Tester
//
//  Created by Matteo Cortonesi on 11/9/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString * const ADEAudioEngineErrorDomain;

typedef NS_ENUM(NSUInteger, ADEAudioEngineError) {
    ADEAudioEngineErrorGenericError
};

@protocol ADEAudioEngineDelegate;


@interface ADEAudioEngine : NSObject

+ (ADEAudioEngine *)audioEngine;

@property (nonatomic, weak) id <ADEAudioEngineDelegate> delegate;

- (BOOL)startWithError:(NSError **)error;

- (BOOL)stopWithError:(NSError **)error;

@end

@protocol ADEAudioEngineDelegate <NSObject>

// Sent if the Audio Engine stops because of an audio session interruption.
- (void)audioEngineDidGetInterrupted:(ADEAudioEngine *)audioEngine;

- (void)audioEngineDidGetInterrupted:(ADEAudioEngine *)audioEngine hasData:(float *)data;

@end