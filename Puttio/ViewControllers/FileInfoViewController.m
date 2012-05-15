//
//  FileInfoViewController.m
//  Puttio
//
//  Created by orta therox on 01/04/2012.
//  Copyright (c) 2012 ortatherox.com. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import "FileInfoViewController.h"
#import "UIImageView+AFNetworking.h"
#import "MoviePlayer.h"
#import "FileSizeUtils.h"

#include <sys/param.h>  
#include <sys/mount.h>  

@interface FileInfoViewController() {
    File *_item;
    NSInteger fileSize;
    BOOL fileDownloaded;
    BOOL stopRefreshing;
    
    BOOL _hasMP4;
}
@end


@implementation FileInfoViewController 
@synthesize titleLabel;
@synthesize additionalInfoLabel;
@synthesize fileSizeLabel;
@synthesize streamButton;
@synthesize downloadButton;
@synthesize thumbnailImageView;
@synthesize progressView;
@dynamic item;
@dynamic hasMP4;

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    streamButton.enabled = NO;
    progressView.hidden = YES;
    fileSizeLabel.text = @"";
    titleLabel.text = @"";
    additionalInfoLabel.text = @"";
}

- (void)setItem:(File *)item {
    if (![item conformsToProtocol:@protocol(ORDisplayItemProtocol)]) {
        [NSException raise:@"File Info item should conform to ORDisplayItemProtocol" format:@"File Info item should conform to ORDisplayItemProtocol"];
    }
    NSObject <ORDisplayItemProtocol> *object = item;
    titleLabel.text = object.displayName;
    _item = item;
    [thumbnailImageView setImageWithURL:[NSURL URLWithString:[PutIOClient appendOauthToken:object.screenShotURL]]];

    [self getMP4Info];
    
    [self getFileInfo];
}

- (void)getFileInfo {
    [[PutIOClient sharedClient] getInfoForFile:_item :^(id userInfoObject) {
        if (![userInfoObject isMemberOfClass:[NSError class]]) {
            NSString *contentType = [[userInfoObject valueForKeyPath:@"content_type"] objectAtIndex:0];
            
            titleLabel.text = [[userInfoObject valueForKeyPath:@"name"] objectAtIndex:0]; 
            fileSize = [[[userInfoObject valueForKeyPath:@"size"] objectAtIndex:0] intValue];
            fileSizeLabel.text = unitStringFromBytes(fileSize);

            additionalInfoLabel.text = contentType;            
        }
    }];
}

- (void)getMP4Info {
    [[PutIOClient sharedClient] getMP4InfoForFile:_item :^(id userInfoObject) {
        if (![userInfoObject isMemberOfClass:[NSError class]]) {
            NSString *status = [userInfoObject valueForKeyPath:@"mp4.status"];

            self.hasMP4 = NO;
            if ([status isEqualToString:@"COMPLETED"]) {
                self.hasMP4 = YES;
            }
            
            if ([status isEqualToString:@"NotAvailable"]) {
                additionalInfoLabel.text = @"Requested an iPad version (this takes a *very* long time.)";
                [[PutIOClient sharedClient] requestMP4ForFile:_item];
                [self performSelector:@selector(getMP4Info) withObject:self afterDelay:30];
            }
            
            if ([status isEqualToString:@"CONVERTING"]) {
                additionalInfoLabel.text = @"Converting to iPad version (this takes a *very* long time.)";
                if ([userInfoObject valueForKeyPath:@"mp4.percent_done"] != [NSNull null]) {
                    progressView.hidden = NO;
                    progressView.progress = [[userInfoObject valueForKeyPath:@"mp4.percent_done"] floatValue] / 100;
                }
                if (!stopRefreshing) {
                    #warning this loop can run multiple times 
                    [self performSelector:@selector(getMP4Info) withObject:self afterDelay:1];                    
                }
            }
        }
    }];
}

- (void)setHasMP4:(BOOL)hasMP4 {
    _hasMP4 = hasMP4;
    streamButton.enabled = hasMP4;
    downloadButton.enabled = hasMP4;
}

- (BOOL)hasMP4 {
    return _hasMP4;
}

- (id)item {
    return _item;
}

- (void)viewDidUnload {
    [self setTitleLabel:nil];
    [self setThumbnailImageView:nil];
    [self setAdditionalInfoLabel:nil];
    [self setStreamButton:nil];
    [self setProgressView:nil];
    stopRefreshing = YES;
    [self setFileSizeLabel:nil];
    [self setDownloadButton:nil];
    [super viewDidUnload];
}

- (IBAction)backButton:(id)sender {
    
}

- (IBAction)streamTapped:(id)sender {
    if (_hasMP4) {
        [MoviePlayer streamMovieAtPath:[NSString stringWithFormat:@"http://put.io/v2/files/%@/mp4/stream", _item.id]];
    }
}

- (IBAction)downloadTapped:(id)sender {
    self.progressView.hidden = NO;
    self.progressView.progress = 0;
    self.additionalInfoLabel.text = @"Downloading";
    self.downloadButton.enabled = NO;
    self.streamButton.enabled = NO;
    [self downloadItem];
}

- (void)downloadItem {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);  
    struct statfs tStats;  
    statfs([[paths lastObject] cString], &tStats);  
    uint64_t totalSpace = tStats.f_bavail * tStats.f_bsize;  
        
    NSString *requestURL = [NSString stringWithFormat:@"http://put.io/v2/files/%@/mp4/download", _item.id];
    
    if (fileSize < totalSpace) {
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[PutIOClient appendOauthToken:requestURL]]];
        AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];

        [operation setDownloadProgressBlock:^(NSInteger bytesRead, NSInteger totalBytesRead, NSInteger totalBytesExpectedToRead) {
            progressView.progress = (float)totalBytesRead/totalBytesExpectedToRead;
        }];
        
        [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            additionalInfoLabel.text = @"Moving to Photos app";
            
            NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:_item.id];
            NSString *fullPath = [NSString stringWithFormat:@"%@.mp4", filePath];
            
            [operation.responseData writeToFile:fullPath atomically:YES];
            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];            
            NSURL *filePathURL = [NSURL fileURLWithPath:fullPath isDirectory:NO];
            if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:filePathURL]) {
                [library writeVideoAtPathToSavedPhotosAlbum:filePathURL completionBlock:^(NSURL *assetURL, NSError *error){
                    if (error) {
                        // TODO: error handling
                        NSLog(@"fail bail");

                    } else {
                        // TODO: success handling
                        NSLog(@"success kid");
                        self.additionalInfoLabel.text = @"Downloaded - it's available in Photos";
                        fileDownloaded = YES;
                    }
                }];
            }
            progressView.hidden = YES;
            self.downloadButton.enabled = YES;
            self.streamButton.enabled = NO;
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"%@", NSStringFromSelector(_cmd));
            NSLog(@"mega fail");
            NSLog(@"request %@", operation.request.URL);
            
            self.additionalInfoLabel.text = @"Download failed!";
            progressView.hidden = YES;
            self.downloadButton.enabled = YES;
            self.streamButton.enabled = NO;
        }];
        [operation start];
        
    }else {        
        NSString *message = [NSString stringWithFormat:@"Your iPad doesn't have enough free disk space to download."];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Not enough disk space" message:message delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        [alert show];
    }
}

@end
