//
//  OAuthViewController.m
//  Puttio
//
//  Created by orta therox on 23/03/2012.
//  Copyright (c) 2012 ortatherox.com. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "OAuthViewController.h"
#import "PutIOOAuthHelper.h"

@implementation OAuthViewController
@synthesize usernameTextfield, passwordTextfield;
@synthesize warningLabel;
@synthesize loginViewWrapper, loginButton;
@synthesize authHelper;
@synthesize activityView;
@synthesize delegate;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupShadow];
    self.warningLabel.text = @"";
}

- (void)setupShadow {
    self.loginViewWrapper.clipsToBounds = NO;
    
    CALayer *layer = self.loginViewWrapper.layer;
    layer.masksToBounds = NO;
    layer.shadowOffset = CGSizeZero;
    layer.shadowColor = [[UIColor blackColor] CGColor];
    layer.shadowRadius = 20;
    layer.shadowOpacity = 0.15;
}

- (void)viewDidUnload {
    [self setUsernameTextfield:nil];
    [self setPasswordTextfield:nil];
    [self setWarningLabel:nil];
    [self setLoginViewWrapper:nil];
    [self setLoginButton:nil];
    [self setActivityView:nil];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return YES;
}

- (IBAction)loginPressed:(id)sender {
    [self.loginButton setEnabled:NO];
    [self.usernameTextfield setEnabled:NO];
    [self.passwordTextfield setEnabled:NO];
    [self.activityView startAnimating];
    self.warningLabel.text = @"";
    
    [authHelper loginWithUsername:usernameTextfield.text andPassword:passwordTextfield.text];
}

- (void)authHelperDidLogin:(PutIOOAuthHelper *)helper {
    if([delegate respondsToSelector:@selector(authorizationDidFinishWithController:)]){
        [delegate authorizationDidFinishWithController:self];
    }
}

- (void)authHelperLoginFailedWithDesription:(NSString *)errorDescription {
    self.warningLabel.text = errorDescription;
    [self.loginButton setEnabled:YES];
    [self.usernameTextfield setEnabled:YES];
    [self.passwordTextfield setEnabled:YES];
    [self.activityView stopAnimating];
}

@end
