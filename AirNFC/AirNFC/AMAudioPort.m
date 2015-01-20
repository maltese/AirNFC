//
//  AMAudioPort.m
//  AirNFC
//
//  Created by Matteo Cortonesi on 1/7/13.
//  Copyright (c) 2013 Matteo Cortonesi. All rights reserved.
//

#import "AMAudioPort.h"
#import <AVFoundation/AVFoundation.h>
#include <mach/mach_time.h>
#import "AirNFCConfiguration.h"
#import "AMAudioSessionManager.h"
#import "TPCircularBuffer.h"
#import "AirNFCErrors.h"

@interface AMAudioPort () <AMAudioSessionManagerDelegate>

@property (nonatomic, assign, getter = isRunning, readwrite) BOOL running;
@property (nonatomic, assign, getter = isRemoteIOUnitRunning) BOOL remoteIOUnitRunning;

@property (nonatomic, strong) NSThread *invokingThread;

@property (nonatomic, assign, getter = isAudioCallbackIgnored) BOOL audioCallbackIgnored;

@property (nonatomic, assign) double hostTimeToNanoSecondsFactor;
@property (nonatomic, assign) double initialInputCallbackTimeStampInNanoSeconds;
@property (nonatomic, assign) double outputCallbackSampleTimeOffsetFromInputCallback;

@property (nonatomic, assign) BOOL modemRespondsToProtocolSelector;

@property (nonatomic, assign) AudioBufferList *audioBufferList;
@property (nonatomic, assign) AudioUnit remoteIOUnit;
@property (nonatomic, assign) Float64 lastMicrophoneSampleTime;

@property (nonatomic, assign) float *silence;
@property (nonatomic, assign) float *outputData;

@property (nonatomic, assign) TPCircularBuffer *outputCircularBuffer;

@property (nonatomic, assign) TPCircularBuffer *inputCircularBuffer;
@property (nonatomic, assign) BOOL firstCallbackExecution;
@property (nonatomic, assign) dispatch_queue_t inputProcessingQueue;

@end

@implementation AMAudioPort

//------------------------------------------------------------------------------
#pragma mark - Private Constants
//------------------------------------------------------------------------------

AudioUnitElement const static kInputBus = 1;
AudioUnitElement const static kOutputBus = 0;

//------------------------------------------------------------------------------
#pragma mark - Initializing an Audio Port Object
//------------------------------------------------------------------------------

- (id)init {
    self = [super init];
    if (self) {
        // Initialize `hostTimeToNanoSecondsFactor`.
        mach_timebase_info_data_t timebaseInfoData;
        (void)mach_timebase_info(&timebaseInfoData);
        self.hostTimeToNanoSecondsFactor = (double)timebaseInfoData.numer / (double)timebaseInfoData.denom;
    }
    return self;
}

//------------------------------------------------------------------------------
#pragma mark - Getting the Singleton
//------------------------------------------------------------------------------

+ (AMAudioPort *)audioPort {
    static AMAudioPort *audioPort;
    static dispatch_once_t done;
    dispatch_once(&done, ^{
                      audioPort = [AMAudioPort new];
                  });
    return audioPort;
}

//------------------------------------------------------------------------------
#pragma mark - Setting the Modem
//------------------------------------------------------------------------------

- (void)setModem:(id<AMAudioPortModem>)modem {
    // Update Model.
    _modem = modem;

    // Optimization for not having to ask the modem if it responds the selector
    // every single time.
    _modemRespondsToProtocolSelector = [modem respondsToSelector:@selector(audioPort:didReceiveNewDataInCircularBuffer:sampleTime:)];
}

//------------------------------------------------------------------------------
#pragma mark - Starting and Stopping the Audio Port
//------------------------------------------------------------------------------

