//
//  AMDeviceDiscovererModem.m
//  AirNFC
//
//  Created by Matteo Cortonesi on 2/6/13.
//  Copyright (c) 2013 Matteo Cortonesi. All rights reserved.
//

#import "AMDeviceDiscovererModem.h"
#import "AirNFCConfiguration.h"
#import <Accelerate/Accelerate.h>

#import "ViewController.h"

static BOOL listener = YES;

@interface AMDeviceDiscovererModem ()

// Synchronization symbol variables.
@property (nonatomic, assign) float *synchronizationSymbol;
@property (nonatomic, assign) vDSP_Length log2SynchronizationSymbolFFTData;
@property (nonatomic, assign) FFTSetup synchronizationSymbolFFTSetup;
@property (nonatomic, assign) DSPSplitComplex synchronizationSymbolFFTData;
@property (nonatomic, assign) float *filteredSynchronizationSymbolData;
@property (nonatomic, assign) float *reversedFilteredSynchronizationSubsymbolData;

@property (nonatomic, assign) BOOL firstTime;

@end

@implementation AMDeviceDiscovererModem

//------------------------------------------------------------------------------
#pragma mark - Macros
//------------------------------------------------------------------------------

// Given a frequency in Hz, compute the corresponding number of oscillations in
// a time sequence of `samplesPerSymbol`. Assume a sample rate of `kSampleRate`.
#define AMFrequencyToOscillationCount(frequency, samplesPerSymbol) \
    frequency / kSampleRate * samplesPerSymbol

//------------------------------------------------------------------------------
#pragma mark - Private Constants
//------------------------------------------------------------------------------

NSUInteger const static kSamplesPerSynchronizationSymbol = 256;
NSUInteger const static kSamplesPerSynchronizationSymbolWithFadedParts = kSamplesPerSynchronizationSymbol + 2 * kOFDMSymbolExtremityFadingLength;
NSUInteger const static kSamplesPerSynchronizationSubsymbol = kSamplesPerSynchronizationSymbol / 2;
NSUInteger const static kSynchronizationSymbolFFTSize = 2 * kSamplesPerSynchronizationSymbol;

//------------------------------------------------------------------------------
#pragma mark - Initializing a Device Discoverer Modem Object
//------------------------------------------------------------------------------

- (id)init {
    self = [super init];
    if (self) {
        self.firstTime = YES;

        // Create `synchronizationSymbolFFTSetup`.
        self.log2SynchronizationSymbolFFTData = log2(2 * kSamplesPerSynchronizationSymbol);
        self.synchronizationSymbolFFTSetup = vDSP_create_fftsetup(self.log2SynchronizationSymbolFFTData, kFFTRadix2);

        [self createSynchronizationSymbol];

        // Allocate space for `synchronizationSymbolFFTData`.
        _synchronizationSymbolFFTData.realp = malloc(kSamplesPerSynchronizationSymbol * kAudioSampleSize);
        _synchronizationSymbolFFTData.imagp = malloc(kSamplesPerSynchronizationSymbol * kAudioSampleSize);

        // Allocate space for `filteredSynchronizationSymbolData`.
        self.filteredSynchronizationSymbolData = malloc(kSynchronizationSymbolFFTSize * kAudioSampleSize);

        // Allocate space for `reversedFilteredSynchronizationSubsymbolData`.
        self.reversedFilteredSynchronizationSubsymbolData = malloc(kSamplesPerSynchronizationSubsymbol * kAudioSampleSize);
    }
    return self;
}

