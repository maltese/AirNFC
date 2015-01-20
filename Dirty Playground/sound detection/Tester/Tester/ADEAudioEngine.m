//
//  AudioEngine.m
//  Tester
//
//  Created by Matteo Cortonesi on 11/9/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import "ADEAudioEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import "ViewController.h"

#warning Remove when time measuring is not needed anymore
#include <mach/mach_time.h>

#define FailWithGenericErrorIfError(result) \
    do { \
        OSStatus __err = result; \
        if (__err) { \
            if (error) { \
                *error = [NSError errorWithDomain:ADEAudioEngineErrorDomain code:ADEAudioEngineErrorGenericError userInfo:nil]; \
            } \
            return NO; \
        } \
    } while (0)

@interface ADEAudioEngine () <AVAudioSessionDelegate>

@property (nonatomic, assign, getter=isRunning) BOOL running;
@property (nonatomic, assign) AUGraph graph;
@property (nonatomic, assign) AudioUnit remoteIO;

@end

@implementation ADEAudioEngine {
    // Store variables that need low-latency as instance variables
    UInt32 _log2numberOfFrames;
    FFTSetup _fftSetup;
    AudioBufferList _audioBufferList;
    DSPSplitComplex _splitComplex;
    
    Float64 _lastSampleTime;
    float *_bits;
    float *_pilotValues;
}

//------------------------------------------------------------------------------
#pragma mark - Constants
//------------------------------------------------------------------------------

NSString * const ADEAudioEngineErrorDomain = @"AudioEngineErrorDomain";
static UInt32 const kOutputBus = 0;
static UInt32 const kInputBus = 1;
static double const sampleRate = 44100;
static UInt32 const numberOfFrames = 2048;
static int const pilotCarrierSpacing = 25;
static int const numberOfCarriers = 4 * pilotCarrierSpacing + 1; // must be = k * `pilotCarrierSpacing` + 1
static int startFrequency = 789;
static UInt32 const numberOfFramesDivided2 = numberOfFrames / 2;

//------------------------------------------------------------------------------
#pragma mark - Initializing an Audio Enginge Object
//------------------------------------------------------------------------------

- (id)init {
    self = [super init];
    if (self) {
        // Create the Audio Buffer List
        _audioBufferList.mNumberBuffers = 1;
        AudioBuffer audioBuffer;
        audioBuffer.mNumberChannels = _audioBufferList.mNumberBuffers;
        audioBuffer.mDataByteSize = sizeof(float) * numberOfFrames;
        audioBuffer.mData = malloc(audioBuffer.mDataByteSize);
        _audioBufferList.mBuffers[0] = audioBuffer;
        
        _log2numberOfFrames = ceilf(log2f(numberOfFrames));
        
        // Create the FFT
        _fftSetup = vDSP_create_fftsetup(_log2numberOfFrames, kFFTRadix2);
        
        // Create the split complex structure
        _splitComplex.realp = malloc(sizeof(float) * numberOfFramesDivided2);
        _splitComplex.imagp = malloc(sizeof(float) * numberOfFramesDivided2);
        
        // Compute bits to transfer
        _bits = malloc(numberOfCarriers * sizeof(float));
        for (int k = 0; k < numberOfCarriers; k++) {
            _bits[k] = roundf((float)rand()/RAND_MAX);
            // Add pilot carrier every `pilotCarriersSpacing`.
            if (k % pilotCarrierSpacing == 0) {
                _bits[k] = 1.0;
            }
        }
        
        _pilotValues = malloc((numberOfCarriers / pilotCarrierSpacing + 1) * sizeof(float));
    }
    return self;
}

//------------------------------------------------------------------------------
#pragma mark - Getting the Singleton
//------------------------------------------------------------------------------

+ (ADEAudioEngine *)audioEngine {
    static ADEAudioEngine *audioEngine;
    static dispatch_once_t done;
    dispatch_once(&done, ^{audioEngine = [ADEAudioEngine new];});
    return audioEngine;
}

