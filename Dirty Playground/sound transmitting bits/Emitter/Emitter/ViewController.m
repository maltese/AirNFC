//
//  ViewController.m
//  Tester
//
//  Created by Matteo Cortonesi on 10/22/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#include <mach/mach.h>
#include <mach/mach_time.h>

@interface ViewController ()
@property (nonatomic, assign) AudioUnit remoteIO;
@end

@implementation ViewController

UInt32 const kOutputBus = 0;
UInt32 const kInputBus = 1;

int const pilotCarrierSpacing = 25;
int const numberOfCarriers = 4 * pilotCarrierSpacing + 1; // must be = k * `pilotCarrierSpacing` + 1
float startFrequency = 789;
double const sampleRate = 44100;
UInt32 const numberOfFrames = 2048;
float *data;
UInt32 log2numberOfFrames;
UInt32 const numberOfFramesDivided2 = numberOfFrames / 2;
FFTSetup fftSetup = NULL;
AudioBufferList audioBufferList;
DSPSplitComplex splitComplex;

- (void)initValues {
    // Create the Audio Buffer List
    audioBufferList.mNumberBuffers = 1;
    AudioBuffer audioBuffer;
    audioBuffer.mNumberChannels = audioBufferList.mNumberBuffers;
    audioBuffer.mDataByteSize = sizeof(float) * numberOfFrames;
    audioBuffer.mData = malloc(audioBuffer.mDataByteSize);
    audioBufferList.mBuffers[0] = audioBuffer;

    log2numberOfFrames = ceilf(log2f(numberOfFrames));
    
    // Create the FFT
//    fftSetup = vDSP_create_fftsetup(log2numberOfFrames, kFFTRadix2);
    
    // Create the split complex structure
    splitComplex.realp = malloc(sizeof(float) * numberOfFramesDivided2);
    splitComplex.imagp = malloc(sizeof(float) * numberOfFramesDivided2);
    
    // Compute bits to transfer
    float bits[numberOfCarriers];
    for (int k = 0; k < numberOfCarriers; k++) {
        bits[k] = roundf((float)rand()/RAND_MAX);
        // Add pilot carrier every `pilotCarrierSpacing`.
        if (k % pilotCarrierSpacing == 0) {
            bits[k] = 1.0;
        }
    }
    
    // Compute phases
    float phases[numberOfCarriers];
    for (int k = 0; k < numberOfCarriers; k++) {
        phases[k] = (float)rand() / RAND_MAX * 2 * M_PI - M_PI;
    }
    
    // compute ofdm signal
    float max = -FLT_MAX;
    data = calloc(numberOfFrames, sizeof(float));
    for (int i = 0; i < numberOfFrames; i++) {
        for (int k = 0; k < numberOfCarriers; k++) {
            data[i] += bits[k] * cosf(2 * M_PI * (startFrequency+k) * (float)i/numberOfFrames + phases[k]);
//            data[i] += cosf(2 * M_PI * (startFrequency+k) * (float)i/numberOfFrames + phases[k]);
        }
        if (data[i] > max) {
            max = data[i];
        }
    }
    printf("%f\n", max);
    // Normalize data
    for (int i = 0; i < numberOfFrames; i++) {
        data[i] /= max;
//        data[i] /= sqrtf(numberOfCarriers);
//        printf("%d %f\n", i, data[i]);
    }
}


void computeFFTData(float *data, UInt32 dataLength) {
//    vDSP_ctoz((DSPComplex *)data, 2, &splitComplex, 1, numberOfFramesDivided2);
//    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2numberOfFrames, kFFTDirection_Forward);
}