- (void)createSynchronizationSymbol {
    // Allocate space for the synchronization symbol.
    self.synchronizationSymbol = malloc(kSamplesPerSynchronizationSymbolWithFadedParts * kAudioSampleSize);
    float *centralSynchronizationSymbol = self.synchronizationSymbol + kOFDMSymbolExtremityFadingLength;

    // Compute the lowest oscillation count for the subsymbol.
    NSUInteger lowestOscillationCountForSubsymbol = ceilf(AMFrequencyToOscillationCount(kLowestSoundFrequency, kSamplesPerSynchronizationSubsymbol));

    // Compute the number of carriers required to fill all the bandwidth of the
    // subsymbol whilst keeping it periodic.
    NSUInteger subsymbolCarrierCount = floorf(AMFrequencyToOscillationCount(kHighestSoundFrequency, kSamplesPerSynchronizationSubsymbol)) - lowestOscillationCountForSubsymbol + 1;

    // Initialize the carrier phases. This phases have been optimally chosen to
    // lower the PAPR (Peak-to-Average Power Ratio), which in this case amounts
    // to 1.920576579000864.
    float carrierPhases[] = {2.437141070138417, 1.379861523905170, 6.048383864459403, 3.223180788132005, 4.936236699655129, 5.878707885536211};

    // Generate the subsymbol data.
    for (NSUInteger sampleIndex = 0; sampleIndex < kSamplesPerSynchronizationSubsymbol; sampleIndex++) {
        float sampleValue = 0;
        for (NSUInteger i = 0; i < subsymbolCarrierCount; i++) {
            NSUInteger frequency = lowestOscillationCountForSubsymbol + i;
            sampleValue += cosf(2.0 * M_PI * frequency * sampleIndex / kSamplesPerSynchronizationSubsymbol + carrierPhases[i]);
        }
        centralSynchronizationSymbol[sampleIndex] = sampleValue;
    }

    // Replicate symmetrically the subsignal to the rest of the symbol.
    for (NSUInteger sampleIndex = 0; sampleIndex < kSamplesPerSynchronizationSubsymbol; sampleIndex++) {
        centralSynchronizationSymbol[kSamplesPerSynchronizationSymbol - 1 - sampleIndex] = centralSynchronizationSymbol[sampleIndex];
    }

    // Perform FFT
    vDSP_Length log2SamplesPerSynchronizationSymbol = log2(kSamplesPerSynchronizationSymbol);
    FFTSetup fftSetup = vDSP_create_fftsetup(log2SamplesPerSynchronizationSymbol, kFFTRadix2);
    DSPSplitComplex fftData;
    fftData.realp = malloc(kSamplesPerSynchronizationSubsymbol * kAudioSampleSize);
    fftData.imagp = malloc(kSamplesPerSynchronizationSubsymbol * kAudioSampleSize);
    vDSP_ctoz((DSPComplex *)centralSynchronizationSymbol, 2, &fftData, 1, kSamplesPerSynchronizationSubsymbol);
    vDSP_fft_zrip(fftSetup, &fftData, 1, log2SamplesPerSynchronizationSymbol, kFFTDirection_Forward);

    // Filter out frequencies out of the allowed range.
    for (NSUInteger i = 0; i < 2 * lowestOscillationCountForSubsymbol; i++) {
        fftData.realp[i] = 0;
        fftData.imagp[i] = 0;
    }
    for (NSUInteger i = 2 * (lowestOscillationCountForSubsymbol + subsymbolCarrierCount - 1) + 1; i < kSamplesPerSynchronizationSubsymbol; i++) {
        fftData.realp[i] = 0;
        fftData.imagp[i] = 0;
    }

    // Perform IFFT.
    vDSP_fft_zrip(fftSetup, &fftData, 1, log2SamplesPerSynchronizationSymbol, kFFTDirection_Inverse);
    vDSP_ztoc(&fftData, 1, (DSPComplex *)centralSynchronizationSymbol, 2, kSamplesPerSynchronizationSubsymbol);

    // Normalize the subsymbol by dividing it by the maximum sample value.
    float maximumSampleAmplitude = 0.0;
    for (NSUInteger sampleIndex = 0; sampleIndex < kSamplesPerSynchronizationSymbol; sampleIndex++) {
        float value = fabsf(centralSynchronizationSymbol[sampleIndex]);
        if (value > maximumSampleAmplitude) {
            maximumSampleAmplitude = value;
        }
    }
    for (NSUInteger sampleIndex = 0; sampleIndex < kSamplesPerSynchronizationSymbol; sampleIndex++) {
        centralSynchronizationSymbol[sampleIndex] /= maximumSampleAmplitude;
    }

    // Fill the initial and final part of the symbol with the corresponding
    // faded periodic parts.
    for (NSUInteger sampleIndex = 0; sampleIndex < kOFDMSymbolExtremityFadingLength; sampleIndex++) {
        // Faded-in part.
        _synchronizationSymbol[sampleIndex] = centralSynchronizationSymbol[kSamplesPerSynchronizationSymbol - kOFDMSymbolExtremityFadingLength + sampleIndex] * 0.5 * (1 - cosf(2.0 * M_PI * 1.0/2.0 * sampleIndex/kOFDMSymbolExtremityFadingLength));
        // Faded-out part.
        _synchronizationSymbol[kSamplesPerSynchronizationSymbolWithFadedParts - kOFDMSymbolExtremityFadingLength + sampleIndex] = centralSynchronizationSymbol[sampleIndex] * 0.5 * (1 + cosf(2.0 * M_PI * 1.0/2.0 * (sampleIndex + 1)/kOFDMSymbolExtremityFadingLength));
    }
}