//------------------------------------------------------------------------------
#pragma mark - Starting and Stopping the Audio Engine
//------------------------------------------------------------------------------

- (BOOL)startWithError:(NSError **)error {
    ADEAssert(!self.running, @"Cannot start Audio Engine because it is already running");
    
    // Start Audio Session
    FailWithGenericErrorIfError(![self startAudioSessionWithError:error]);
    
    // Create the graph
    AUGraph graph = self.graph;
    FailWithGenericErrorIfError(NewAUGraph(&graph));
    
    // Add a Remote I/O Audio Unit Node
    AUNode remoteIONode;
    AudioComponentDescription remoteIOAudioUnitDescription = {0};
    remoteIOAudioUnitDescription.componentType          = kAudioUnitType_Output;
    remoteIOAudioUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    remoteIOAudioUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    remoteIOAudioUnitDescription.componentFlags         = 0;
    remoteIOAudioUnitDescription.componentFlagsMask     = 0;
    FailWithGenericErrorIfError(AUGraphAddNode(graph, &remoteIOAudioUnitDescription, &remoteIONode));
    
    // Instantiate the Audio Unit
    FailWithGenericErrorIfError(AUGraphOpen(graph));
    
    // Get a reference to the Remote I/O Audio Unit
    AudioUnit remoteIO;
    FailWithGenericErrorIfError(AUGraphNodeInfo(graph, remoteIONode, NULL, &remoteIO));
    self.remoteIO = remoteIO;
    
    // Enable the input
    UInt32 enableInput = 1;
    FailWithGenericErrorIfError(AudioUnitSetProperty(remoteIO, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBus, &enableInput, sizeof(enableInput)));
    
    // Set the format
    AudioStreamBasicDescription asbd = {0};
    asbd.mSampleRate = sampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mBytesPerFrame = 4;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerPacket = asbd.mBytesPerFrame * asbd.mFramesPerPacket;
    asbd.mChannelsPerFrame = 1;
    asbd.mBitsPerChannel = 8 * asbd.mBytesPerFrame * asbd.mChannelsPerFrame;
    asbd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    FailWithGenericErrorIfError(AudioUnitSetProperty(remoteIO, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd, sizeof(asbd)));
    FailWithGenericErrorIfError(AudioUnitSetProperty(remoteIO, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd, sizeof(asbd)));
    
    // Set the render callback
    AURenderCallbackStruct recordingCallbackStruct;
    recordingCallbackStruct.inputProc = recordingCallack;
    recordingCallbackStruct.inputProcRefCon = (__bridge void *)self;
    FailWithGenericErrorIfError(AudioUnitSetProperty(remoteIO, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, kInputBus, &recordingCallbackStruct, sizeof(recordingCallbackStruct)));
    UInt32 value = 0;
    FailWithGenericErrorIfError(AudioUnitSetProperty(remoteIO, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, kInputBus, &value, sizeof(value)));
    
    // Initialize the graph such that it will initialize the Audio Units
    FailWithGenericErrorIfError(AUGraphInitialize(graph));
        
    // Start the graph
    FailWithGenericErrorIfError(AUGraphStart(graph));
    
    return YES;
}

- (BOOL)stopWithError:(NSError **)error {
    return YES;
}

//------------------------------------------------------------------------------
#pragma mark - Starting and Stopping the Audio Session
//------------------------------------------------------------------------------

