//
/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCUserDefaults.h"

#import "NCAppBranding.h"
#import "NCKeyChainController.h"

@implementation NCUserDefaults

NSString * const kNCPreferredCameraFlashMode    = @"ncPreferredCameraFlashMode";
NSString * const kNCBackgroundBlurEnabled       = @"ncBackgroundBlurEnabled";
NSString * const kNCIncludeCallsInRecents       = @"ncIncludeCallsInRecents";
NSString * const kNCPreferredCallViewMode       = @"ncPreferredCallViewMode";
NSString * const kNCSpeakerViewStripeHidden     = @"ncSpeakerViewStripeHidden";
NSString * const kNCMediaUploadMode             = @"ncMediaUploadMode";

+ (NSUserDefaults *)sharedAppGroupDefaults
{
    static NSUserDefaults *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:groupIdentifier];
        if (!defaults) {
            defaults = [NSUserDefaults standardUserDefaults];
        }
    });
    return defaults;
}

+ (void)setPreferredCameraFlashMode:(NSInteger)flashMode
{
    [[NSUserDefaults standardUserDefaults] setObject:@(flashMode) forKey:kNCPreferredCameraFlashMode];
}

+ (NSInteger)preferredCameraFlashMode
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:kNCPreferredCameraFlashMode] integerValue];
}

+ (void)setBackgroundBlurEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setObject:@(enabled) forKey:kNCBackgroundBlurEnabled];
}

+ (BOOL)backgroundBlurEnabled
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:kNCBackgroundBlurEnabled] boolValue];
}

+ (void)setIncludeCallsInRecentsEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setObject:@(enabled) forKey:kNCIncludeCallsInRecents];
}

+ (BOOL)includeCallsInRecents
{
    id includeCallsInRecentsObject = [[NSUserDefaults standardUserDefaults] objectForKey:kNCIncludeCallsInRecents];
    if (includeCallsInRecentsObject == nil) {
        [self setIncludeCallsInRecentsEnabled:YES];
        return YES;
    }

    return [includeCallsInRecentsObject boolValue];
}

+ (void)setPreferredCallViewMode:(NSString *)mode
{
    [[NSUserDefaults standardUserDefaults] setObject:mode forKey:kNCPreferredCallViewMode];
}

+ (NSString * _Nullable)preferredCallViewMode
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kNCPreferredCallViewMode];
}

+ (void)setSpeakerViewStripeHidden:(BOOL)hidden
{
    [[NSUserDefaults standardUserDefaults] setObject:@(hidden) forKey:kNCSpeakerViewStripeHidden];
}

+ (BOOL)speakerViewStripeHidden
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:kNCSpeakerViewStripeHidden] boolValue];
}

+ (void)setMediaUploadMode:(NSInteger)mode
{
    // Main app reads standard defaults. Mirror to App Group for Share Extension when entitled.
    [[NSUserDefaults standardUserDefaults] setObject:@(mode) forKey:kNCMediaUploadMode];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[self sharedAppGroupDefaults] setObject:@(mode) forKey:kNCMediaUploadMode];
}

+ (NSInteger)mediaUploadMode
{
    id modeObject = [[NSUserDefaults standardUserDefaults] objectForKey:kNCMediaUploadMode];
    if (modeObject == nil) {
        modeObject = [[self sharedAppGroupDefaults] objectForKey:kNCMediaUploadMode];
    }
    if (modeObject == nil) {
        // MediaUploadModeAutomatic
        return 1;
    }

    return [modeObject integerValue];
}

@end