//------------------------------------------------------------------------------
#pragma mark - AMAudioPortModem
//------------------------------------------------------------------------------

- (void)audioPort:(AMAudioPort *)audioPort
didReceiveNewDataInCircularBuffer:(TPCircularBuffer *)circularBuffer
       sampleTime:(Float64)sampleTime {
    // Running on a grand central dispatch thread.

    if (listener) {
        // Get the tail of the circular buffer along with the number of bytes
        // available for reading.
        int32_t availableBytesToRead = 0;
        float *circularBufferTail = TPCircularBufferTail(circularBuffer, &availableBytesToRead);
        // Compute the number of samples available for reading from the circular
        // buffer.
        NSUInteger availableSamplesToRead = availableBytesToRead / kAudioSampleSize;
        
        if (availableSamplesToRead >= kSynchronizationSymbolFFTSize) {
            // Perform FFT transform.
            vDSP_ctoz((DSPComplex *)circularBufferTail, 2, &_synchronizationSymbolFFTData, 1, kSamplesPerSynchronizationSymbol);
            vDSP_fft_zrip(_synchronizationSymbolFFTSetup, &_synchronizationSymbolFFTData, 1, _log2SynchronizationSymbolFFTData, kFFTDirection_Forward);

            // Set lower frequencies to zero.
            NSUInteger lowestOscillationCount = ceilf(AMFrequencyToOscillationCount(kLowestSoundFrequency, kSynchronizationSymbolFFTSize));
            memset(_synchronizationSymbolFFTData.realp, 0, lowestOscillationCount * kAudioSampleSize);
            memset(_synchronizationSymbolFFTData.imagp, 0, lowestOscillationCount * kAudioSampleSize);

            // Set higher frequencies to zero.
            NSUInteger highestOscillationCount = lowestOscillationCount + floorf(AMFrequencyToOscillationCount((kCarrierCount - 1) * kCarrierFrequencySpacing, kSynchronizationSymbolFFTSize));
            memset(_synchronizationSymbolFFTData.realp + highestOscillationCount + 1, 0, (kSamplesPerSynchronizationSymbol - highestOscillationCount - 1) * kAudioSampleSize);
            memset(_synchronizationSymbolFFTData.imagp + highestOscillationCount + 1, 0, (kSamplesPerSynchronizationSymbol - highestOscillationCount - 1) * kAudioSampleSize);

            // Perform IFFT transform.
            vDSP_fft_zrip(_synchronizationSymbolFFTSetup, &_synchronizationSymbolFFTData, 1, _log2SynchronizationSymbolFFTData, kFFTDirection_Inverse);
            vDSP_ztoc(&_synchronizationSymbolFFTData, 1, (DSPComplex *)_filteredSynchronizationSymbolData, 2, kSamplesPerSynchronizationSymbol);

            // Data Recording
            static int sampleIndex=0;
//            static float *preIFFTRecordedData = nil;
//            static float *postIFFTRecordedData = nil;
//            if (sampleIndex > 4 * kSampleRate) {
//                printf("Pre IFFT\n");
//                for (NSUInteger i = 0; i < 4 * kSampleRate; i++) {
//                    printf("%f\n", preIFFTRecordedData[i]);
//                }
//                printf("\n\n\n\n\n\nPOST IFFT\n\n\n\n\n\n");
//                for (NSUInteger i = 0; i < 4 * kSampleRate; i++) {
//                    printf("%f\n", postIFFTRecordedData[i]);
//                }
//                exit(0);
//            }
//            // Pre IFFT Data recording for matlab inspection.
//            static BOOL allocatePreIFFTData=YES;
//            if (allocatePreIFFTData) {
//                preIFFTRecordedData = malloc(5 * kSampleRate * kAudioSampleSize);
//                allocatePreIFFTData = NO;
//            }
//            memcpy(preIFFTRecordedData + (unsigned int)(sampleIndex), circularBufferTail, 256 * kAudioSampleSize);
//            // Post IFFT Data recording for matlab inspection.
//            static BOOL allocatePostIFFTData=YES;
//            if (allocatePostIFFTData) {
//                postIFFTRecordedData = malloc(5 * kSampleRate * kAudioSampleSize);
//                allocatePostIFFTData = NO;
//            }
//            memcpy(postIFFTRecordedData + (unsigned int)(sampleIndex), _filteredSynchronizationSymbolData, 256 * kAudioSampleSize);

            // For each position in the first half of
            // `_filteredSynchronizationSymbolData`, compute the likelihood that
            // a synchronization symbol starts there.
            static float maxSignalStartLikelihood = -FLT_MAX;
            for (NSUInteger signalStart = 0; signalStart < kSamplesPerSynchronizationSymbol; signalStart++) {
                float signalStartLikelihood = 0;

                // Copy the first half of the synchronization symbol to a
                // different storage in order to subsequently reverse it.
                memcpy(_reversedFilteredSynchronizationSubsymbolData, _filteredSynchronizationSymbolData + signalStart, kSamplesPerSynchronizationSubsymbol * kAudioSampleSize);
                // Reverse the first half of the synchronization symbol.
                vDSP_vrvrs(_reversedFilteredSynchronizationSubsymbolData, 1, kSamplesPerSynchronizationSubsymbol);
                // Compute the scalar product between the 2 halves of the
                // synchronization symbol.
                vDSP_dotpr(_reversedFilteredSynchronizationSubsymbolData, 1, _filteredSynchronizationSymbolData + signalStart + kSamplesPerSynchronizationSubsymbol, 1, &signalStartLikelihood, kSamplesPerSynchronizationSubsymbol);
                // Compute difference between the 2 vectors.
                vDSP_vsub(_reversedFilteredSynchronizationSubsymbolData, 1, _filteredSynchronizationSymbolData + signalStart + kSamplesPerSynchronizationSubsymbol, 1, _reversedFilteredSynchronizationSubsymbolData, 1, kSamplesPerSynchronizationSubsymbol);
                float squaredNorm = 0;
                // Compute the squared norm of the difference between the 2
                // vectors.
                vDSP_svesq(_reversedFilteredSynchronizationSubsymbolData, 1, &squaredNorm, kSamplesPerSynchronizationSubsymbol);

                // Finally, compute the likelihood of the signal starting at
                // `signalStart`.
                signalStartLikelihood = signalStartLikelihood / sqrtf(squaredNorm);

                if (signalStartLikelihood > maxSignalStartLikelihood) {
                    maxSignalStartLikelihood = signalStartLikelihood;
                    printf("max likelihood = %f (%d)\n", maxSignalStartLikelihood, sampleIndex + signalStart + 1);
                }
            }
            sampleIndex += 256;
//            printf("%f\n", maxCorrelation);
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [[(ViewController *)[[UIApplication sharedApplication].delegate window].rootViewController label] setText:[NSString stringWithFormat:@"%f", roundf(maxSignalStartLikelihood)]];
//            });

            // Mark bytes as consumed.
            TPCircularBufferConsume(circularBuffer, kSamplesPerSynchronizationSymbol * kAudioSampleSize);
        }
    } else {
        TPCircularBufferConsume(circularBuffer, kAudioPacketSampleCount * kAudioSampleSize);
        if (self.firstTime) {
//            float *shit = malloc(44100 * kAudioSampleSize);
//            for (NSUInteger i=0;i < 44100;i++) {
//                shit[i] = cosf(2*M_PI*440*(float)i/44100.0);
//            }
            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+2*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+3*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+4*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+5*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+6*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+7*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+8*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+9*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+10*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+11*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+12*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+13*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+14*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+15*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+16*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+17*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+18*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+19*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+20*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+21*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+22*384];
//            [audioPort scheduleOutputData:_synchronizationSymbol sampleCount:kSamplesPerSynchronizationSymbolWithFadedParts startTime:sampleTime + 1*44100+23*384];
            self.firstTime = NO;
        }
    }

}

//------------------------------------------------------------------------------
#pragma mark - Deallocating
//------------------------------------------------------------------------------

- (void)dealloc {
    vDSP_destroy_fftsetup(self.synchronizationSymbolFFTSetup);
    free(_synchronizationSymbol);
    free(_synchronizationSymbolFFTData.realp);
    free(_synchronizationSymbolFFTData.imagp);
    free(_filteredSynchronizationSymbolData);
    free(_reversedFilteredSynchronizationSubsymbolData);
}

@end
