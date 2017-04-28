// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


@import CoreGraphics;
@import MobileCoreServices;
@import ImageIO;
@import WireUtilities;
@import WireTransport;

#import "ZMMessage+Internal.h"
#import "NSManagedObjectContext+zmessaging.h"
#import "ZMConversation+Internal.h"
#import "ZMConversation+Transport.h"
#import "ZMClientMessage.h"
#import "WireDataModel/WireDataModel-Swift.h"

#pragma mark - Image message

@interface ZMImageMessage ()

@property (nonatomic) BOOL isAnimatedGIF;
@property (nonatomic) NSString *imageType;

@end


@implementation ZMImageMessage

+ (NSArray *)sortDescriptorsForUpdating;
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSSortDescriptor *conversationSD in ZMConversation.sortDescriptorsForUpdating) {
        NSString *key = [NSString stringWithFormat:@"%@.%@", ZMMessageConversationKey, conversationSD.key];
        [result addObject:[NSSortDescriptor sortDescriptorWithKey:key ascending:conversationSD.ascending]];
    }
    [result addObject:[NSSortDescriptor sortDescriptorWithKey:ZMMessageServerTimestampKey ascending:NO]];
    return result;
}

@dynamic mediumDataLoaded;
@dynamic originalDataProcessed;

@dynamic imageType;
@dynamic isAnimatedGIF;

+ (NSString *)imageTypeForData:(NSData *)data
{
    if(data.length == 0) {
        return nil;
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) data, NULL);
    VerifyReturnNil(source != NULL);
    NSString *type = CFBridgingRelease(CGImageSourceGetType(source));
    CFRelease(source);
    return type;
}

- (NSData *)imageData;
{
    return self.mediumData ?: self.originalImageData;
}

- (NSString *)imagePreviewDataIdentifier;
{
    return (self.previewData == nil) ? nil : self.nonce.UUIDString;
}

- (NSString *)imageDataIdentifier;
{
    NSUUID *identifier = self.mediumRemoteIdentifier;
    if (identifier != nil) {
        return identifier.UUIDString;
    } else if (self.imageData) {
        return [NSString stringWithFormat:@"orig-%@", self.nonce.UUIDString];
    }
    return nil;
}

+ (NSString *)entityName;
{
    return @"ImageMessage";
}

- (NSUUID *)mediumRemoteIdentifier;
{
    return [self transientUUIDForKey:ZMMessageMediumRemoteIdentifierKey];
}

- (void)setMediumRemoteIdentifier:(NSUUID *)mediumRemoteIdentifier;
{
    [self setTransientUUID:mediumRemoteIdentifier forKey:ZMMessageMediumRemoteIdentifierKey];
}

+ (NSSet *)keyPathsForValuesAffectingMediumRemoteIdentifier
{
    return [NSSet setWithObject:ZMMessageMediumRemoteIdentifierDataKey];
}

- (CGSize)originalSize;
{
    return [self transientCGSizeForKey:ZMMessageOriginalSizeKey];
}

- (void)setOriginalSize:(CGSize)originalSize;
{
    [self setTransientCGSize:originalSize forKey:ZMMessageOriginalSizeKey];
}

- (NSData *)mediumData
{
    return [self imageDataForFormat:ZMImageFormatMedium];
}

- (NSData *)previewData
{
    return [self imageDataForFormat:ZMImageFormatPreview];
}

//For image messages we have two events - for preview and medium format
//To preserve messages order we need to keep the earliest serverTimestamp of these two events
- (void)updateTimestamp:(NSDate *)timestamp isUpdatingExistingMessage:(BOOL)isUpdate
{
    if (isUpdate) {
        self.serverTimestamp = [NSDate earliestOfDate:self.serverTimestamp and:timestamp];
    } else if (timestamp != nil) {
        self.serverTimestamp = timestamp;
    }
}

- (id<ZMImageMessageData>)imageMessageData
{
    return self;
}

- (void)removeMessageClearingSender:(BOOL)clearingSender
{
    [self.managedObjectContext.zm_imageAssetCache deleteAssetData:self.nonce format:ZMImageFormatPreview encrypted:NO];
    [self.managedObjectContext.zm_imageAssetCache deleteAssetData:self.nonce format:ZMImageFormatMedium encrypted:NO];
    [self.managedObjectContext.zm_imageAssetCache deleteAssetData:self.nonce format:ZMImageFormatOriginal encrypted:NO];

    self.originalSize = CGSizeZero;
    self.mediumRemoteIdentifier = nil;

    [super removeMessageClearingSender:clearingSender];
}