- (BOOL)startWithError:(NSError **)error {
    AMAssert(!self.isRunning, @"Could not start AMAudioPort because it is already running.");

    // Initialize `lastMicrophoneSampleTime`.
    _lastMicrophoneSampleTime = -1;

    // Initialize `_firstCallbackExecution`;
    _firstCallbackExecution = YES;

    // Initialize `initialInputCallbackTimeStampInNanoSeconds`.
    self.initialInputCallbackTimeStampInNanoSeconds = 0;

    // Initialize `outputCallbackSampleTimeOffsetFromInputCallback`.
    self.outputCallbackSampleTimeOffsetFromInputCallback = 0;

    self.invokingThread = [NSThread currentThread];

    // It is important the memory allocation happens before the functions that
    // may return errors, because the clean up method assumes all the memory has
    // been allocated.
    [self allocateMemoryForVariables];

    // Start audio session.
    [AMAudioSessionManager audioSessionManager].delegate = self;
    if (![[AMAudioSessionManager audioSessionManager] startWithError:error]) {
        [self cleanUp];
        return NO;
    }

    // Create a remote IO unit.
    AudioComponent audioComponent;
    AudioComponentDescription remoteIOAudioUnitDescription;
    remoteIOAudioUnitDescription.componentType         = kAudioUnitType_Output;
    remoteIOAudioUnitDescription.componentSubType      = kAudioUnitSubType_RemoteIO;
    remoteIOAudioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    remoteIOAudioUnitDescription.componentFlags        = 0;
    remoteIOAudioUnitDescription.componentFlagsMask    = 0;
    audioComponent = AudioComponentFindNext(NULL, &remoteIOAudioUnitDescription);

    OSStatus errorCode;
    if ((errorCode = AudioComponentInstanceNew(audioComponent, &_remoteIOUnit))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }

    // Enable microphone input.
    UInt32 one = 1;
    if ((errorCode = AudioUnitSetProperty(_remoteIOUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBus, &one, sizeof(one)))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }

    // Set the desired audio format.
    AudioStreamBasicDescription asbd = {
        0
    };
    asbd.mSampleRate = kSampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mBytesPerFrame = kAudioSampleSize;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerPacket = asbd.mBytesPerFrame * asbd.mFramesPerPacket;
    asbd.mChannelsPerFrame = 1;
    asbd.mBitsPerChannel = 8 * asbd.mBytesPerFrame * asbd.mChannelsPerFrame;
    asbd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    if ((errorCode = AudioUnitSetProperty(_remoteIOUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &asbd, sizeof(asbd)))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }
    if ((errorCode = AudioUnitSetProperty(_remoteIOUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBus, &asbd, sizeof(asbd)))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }

    // Set input callback.
    AURenderCallbackStruct inputCallbackStruct;
    inputCallbackStruct.inputProc = (AURenderCallback)inputCallback;
    inputCallbackStruct.inputProcRefCon = (__bridge void *)self;
    if ((errorCode = AudioUnitSetProperty(_remoteIOUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, kInputBus, &inputCallbackStruct, sizeof(inputCallbackStruct)))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }

    // Set that the audio unit should not allocate a buffer for the recording of
    // data.
    UInt32 no = 0;
    if ((errorCode = AudioUnitSetProperty(_remoteIOUnit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, kInputBus, &no, sizeof(no)))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }

    // Set output callback.
    AURenderCallbackStruct outputCallbackStruct;
    outputCallbackStruct.inputProc = (AURenderCallback)outputCallback;
    outputCallbackStruct.inputProcRefCon = (__bridge void *)self;
    if ((errorCode = AudioUnitSetProperty(_remoteIOUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, kOutputBus, &outputCallbackStruct, sizeof(outputCallbackStruct)))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }

    // Initialize remote IO unit.
    if ((errorCode = AudioUnitInitialize(_remoteIOUnit))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }

    // Start the remote IO unit.
    if ((errorCode = AudioOutputUnitStart(_remoteIOUnit))) {
        [self cleanUp];

        if (error) {
            NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                           code:errorCode
                                                       userInfo:nil];
            *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorUnableToStart
                                     userInfo:@{
                          NSUnderlyingErrorKey: underlyingError,
                          NSLocalizedDescriptionKey: @"AirNFCErrorUnableToStart"
                      }];
        }
        return NO;
    }
    self.remoteIOUnitRunning = YES;

    // At the end, update the state.
    self.running = YES;

    return YES;
}

