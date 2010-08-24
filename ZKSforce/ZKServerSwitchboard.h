// Copyright (c) 2010 Rick Fillion
// Code based on Chris Farber's CRServerSwitchboard
//
// Permission is hereby granted, free of charge, to any person obtaining a 
// copy of this software and associated documentation files (the "Software"), 
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense, 
// and/or sell copies of the Software, and to permit persons to whom the 
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included 
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN 
// THE SOFTWARE.
//

#import <Foundation/Foundation.h>

@class ZKUserInfo;

@interface ZKServerSwitchboard : NSObject {
    CFMutableDictionaryRef connections;
    CFMutableDictionaryRef connectionsData;
    
    NSString    *apiUrl;
    
	NSString	*clientId;	
	NSString	*sessionId;
	NSDate		*sessionExpiry;
    ZKUserInfo	*userInfo;
    //BOOL        savesUsernameAndPasswordInKeychain;
	NSUInteger  preferredApiVersion;
    
    BOOL        updatesMostRecentlyUsed;
}

@property (nonatomic, copy) NSString *apiUrl;
@property (nonatomic, copy) NSString *clientId;
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, retain) ZKUserInfo *userInfo;
//@property (nonatomic, assign) BOOL savesUsernameAndPasswordInKeychain;
@property (nonatomic, assign) BOOL updatesMostRecentlyUsed;

+ (NSString *)baseURL;
+ (ZKServerSwitchboard *)switchboard;
- (NSString *)authenticationUrl;
- (void)authenticateWithUsername:(NSString *)username password:(NSString *)password target:(id)target selector:(SEL)selector;
- (void)query:(NSString *)soqlQuery target:(id)target selector:(SEL)selector context:(id)context;
- (void)create:(NSArray *)objects target:(id)target selector:(SEL)selector context:(id)context;
- (void)update:(NSArray *)objects target:(id)target selector:(SEL)selector context:(id)context;

@end