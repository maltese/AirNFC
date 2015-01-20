//
//  main.m
//  test
//
//  Created by Matteo Cortonesi on 11/21/12.
//  Copyright (c) 2012 Avaloq Evolution AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#import "data.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        int const length = 4096;
        int const carriers = 200;
                
        // convert intData into floats
        float *data = (float *)intData;
        
        float phases[carriers];
        for (int i = 0; i < carriers; i++) {
            phases[i] = (float)rand()/(float)RAND_MAX * 2.0 * M_PI - M_PI;
        }
        
        float bits[carriers];
        for (int i = 0; i < carriers; i++) {
            bits[i] = roundf((float)rand()/(float)RAND_MAX);
        }
        
        vDSP_Length log2length = (int)log2f(length);
        FFTSetup setup = vDSP_create_fftsetup(log2length, kFFTRadix2);
        DSPSplitComplex splitComplex;
        splitComplex.realp = malloc(sizeof(float) * length / 2);
        splitComplex.imagp = malloc(sizeof(float) * length / 2);

        vDSP_ctoz((DSPComplex *)data, 2, &splitComplex, 1, length / 2);
        vDSP_fft_zrip(setup, &splitComplex, 1, log2length, kFFTDirection_Forward);
        
        float phaseShift = 0;
        for (int i = 0; i < length / 2; i++) {
            float real = splitComplex.realp[i];
            float imag = splitComplex.imagp[i];
            float norm = sqrtf(real*real + imag*imag);
            float phase = atan2f(imag, real);
            int bit = 0;
            if ((i >= 1579) && (i % 2 == 1)) {
                phaseShift = phases[i - 1579] - phase;
            }
//            if (i == 1579) {
//                phaseShift = phases[0] - phase;
//            }
            phase += phaseShift;
            if (phase > M_PI) {
                phase -= 2.0 * M_PI;
            } else if (phase < -M_PI) {
                phase += 2.0 * M_PI;
            }
            
            float phaseError = 0;
            if (1579 <= i && i <= 1778) {
                bit = bits[i - 1579];
                phaseError = fabsf(phases[i - 1579] - phase);
                if (phaseError > M_PI) {
                    phaseError = fabs(phaseError - 2.0 * M_PI);
                }
            }

            
            printf("f%d: a=%f (bit=%d) p=%f (e=%f)\n", i, norm, bit, phase, phaseError);
        }
    }
    return 0;
}