@end



@implementation ZMImageMessage (Internal)

@dynamic mediumDataLoaded;
@dynamic originalDataProcessed;


+ (instancetype)createOrUpdateMessageFromUpdateEvent:(ZMUpdateEvent __unused *)updateEvent
                              inManagedObjectContext:(NSManagedObjectContext __unused *)moc
                                      prefetchResult:(ZMFetchRequestBatchResult __unused *)prefetchResult
{
    return nil;
}

- (BOOL)isInlineForFormat:(ZMImageFormat)format
{
    switch (format) {
        case ZMImageFormatPreview:
            return YES;
            
        case ZMImageFormatMedium:
            return NO;
            
        case ZMImageFormatOriginal:
        case ZMImageFormatProfile:
        case ZMImageFormatInvalid:
            RequireString(NO, "Invalid image format in ZMMessage: %ld", (long)format);
            return NO;
    }
}

- (BOOL)isPublicForFormat:(ZMImageFormat __unused)format
{
    return NO;
}

- (BOOL)isUsingNativePushForFormat:(ZMImageFormat)format
{
    switch (format) {
        case ZMImageFormatMedium:
            return YES;
            
        case ZMImageFormatPreview:
        case ZMImageFormatProfile:
            return NO;
            
        case ZMImageFormatOriginal:
        case ZMImageFormatInvalid:
            RequireString(NO, "Invalid image format: %ld", (long)format);
            return NO;
    }
}

- (void)setImageData:(NSData *)imageData forFormat:(ZMImageFormat)format properties:(ZMIImageProperties * __unused)properties;
{
    if (imageData == nil) {
        [self.managedObjectContext.zm_imageAssetCache deleteAssetData:self.nonce format:format encrypted:NO];
    }
    else {
        [self.managedObjectContext.zm_imageAssetCache storeAssetData:self.nonce format:format encrypted:NO data:imageData];
        switch (format) {
            case ZMImageFormatMedium:
                self.mediumDataLoaded = YES;
                self.isAnimatedGIF = [ZMImageMessage isDataAnimatedGIF:imageData];
                self.imageType = [ZMImageMessage imageTypeForData:imageData];
                
                break;
            case ZMImageFormatPreview:
                break;
            case ZMImageFormatOriginal:
                self.isAnimatedGIF = [ZMImageMessage isDataAnimatedGIF:imageData];
                break;
            default:
                RequireString(NO, "Invalid image format in ZMMessage: %ld", (long)format);
                break;
        }
    }
}

- (NSData *)imageDataForFormat:(ZMImageFormat)format
{
    switch (format) {
        case ZMImageFormatPreview:
        case ZMImageFormatMedium:
        case ZMImageFormatOriginal:
            return [self.managedObjectContext.zm_imageAssetCache assetData:self.nonce format:format encrypted:NO];
        default:
            return nil;
    }
}

- (CGSize)originalImageSize
{
    return self.originalSize;
}

- (NSData *)originalImageData
{
    return [self imageDataForFormat:ZMImageFormatOriginal];
}

- (void)setOriginalImageData:(NSData *)originalImageData
{
    [self setImageData:originalImageData forFormat:ZMImageFormatOriginal properties:nil];
}

- (void)setMediumData:(NSData *)mediumData
{
    [self setImageData:mediumData forFormat:ZMImageFormatMedium properties:nil];
}

- (void)setPreviewData:(NSData *)previewData
{
    [self setImageData:previewData forFormat:ZMImageFormatPreview properties:nil];
}

- (NSOrderedSet *)requiredImageFormats;
{
    return [NSOrderedSet orderedSetWithObjects:@(ZMImageFormatPreview), @(ZMImageFormatMedium), nil];
}

- (void)processingDidFinish;
{
    [self setImageData:nil forFormat:ZMImageFormatOriginal properties:nil];
    
    self.originalDataProcessed = YES;
    [self.managedObjectContext enqueueDelayedSave];
}

@end