- (void)allocateMemoryForVariables {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    // Create the audio buffer List
    _audioBufferList = malloc(sizeof(AudioBufferList));
    _audioBufferList->mNumberBuffers = 1;
    AudioBuffer audioBuffer;
    audioBuffer.mNumberChannels = 1;
    audioBuffer.mDataByteSize = kAudioPacketSampleCount * kAudioSampleSize;
    _audioBufferList->mBuffers[0] = audioBuffer;

    // Create an audio packet of silence.
    _silence = calloc(kAudioPacketSampleCount, kAudioSampleSize);

    // Allocate space for the output sound buffer.
    _outputData = malloc(kAudioPacketSampleCount * kAudioSampleSize);

    // TODO: change buffer sizes to normal value.

    // Create the output circular buffer with a buffer size of 1 second.
    _outputCircularBuffer = malloc(sizeof(TPCircularBuffer));
    TPCircularBufferInit(_outputCircularBuffer, 5 * kSampleRate * kAudioSampleSize);

    // Create the input circular buffer with a buffer size of 1 second.
    _inputCircularBuffer = malloc(sizeof(TPCircularBuffer));
    TPCircularBufferInit(_inputCircularBuffer, 5 * kSampleRate * kAudioSampleSize);

    // Create the input processing queue.
    _inputProcessingQueue = dispatch_queue_create("com.AirNFC.inputProcessingQueue", DISPATCH_QUEUE_SERIAL);
    // Make it a high priority queue.
    dispatch_queue_t highPriorityQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    dispatch_set_target_queue(_inputProcessingQueue, highPriorityQueue);
}

- (void)freeMemoryForVariables {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    // Free the audio buffer list
    free(_audioBufferList);
    _audioBufferList = NULL;

    // Free the silence audio packet
    free(_silence);
    _silence = NULL;

    // Free the space for the output sound buffer.
    free(_outputData);
    _outputData = NULL;

    // The input and output circular buffers are being accessed by threads of
    // the `_inputProcessingQueue`. Therefore, we need to clean them up on that
    // queue to avoid race conditions.
    // This also guarantees that after this function returns, no more calls to
    // the delegate will be made since this is the last piece of code that will
    // by executed in the `_inputProcessingQueue`.
    dispatch_sync(_inputProcessingQueue, ^{
                      // Clean up the output circular buffer.
                      TPCircularBufferCleanup(_outputCircularBuffer);
                      free(_outputCircularBuffer);
                      _outputCircularBuffer = NULL;

                      // Clean up the input circular buffer.
                      TPCircularBufferCleanup(_inputCircularBuffer);
                      free(_inputCircularBuffer);
                      _inputCircularBuffer = NULL;
                  });

    // Release the input processing queue.
    dispatch_release(_inputProcessingQueue);
    _inputProcessingQueue = nil;
}