- (BOOL)startAudioSessionWithError:(NSError **)error {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    if (![audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:error]) {
        return NO;
    }
    
    if (![audioSession setMode:AVAudioSessionModeMeasurement error:error]) {
        return NO;
    }
    
    if ([audioSession respondsToSelector:@selector(setPreferredSampleRate:error:)]) {
        if (![audioSession setPreferredSampleRate:sampleRate error:error]) {
            return NO;
        }
        
        FailWithGenericErrorIfError([audioSession preferredSampleRate] != sampleRate);
    } else {
        if (![audioSession setPreferredHardwareSampleRate:sampleRate error:error]) {
            return NO;
        }
        
        FailWithGenericErrorIfError([audioSession preferredHardwareSampleRate] != sampleRate);
    }
    
    if (![audioSession setPreferredIOBufferDuration:numberOfFrames / sampleRate error:error]) {
        return NO;
    }
    
    if (![audioSession setActive:YES error:error]) {
        return NO;
    }
    
    // If AVAudioSessionInterruptionNotification is available, register for the session interruption notification
    if (&AVAudioSessionInterruptionNotification) {
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self selector:@selector(audioSessionInterruptionNotification:) name:AVAudioSessionInterruptionNotification object:nil];
    } else {
        // Use the deprecated way to get interruption notifications
        #warning Use of audio session's delegate is deprecated. Remove when no iOS 5 support is required anymore.
        audioSession.delegate = self;
    }

    return YES;
}


