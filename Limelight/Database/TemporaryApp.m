//
//  TemporaryApp.m
//  Moonlight
//
//  Created by Cameron Gutman on 9/30/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "TemporaryApp.h"

@implementation TemporaryApp

- (NSComparisonResult)compareName:(TemporaryApp *)other {
    return [self.name caseInsensitiveCompare:other.name];
}

- (NSUInteger)hash {
    return [self.host.uuid hash] * 31 + [self.id intValue];
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[TemporaryApp class]]) {
        return NO;
    }

    TemporaryApp *other = (TemporaryApp *)object;
    return [self.host.uuid isEqualToString:other.host.uuid] &&
           [self.id isEqualToString:other.id];
}

@end