- (void)cleanUp {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    // If the remote IO unit is running...
    if (self.isRemoteIOUnitRunning) {
        // Stop it.
        // The following function will actually synchronize with the Core Audio
        // thread. This means, after its invocation, it is guaranteed no more
        // audio callbacks will be fired and we can therefore safely continue
        // the clean up memory used by the Core Audio thread, unless other
        // threads are still accessing it.
        AMAssert(!AudioOutputUnitStop(_remoteIOUnit), @"");
        self.remoteIOUnitRunning = NO;
    }

    // If a remote IO unit object exists...
    if (_remoteIOUnit) {
        // Dispose it.
        AMAssert(!AudioComponentInstanceDispose(_remoteIOUnit), @"");
        _remoteIOUnit = nil;
    }

    // Deactivate the audio session.
    AMAudioSessionManager *audioSessionManager = [AMAudioSessionManager audioSessionManager];
    [audioSessionManager stop];
    audioSessionManager.delegate = nil;

    [self freeMemoryForVariables];

    self.invokingThread = nil;

    // Reset the `audioCallbackIgnored` property.
    self.audioCallbackIgnored = NO;

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
#pragma mark - Scheduling Output Data
//------------------------------------------------------------------------------

- (void)scheduleOutputData:(float *)data
               sampleCount:(UInt32)sampleCount
                 startTime:(Float64)startTime {
    assert("AMAudioPortScheduleOutputData() can only be called from the thread that invoked `-[AMAudioPortDelegate audioPort:didReceiveNewDataInCircularBuffer:sampleTime:]`." &&
           dispatch_get_current_queue() == _inputProcessingQueue);

    // Get the head of the output circular buffer and the number of bytes
    // available to be written.
    int32_t availableBytesToWrite;
    TPCircularBuffer *outputCircularBuffer = _outputCircularBuffer;
    float *outputCircularBufferHead = TPCircularBufferHead(outputCircularBuffer, &availableBytesToWrite);

    Float64 outputCircularBufferHeadSampleTime = TPCircularBufferHeadSampleTime(outputCircularBuffer);
    int32_t outputCircularBufferFillCount = outputCircularBuffer->fillCount;
    assert("Writing more data than the available space is not allowed." &&
           (outputCircularBufferFillCount == 0 ?
            sampleCount <= availableBytesToWrite / kAudioSampleSize :
            startTime - outputCircularBufferHeadSampleTime + sampleCount <= availableBytesToWrite / kAudioSampleSize));

    UInt32 silenceLength = 0;

    // If there is no data in the output circular buffer...
    if (outputCircularBufferFillCount == 0) {
        // Copy all the data to the output circular buffer.
        memcpy(outputCircularBufferHead, data, sampleCount * kAudioSampleSize);
        // Update the output circular buffer tail sample time.
        TPCircularBufferSetTailSampleTime(outputCircularBuffer, startTime);
        // Update the output circular buffer head sample time. This will be
        // later increased again by the `TPCircularBufferProduce()` function by
        // the `sampleCount` amount.
        TPCircularBufferSetHeadSampleTime(outputCircularBuffer, startTime);
    } else {
        assert("Overriding data in the past is not allowed" &&
               (startTime >= outputCircularBufferHeadSampleTime));

        // Compute the amount of silence needed, if any.
        silenceLength = startTime - outputCircularBufferHeadSampleTime;
        // Write silence to the output circular buffer, if needed.
        memset(outputCircularBufferHead, 0, silenceLength * kAudioSampleSize);
        // Write data to the output circular buffer.
        memcpy(outputCircularBufferHead + silenceLength, data, sampleCount * kAudioSampleSize);
    }

    // Compute the number of bytes written.
    UInt32 producedBytes = (silenceLength + sampleCount) * kAudioSampleSize;

    // Mark the written bytes as "produced" so that they can be read by the
    // consumer.
    TPCircularBufferProduce(outputCircularBuffer, producedBytes);
}

//------------------------------------------------------------------------------
#pragma mark - Handling Callbacks
//------------------------------------------------------------------------------

OSStatus inputCallback(void *RefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    assert("Number for frames must correspond to the `audioPacketBufferSize`." && inNumberFrames == kAudioPacketSampleCount);

    // Get an unsafe, unretained reference to `self`. This avoids ARC to
    // automatically retain the object and thus sending an Objective-C message,
    // which we should not do here. Note that even tagging the variable with
    // `__weak` would not be safe as ARC will use some functions to load the
    // weak reference and we cannot be sure if that code will send Objective-C
    // messages or allocate memory.
    // We do not need to retain `self` as it will always be there as long as we
    // are running.
    AMAudioPort * __unsafe_unretained self = (__bridge AMAudioPort *)RefCon;

    // If we have to ignore the callback because the audio unit is being stop,
    // simply return.
    if (self->_audioCallbackIgnored) {
        return noErr;
    }

    // Get the sample time of the first sample in the buffer.
    // inTimeStamp->mSampleTime sometimes jumps far in the future with no
    // plausible explanation. See for example:
    // http://lists.apple.com/archives/coreaudio-api/2009/Mar/msg00225.html
    // Therefore it cannot be reliably used.
    // Instead we are going to use `inTimeStamp->mHostTime` and try to figure
    // out from there the corresponding sampleTime. We assume sample times are
    // multiples of `kAudioPacketSampleCount`. Moreover, we make the first
    // sample time start from 0.
    if (self->_initialInputCallbackTimeStampInNanoSeconds == 0) {
        self->_initialInputCallbackTimeStampInNanoSeconds = inTimeStamp->mHostTime * self->_hostTimeToNanoSecondsFactor;
    }
    double currentTimeInNanoSeconds = inTimeStamp->mHostTime * self->_hostTimeToNanoSecondsFactor;
    double sampleTime = round((currentTimeInNanoSeconds - self->_initialInputCallbackTimeStampInNanoSeconds) * kSampleRate * 1e-9 / kAudioPacketSampleCount) * kAudioPacketSampleCount;

    // Check if we dropped some packets.
    Float64 lastMicrophoneSampleTime = self->_lastMicrophoneSampleTime;
    if (lastMicrophoneSampleTime >= 0 && sampleTime - lastMicrophoneSampleTime > kAudioPacketSampleCount) {
        // Set the ignore audio callback flag.
        self->_audioCallbackIgnored = YES;

        // Handle the failure asynchronously;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                           // Running on a grand central dispatch thread.
                           [self handleInsufficientCPUTimeFailure];
                       });
        return noErr;
    }
    self->_lastMicrophoneSampleTime = sampleTime;

    // Get the head of the input circular buffer and the number of bytes
    // available to be written.
    int32_t availableBytesToWrite;
    TPCircularBuffer *inputCircularBuffer = self->_inputCircularBuffer;
    float *inputCircularBufferHead = TPCircularBufferHead(inputCircularBuffer, &availableBytesToWrite);

    // Check whether there is not enough space.
    if (kAudioPacketSampleCount > availableBytesToWrite / kAudioSampleSize) {
        // Set the ignore audio callback flag.
        self->_audioCallbackIgnored = YES;

        // Handle the failure asynchronously;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                           // Running on a grand central dispatch thread.
                           [self handleInsufficientCPUTimeFailure];
                       });
        return noErr;
    }

    // If this is the first time the callback is executed in the current
    // session...
    if (self->_firstCallbackExecution) {
        // Set the input circular buffer tail sample time.
        TPCircularBufferSetTailSampleTime(inputCircularBuffer, sampleTime);
        // Set the input circular buffer head sample time.
        TPCircularBufferSetHeadSampleTime(inputCircularBuffer, sampleTime);

        // Update the flag.
        self->_firstCallbackExecution = NO;
    }

    // Set the data buffer to write the recorded data to, to be the head of the
    // input circular buffer.
    AudioBufferList *audioBufferList = self->_audioBufferList;
    audioBufferList->mBuffers[0].mData = inputCircularBufferHead;

    // Write the recorded data to the input circular buffer
    AudioUnitRender(self->_remoteIOUnit, ioActionFlags, inTimeStamp, kInputBus, inNumberFrames, audioBufferList);

    // Tell the input circular buffer that we "produced" some data.
    TPCircularBufferProduce(inputCircularBuffer, kAudioPacketSampleCount * kAudioSampleSize);

    dispatch_async(self->_inputProcessingQueue, ^{
                       // Running on a grand central dispatch thread.

                       // Inform delegate new data is there.
                       if (self->_modemRespondsToProtocolSelector) {
                           [self->_modem audioPort:self
               didReceiveNewDataInCircularBuffer:self->_inputCircularBuffer
                                      sampleTime:sampleTime];
                       }
                   });

    return noErr;
}