- (BOOL)stopAudioSessionWithError:(NSError **)error {
    ADEAssert(self.running, @"Cannot stop Audio Engine because it not running");
    
    if(![[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:error]) {
        return NO;
    }
    
    return YES;
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

#warning Use of audio session's delegate is deprecated. Remove when no iOS 5 support is required anymore.
// Sent by the audio session if we are on an older iOS version.
- (void)beginInterruption {
    [self handleInterruption];
}

- (void)handleInterruption {
    // Deregister for the session interruption notification
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    [self.delegate audioEngineDidGetInterrupted:self];
}

//------------------------------------------------------------------------------
#pragma mark - Handling the Input Microphone Data
//------------------------------------------------------------------------------

void computeFFTData(float *data, UInt32 dataLength, ADEAudioEngine *self) {
    //    computeFFTData(audioBufferList.mBuffers[0].mData, inNumberFrames, self);
    
    //    float maxAmplitude = 0;
    //    float maxAmplitudePhase = 0;
    //    int maxAmplitudeIndex = 0;
    //
    //    float *realp = self->_splitComplex.realp;
    //    float *imagp = self->_splitComplex.imagp;
    //    for (int i = 0; i < numberOfFramesDivided2; i++) {
    //        float realpValue = realp[i];
    //        float imagpValue = imagp[i];
    //        float amplitude = realpValue * realpValue + imagpValue * imagpValue;
    //        float phase = atan2f(imagpValue, realpValue);
    //        if (amplitude > maxAmplitude) {
    //            maxAmplitude = amplitude;
    //            maxAmplitudePhase = phase;
    //            maxAmplitudeIndex = i;
    //        }
    //    }

    vDSP_ctoz((DSPComplex *)data, 2, &self->_splitComplex, 1, numberOfFramesDivided2);
    vDSP_fft_zrip(self->_fftSetup, &self->_splitComplex, 1, self->_log2numberOfFrames, kFFTDirection_Forward);
}

OSStatus recordingCallack (
                           void                        *inRefCon,
                           AudioUnitRenderActionFlags  *ioActionFlags,
                           const AudioTimeStamp        *inTimeStamp,
                           UInt32                      inBusNumber,
                           UInt32                      inNumberFrames,
                           AudioBufferList             *ioData
                           ) {
    // ****** Measure time ******
    uint64_t        start;
    uint64_t        end;
    uint64_t        elapsed;
    uint64_t        elapsedNano;
    static uint64_t        maxElapsedNano = 0;
    static mach_timebase_info_data_t    sTimebaseInfo;
    start = mach_absolute_time();
    // ****** Measure time ******

    
    assert(inNumberFrames == numberOfFrames);
    
    ADEAudioEngine *self = (__bridge ADEAudioEngine *)inRefCon;
    
    // Get sample time
    Float64 sampleTime = inTimeStamp->mSampleTime;
    if (self->_lastSampleTime && self->_lastSampleTime + numberOfFrames != sampleTime) {
        NSLog(@"Dropped packet!");
        exit(EXIT_FAILURE);
    }
    self->_lastSampleTime = sampleTime;
    
    AudioBufferList audioBufferList = self->_audioBufferList;
    
    AudioUnitRender(self.remoteIO, ioActionFlags, inTimeStamp, kInputBus, inNumberFrames, &audioBufferList);
    
    vDSP_ctoz((DSPComplex *)audioBufferList.mBuffers[0].mData, 2, &self->_splitComplex, 1, numberOfFramesDivided2);
    vDSP_fft_zrip(self->_fftSetup, &self->_splitComplex, 1, self->_log2numberOfFrames, kFFTDirection_Forward);

    float *realp = self->_splitComplex.realp;
    float *imagp = self->_splitComplex.imagp;

    // Compute pilot values
    for (int k = startFrequency, p = 0; k < startFrequency + numberOfCarriers; k += pilotCarrierSpacing, p++) {
        // Compute amplitude of pilot
        float realpValue = realp[k];
        float imagpValue = imagp[k];
        self->_pilotValues[p] = sqrtf(realpValue * realpValue + imagpValue * imagpValue);
    }
    
    // Check received data
    int errorCount = 0;
    float *data = malloc(numberOfCarriers * sizeof(float));
    for (int k = startFrequency; k < startFrequency + numberOfCarriers; k++) {
        // Compute amplitude
        float realpValue = realp[k];
        float imagpValue = imagp[k];
        float amplitude = sqrtf(realpValue * realpValue + imagpValue * imagpValue);

        int carrierIndex = k - startFrequency;
        data[carrierIndex] = amplitude;
        if (carrierIndex % pilotCarrierSpacing != 0) {
            // This is not a pilot.
            // Compute the theoretical maximum amplitude value for this carrier
            // according to the pilots.
            int leftPilotIndex = (carrierIndex / pilotCarrierSpacing) * pilotCarrierSpacing;
            int rightPilotIndex = (carrierIndex / pilotCarrierSpacing + 1) * pilotCarrierSpacing;
            float leftPilotValue = self->_pilotValues[carrierIndex / pilotCarrierSpacing];
            float rightPilotValue = self->_pilotValues[carrierIndex / pilotCarrierSpacing + 1];
            // Interpolate the left and right values
            float maximumAmplitude = (rightPilotValue - leftPilotValue) / (rightPilotIndex - leftPilotIndex) * (carrierIndex - leftPilotIndex) + leftPilotValue;
            // Interpret the received signal as 1 if the amplitude is above half of the maximum amplitude.
            float bit = amplitude >= 0.5 * maximumAmplitude;
            if (self->_bits[carrierIndex] != bit) {
                errorCount++;
            }
        }
    }
    
    // Print error count
    printf("bit errors = %d\t%d\n", errorCount, numberOfCarriers);
    
    // Pass data to main thread to draw
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate audioEngineDidGetInterrupted:self hasData:data];
    });
    

    // ****** Measure time ******
    end = mach_absolute_time();
    elapsed = end - start;
    if ( sTimebaseInfo.denom == 0 ) {
        (void) mach_timebase_info(&sTimebaseInfo);
    }
    elapsedNano = elapsed * sTimebaseInfo.numer / sTimebaseInfo.denom;
    if (elapsedNano > maxElapsedNano) {
        maxElapsedNano = elapsedNano;
    }
//    NSLog(@"%lf", (double)elapsedNano / 1000000.0);
    // ****** Measure time ******
    
    return noErr;
}

//------------------------------------------------------------------------------
#pragma mark - Deallocating
//------------------------------------------------------------------------------

- (void)dealloc {
    if (self.isRunning) {
        [self stopWithError:nil];
    }
}

@end