OSStatus playbackCallback (
                            void                        *inRefCon,
                            AudioUnitRenderActionFlags  *ioActionFlags,
                            const AudioTimeStamp        *inTimeStamp,
                            UInt32                      inBusNumber,
                            UInt32                      inNumberFrames,
                            AudioBufferList             *ioData
                            ) {
    assert(inNumberFrames == numberOfFrames);
    
//    static mach_timebase_info_data_t    sTimebaseInfo;
//    // Start the clock.
//        
//    if ( sTimebaseInfo.denom == 0 ) {
//        (void) mach_timebase_info(&sTimebaseInfo);
//    }
//        
//    NSLog(@"Current time: %llu", mach_absolute_time() * sTimebaseInfo.numer / sTimebaseInfo.denom);
//    NSLog(@"Due time: %llu", inTimeStamp->mHostTime * sTimebaseInfo.numer / sTimebaseInfo.denom);
    
//    ViewController *self = (__bridge ViewController *)inRefCon;
    
    // make sure we don't drop packets.
    static Float64 oldSampleTime = 0;
    Float64 currentSampletime = inTimeStamp->mSampleTime;
    if (oldSampleTime) {
        assert(currentSampletime == oldSampleTime + numberOfFrames);
    }
    oldSampleTime = currentSampletime;
    
    ioData->mBuffers[0].mData = data;
    
    
    return noErr;
}

- (void)viewDidLoad {
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    
}

- (IBAction)start:(id)sender {
    // Setup Audio Session
    [self setupAudioSession];
    
    // Create the graph
    AUGraph graph;
    NSAssert(NewAUGraph(&graph) == noErr, @"");
    
    // Add a Remote I/O Audio Unit Node
    AUNode remoteIONode;
    AudioComponentDescription remoteIOAudioUnitDescription = [self remoteIOAudioUnitDescription];
    NSAssert(AUGraphAddNode(graph, &remoteIOAudioUnitDescription, &remoteIONode) == noErr, @"");
    
    // Instantiate the Audio Unit
    NSAssert(AUGraphOpen(graph) == noErr, @"");
    
    // Get a reference to the Remote I/O Audio Unit
    AudioUnit remoteIO;
    NSAssert(AUGraphNodeInfo(graph, remoteIONode, NULL, &remoteIO) == noErr, @"");
    self.remoteIO = remoteIO;
    
//    // Enable the input
//    UInt32 enableInput = 1;
//    NSAssert(AudioUnitSetProperty(remoteIO, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBus, &enableInput, sizeof(enableInput)) == noErr, @"");
    
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
    NSAssert(AudioUnitSetProperty(remoteIO, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &asbd, sizeof(asbd)) == noErr, @"");
//    NSAssert(AudioUnitSetProperty(remoteIO, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBus, &asbd, sizeof(asbd)) == noErr, @"");
    
    // Set the render callback
    AURenderCallbackStruct playbackCallbackStruct;
    playbackCallbackStruct.inputProc = playbackCallback;
    playbackCallbackStruct.inputProcRefCon = (__bridge void *)self;
    NSAssert(AudioUnitSetProperty(remoteIO, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, kOutputBus, &playbackCallbackStruct, sizeof(playbackCallbackStruct)) == noErr, @"");
    
    // Initialize the graph such that it will initialize the Audio Units
    NSAssert(AUGraphInitialize(graph) == noErr, @"");
    
    // Initialize the values used for the FFT and the Audio Unit
    [self initValues];
    
    // Start the graph
    NSAssert(AUGraphStart(graph) == noErr, @"");
}

- (void)setupAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error;
    NSAssert([audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error], @"");
    NSAssert([audioSession setMode:AVAudioSessionModeMeasurement error:&error], @"");
    NSAssert([audioSession setPreferredSampleRate:sampleRate error:&error], @"");
    NSAssert([audioSession preferredSampleRate] == sampleRate, @"");
    NSAssert([audioSession setPreferredIOBufferDuration:numberOfFrames / sampleRate error:&error], @"");
    [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
    [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
    NSAssert([audioSession setActive:YES error:&error], @"");
}

- (AudioComponentDescription)remoteIOAudioUnitDescription {
    AudioComponentDescription remoteIOAudioUnitDescription = {0};
    
    remoteIOAudioUnitDescription.componentType          = kAudioUnitType_Output;
    remoteIOAudioUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    remoteIOAudioUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    remoteIOAudioUnitDescription.componentFlags         = 0;
    remoteIOAudioUnitDescription.componentFlagsMask     = 0;
    
    return remoteIOAudioUnitDescription;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