OSStatus outputCallback(void *RefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    assert("Number for frames must correspond to the `audioPacketBufferSize`." && inNumberFrames == kAudioPacketSampleCount);

    // Get an unsafe, unretained reference to `self`. This avoids ARC to
    // automatically retain the object and thus sending an Objective-C message,
    // which we should not do here. Note that even tagging the variable with
    // `__weak` would not be safe as ARC will use some functions to load the
    // weak reference and we cannot be sure if that code will send Objective-C
    // messages or allocate memory.
    // We do not need to retain `self` as it will always be there as long as we
    // are running.
    AMAudioPort * __unsafe_unretained self = (__bridge AMAudioPort *)RefCon;

    // If we have to ignore the callback because the audio unit is being stop,
    // simply return.
    if (self->_audioCallbackIgnored) {
        return noErr;
    }

    // Get the sample time of the first sample in the buffer using the
    // information acquired in the inputCallback.
    double currentTimeInNanoSeconds = inTimeStamp->mHostTime * self->_hostTimeToNanoSecondsFactor;
    if (self->_outputCallbackSampleTimeOffsetFromInputCallback == 0) {
        self->_outputCallbackSampleTimeOffsetFromInputCallback = round((currentTimeInNanoSeconds - self->_initialInputCallbackTimeStampInNanoSeconds) * kSampleRate * 1e-9);
    }
    double sampleTime = round(((currentTimeInNanoSeconds - self->_initialInputCallbackTimeStampInNanoSeconds) * kSampleRate * 1e-9 - self->_outputCallbackSampleTimeOffsetFromInputCallback) / kAudioPacketSampleCount) * kAudioPacketSampleCount + self->_outputCallbackSampleTimeOffsetFromInputCallback;

    // Get the tail of the output circular buffer and the number of bytes
    // available to be read.
    int32_t availableBytesToRead;
    TPCircularBuffer *outputCircularBuffer = self->_outputCircularBuffer;
    float *outputCircularBufferTail = TPCircularBufferTail(outputCircularBuffer, &availableBytesToRead);
    assert("`availableBytesToRead` must be a multiple of the size of an audio sample." && availableBytesToRead % kAudioSampleSize == 0);

    // Check whether we did not manage to play some data.
    Float64 outputCircularBufferTailSampleTime = TPCircularBufferTailSampleTime(outputCircularBuffer);
    if (availableBytesToRead > 0 && outputCircularBufferTailSampleTime < sampleTime) {
        printf("AirNFC: *** WARNING *** Speaker audio packets were dropped. " \
               "This could considerably increase the time needed for AirNFC " \
               "to establish a connection. In order to solve this, reduce " \
               "the load on your CPU.\n");
    }

    // Check whether we need to output silence.
    BOOL outputSilence = availableBytesToRead == 0 ||
        outputCircularBufferTailSampleTime > sampleTime + kAudioPacketSampleCount - 1 ||
        outputCircularBufferTailSampleTime + kAudioPacketSampleCount - 1 < sampleTime;

    float *outputData = self->_outputData;
    if (outputSilence) {
        outputData = self->_silence;
    } else {
        // Compute the sample times that define the cutting point to extract the
        // data to be played. The left and right cutting points are included
        // in the extracted data.
        UInt64 leftSampleTime = MAX(outputCircularBufferTailSampleTime, sampleTime);
        UInt64 rightSampleTime = MIN(outputCircularBufferTailSampleTime + availableBytesToRead / kAudioSampleSize, sampleTime + kAudioPacketSampleCount) - 1;

        // Compute the offset of the cutting points in the output data buffer.
        UInt64 leftOffsetInOutputData = leftSampleTime - sampleTime;
        UInt64 rightOffsetInOutputData = rightSampleTime - sampleTime;

        // Compute the corresponding offsets in the output circular buffer.
        UInt64 leftOffsetInOutputCircularBuffer = leftSampleTime - outputCircularBufferTailSampleTime;
        UInt64 rightOffsetInOutputCircularBuffer = rightSampleTime - outputCircularBufferTailSampleTime;

        // If needed, fill the initial part of the output buffer with silence.
        memset(outputData, 0, leftOffsetInOutputData * kAudioSampleSize);
        // Extract the data from the output circular buffer and copy it to the
        // output.
        memcpy(outputData + leftOffsetInOutputData, outputCircularBufferTail + leftOffsetInOutputCircularBuffer, (rightSampleTime - leftSampleTime + 1) * kAudioSampleSize);
        // If needed, fill the final part of the output buffer with silence.
        memset(outputData + rightOffsetInOutputData + 1, 0, (kAudioPacketSampleCount - rightOffsetInOutputData - 1) * kAudioSampleSize);

        // Compute the number of bytes read.
        UInt32 consumedBytes = (rightOffsetInOutputCircularBuffer + 1) * kAudioSampleSize;

        // Mark the read bytes as "consumed".
        TPCircularBufferConsume(outputCircularBuffer, consumedBytes);
    }

    ioData->mBuffers[0].mData = outputData;

    return noErr;
}

