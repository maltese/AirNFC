//
//  AMDeviceDiscovererModem.h
//  AirNFC
//
//  Created by Matteo Cortonesi on 2/6/13.
//  Copyright (c) 2013 Matteo Cortonesi. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AMAudioPort.h"

@protocol AMDeviceDiscovererModemDelegate;

@interface AMDeviceDiscovererModem : NSObject <AMAudioPortModem>

@property (nonatomic, weak) id <AMDeviceDiscovererModemDelegate> delegate;

@end

@protocol AMDeviceDiscovererModemDelegate <NSObject>

@optional

- (void)deviceDiscovererModemDidDiscoverDevice:(AMDeviceDiscovererModem *)deviceDiscovererModem;

@end