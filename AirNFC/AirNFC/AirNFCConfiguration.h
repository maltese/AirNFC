//
//  AirNFCConstants.h
//  AirNFC
//
//  Created by Matteo Cortonesi on 12/16/12.
//  Copyright (c) 2012 Matteo Cortonesi. All rights reserved.
//

#import <Foundation/Foundation.h>

double const static kSampleRate = 44100.0;

// Size of 1 audio sample. Currently corresponds to the size of a linear PCM
// audio sample, as this is the audio format currently used.
NSUInteger const static kAudioSampleSize = sizeof(float);

// Must be a power of 2.
NSUInteger const static kSamplesPerOFDMSymbol = 2048;

NSUInteger const static kLowestOscillationCountForOFDMSymbol = 789;

NSUInteger const static kCarrierCount = 100;

// The lowest sound frequency used to transmit data [Hz].
double const static kLowestSoundFrequency = kLowestOscillationCountForOFDMSymbol * (kSampleRate / kSamplesPerOFDMSymbol);

// The highest sound frequency used to transmit data [Hz].
double const static kHighestSoundFrequency = kLowestSoundFrequency + (kCarrierCount - 1) * kSampleRate / kSamplesPerOFDMSymbol;

// The carrier spacing is implicitly always 1 oscillation per OFDM symbol. The
// following constant is the carrier spacing in Hertz.
double const static kCarrierFrequencySpacing = 1 * kSampleRate / kSamplesPerOFDMSymbol;

NSUInteger const static kCyclicPrefixLength = 256;

NSUInteger const static kOFDMSymbolExtremityFadingLength = 64;

NSUInteger const static kSamplesPerOFDMSymbolWithCyclicPrefix = kCyclicPrefixLength + kSamplesPerOFDMSymbol;

NSUInteger const static kAudioPacketSampleCount = 256;