//
//  VideoFileController.m
//  Puttio
//
//  Created by orta therox on 26/05/2012.
//  Copyright (c) 2012 ortatherox.com. All rights reserved.
//

#import "VideoFileController.h"
#import "FileInfoViewController.h"
#import "AFNetworking.h"
#import "LocalFile.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import "MoviePlayer.h"
#import "FileSizeUtils.h"
#import "ConvertToMP4Process.h"

@implementation VideoFileController {
    BOOL _isMP4;
    BOOL _MP4Ready;
    BOOL requested;
}

+ (BOOL)fileSupportedByController:(File *)aFile {
    NSSet *fileTypes = [NSSet setWithObjects: @"avi", @"mv4", @"m4v", @"mov", @"wmv", @"mkv", @"mp4", @"rmvb", nil];
    if ([fileTypes containsObject:aFile.extension]) {
        return YES;
    }
    return NO;
}

- (void)setFile:(File *)aFile {
    _file = aFile;
    [self.infoController disableButtons];

    [[PutIOClient sharedClient] getInfoForFile:_file :^(id userInfoObject) {
        if (![userInfoObject isMemberOfClass:[NSError class]]) {
            fileSize = [[userInfoObject valueForKeyPath:@"size"][0] intValue];
            self.infoController.titleLabel.text = [userInfoObject valueForKeyPath:@"name"][0]; 
            self.infoController.fileSizeLabel.text = unitStringFromBytes(fileSize);
            [self.infoController hideProgress];
            
            NSString *contentType = [userInfoObject valueForKeyPath:@"content_type"][0];
            if ([contentType isEqualToString:@"video/mp4"]) {
                _isMP4 = YES;
                [self.infoController enableButtons];
            }else{
                [self getMP4Info];
            }
        }
    }];
}

- (NSString *)descriptiveTextForFile {
    return @"Stream or Download Video";
}

- (NSString *)primaryButtonText {
    return @"Stream";
}

- (void)primaryButtonAction:(id)sender {
    if (_isMP4) {
        [MoviePlayer streamMovieAtPath:[NSString stringWithFormat:@"https://put.io/v2/files/%@/stream", _file.id]];
    }else{
        [MoviePlayer streamMovieAtPath:[NSString stringWithFormat:@"https://put.io/v2/files/%@/mp4/stream", _file.id]];
    }
    
    [self markFileAsViewed];
}

- (BOOL)supportsSecondaryButton {
    return YES;
}

- (NSString *)secondaryButtonText {
    return @"Download";
    [self markFileAsViewed];
}

- (void)secondaryButtonAction:(id)sender {
    self.infoController.additionalInfoLabel.text = @"Downloading";
    self.infoController.secondaryButton.enabled = NO;
    self.infoController.primaryButton.enabled = NO;

    [self downloadFile];
}

- (void)downloadFile {
    NSString *requestURL;
    if (_isMP4) {
        requestURL = [NSString stringWithFormat:@"https://put.io/v2/files/%@/download", _file.id];   
    }else{
        requestURL = [NSString stringWithFormat:@"https://put.io/v2/files/%@/mp4/download", _file.id];   
    }

    [self downloadFileAtPath:requestURL WithCompletionBlock:^(AFHTTPRequestOperation *operation, id responseObject) {
        self.infoController.additionalInfoLabel.text = @"Saving file";
        
        // Save it
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = paths[0];
        NSString *filePath = [documentsDirectory stringByAppendingPathComponent:_file.id];
        NSString *fullPath = [NSString stringWithFormat:@"%@.mp4", filePath];
        [operation.responseData writeToFile:fullPath atomically:YES];

        
        // Make sure its not in iCloud
        NSURL *fileUrl = [NSURL fileURLWithPath:fullPath];
        assert([[NSFileManager defaultManager] fileExistsAtPath: [fileUrl path]]);
        
        NSError *error = nil;
        BOOL success = [fileUrl setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error];
        if(!success){
            NSLog(@"Error excluding %@ from backup %@", fileUrl, error);
        }
        
        // Give it a localfile core data entity
        LocalFile *localFile = [LocalFile localFileWithFile:_file];
        [[localFile managedObjectContext] save:nil];
        
        // Set the UI state 
        self.infoController.additionalInfoLabel.text = @"Downloaded - It's in your media library!";
        [self.infoController enableButtons];
        [self.infoController hideProgress];

        self.infoController.progressInfoHidden = YES;
        self.infoController.secondaryButton.enabled = YES;
        self.infoController.primaryButton.enabled = NO;
        
    } andFailureBlock:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"%@", NSStringFromSelector(_cmd));
        NSLog(@"mega fail");
        NSLog(@"request %@", operation.request.URL);
        
        self.infoController.additionalInfoLabel.text = @"Download failed!";
        self.infoController.progressView.hidden = YES;
        self.infoController.secondaryButton.enabled = NO;
        self.infoController.primaryButton.enabled = YES;
    }];
    
}

- (void)getMP4Info {
    if (!requested) {
        [ConvertToMP4Process processWithFile:_file];
        requested = YES;
    }

    [[PutIOClient sharedClient] getMP4InfoForFile:_file :^(id userInfoObject) {
        if (![userInfoObject isMemberOfClass:[NSError class]]) {
            
            NSString *status = [userInfoObject valueForKeyPath:@"mp4.status"];
            _MP4Ready = NO;
            
            if ([status isEqualToString:@"COMPLETED"]) {
                _MP4Ready = YES;
                [self.infoController enableButtons];
            }
            
            if ([status isEqualToString:@"NOT_AVAILABLE"]) {
                self.infoController.additionalInfoLabel.text = @"Requested an iPad version (this takes a *very* long time.)";
                [[PutIOClient sharedClient] requestMP4ForFile:_file];
                [self performSelector:@selector(getMP4Info) withObject:self afterDelay:1];
            }
            
            if ([status isEqualToString:@"CONVERTING"]) {
                self.infoController.additionalInfoLabel.text = @"Converting to iPad version.";
                if ([userInfoObject valueForKeyPath:@"mp4.percent_done"] != [NSNull null]) {
                    [self.infoController showProgress];
                    self.infoController.progressView.hidden = NO;
                    self.infoController.progressView.progress = [[userInfoObject valueForKeyPath:@"mp4.percent_done"] floatValue] / 100;
                }
                [self performSelector:@selector(getMP4Info) withObject:self afterDelay:1];                    
            }
        }
    }];
}

@end