//------------------------------------------------------------------------------
#pragma mark - AMAudioSessionManagerDelegate
//------------------------------------------------------------------------------

- (void)audioSessionManagerDidReceiveAudioSessionInterruption:(AMAudioSessionManager *)audioSessionManager {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    NSError *error = [NSError errorWithDomain:AirNFCErrorDomain
                                         code:AirNFCErrorInsufficientCPUTime
                                     userInfo:@{NSLocalizedDescriptionKey: @"AirNFCErrorInsufficientCPUTime"}];
    [self handleFailureOnInvokingThreadWithError:error];
}

//------------------------------------------------------------------------------
#pragma mark - Handling Failures
//------------------------------------------------------------------------------

- (void)handleInsufficientCPUTimeFailure {
    // We are running on a grand central dispatch thread.

    // The following check is needed because `invokingThread` might have become
    // nil meanwhile.
    NSThread *invokingThread = self.invokingThread;
    if (invokingThread) {
        NSError *error = [NSError errorWithDomain:AirNFCErrorDomain code:AirNFCErrorInsufficientCPUTime
                                         userInfo:@{NSLocalizedDescriptionKey: @"AirNFCErrorInsufficientCPUTime"}];

        // Call -[self handleFailureOnInvokingThreadWithError:] on
        // `invokingThread`.
        [self performSelector:@selector(handleFailureOnInvokingThreadWithError:)
                     onThread:invokingThread
                   withObject:error
                waitUntilDone:NO];
    }
}

- (void)handleFailureOnInvokingThreadWithError:(NSError *)error {
    AMAssert([NSThread currentThread] == self.invokingThread, @"");

    // The following check is needed because we might already be in the
    // stoppped state.
    if (self.isRunning) {
        // Stop ourselves.
        [self stop];

        // Inform the delegate about the error.
        if ([self.delegate respondsToSelector:@selector(audioPort:didFailWithError:)]) {
            [self.delegate audioPort:self didFailWithError:error];
        }
    }
}

@end
