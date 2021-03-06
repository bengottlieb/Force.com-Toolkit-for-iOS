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

#import "ZKServerSwitchboard+Private.h"
#import "ZKParser.h"
#import "ZKSoapException.h"
#import "NSObject+Additions.h"

static NSString *SOAP_NS = @"http://schemas.xmlsoap.org/soap/envelope/";


@implementation ZKServerSwitchboard (Private)


- (void)_sendRequestWithData:(NSString *)payload
                      target:(id)target
                    selector:(SEL)sel
{
    [self _sendRequestWithData:payload
                        target:target
                      selector:sel
                       context:nil];
}

- (void)_sendRequestWithData:(NSString *)payload
                      target:(id)target
                    selector:(SEL)sel
                     context:(id)context
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self apiUrl]]];
	[request setHTTPMethod:@"POST"];
	[request addValue:@"text/xml; charset=UTF-8" forHTTPHeaderField:@"content-type"];	
	[request addValue:@"\"\"" forHTTPHeaderField:@"SOAPAction"];
	NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
	[request setHTTPBody:data];
    
	if(self.logXMLInOut) {
		NSLog(@"OutputHeaders:\n%@", [request allHTTPHeaderFields]);
		NSLog(@"OutputBody:\n%@", payload);
	}
    
    [self _sendRequest:request target:target selector:sel context:context];
}

- (void)_sendRequest:(NSURLRequest *)aRequest
              target:(id)target
            selector:(SEL)sel
             context:(id)context
{
    NSURL *requestURL = [aRequest URL];
    NSURLConnection *connection = [[[NSURLConnection alloc] initWithRequest:aRequest delegate:self] autorelease];
    if (!connection)
    {
        NSError *error = [NSError errorWithDomain:@"ZKSwitchboardError"
                                             code:1
                                         userInfo:nil];
		[target performSelector: sel withObject: nil withObject: error withObject: context];
        return;
    }
    
    CFDictionarySetValue(connectionsData, connection, [NSMutableData data]);
    
    NSValue *selector = [NSValue value: &sel withObjCType: @encode(SEL)];
    NSMutableDictionary *targetInfo =
    [NSMutableDictionary dictionaryWithObjectsAndKeys:
     selector, @"selector",
     target, @"target",
     context ? context: [NSNull null], @"context",
     nil];
    
    if (requestURL)
    {
        [targetInfo setObject:requestURL forKey:@"requestURL"];
    }
    
    CFDictionarySetValue(connections, connection, targetInfo);
}

- (void) connection: (NSURLConnection *)connection didReceiveResponse: (NSHTTPURLResponse *)response
{
    NSMutableDictionary * targetInfo = (id)CFDictionaryGetValue(connections, connection);
    
    if(self.logXMLInOut) 
    {
        NSLog(@"ResponseStatus: %u\n", [response statusCode]);
		NSLog(@"ResponseHeaders:\n%@", [response allHeaderFields]);
	}
    
    [targetInfo setValue: response forKey: @"response"];
}

- (void) connection: (NSURLConnection *)connection didReceiveData: (NSData *)data
{
    NSMutableData * connectionData = (id)CFDictionaryGetValue(connectionsData, connection);
    [connectionData appendData: data];
}

- (void) connection: (NSURLConnection *)connection didFailWithError: (NSError *)error
{
	if (self.logXMLInOut) {
		NSLog(@"ResponseError:\n%@", error);
	}
    
    NSMutableDictionary * targetInfo = (id)CFDictionaryGetValue(connections, connection);
    [targetInfo setValue: error forKey: @"error"];
    [self _returnResponseForConnection: connection];
}

- (void) connectionDidFinishLoading: (NSURLConnection *)connection
{
    NSMutableDictionary *targetInfo =
    (id)CFDictionaryGetValue(connections, connection);
    
    // Determine what type of request is being dealt with
    NSURL *requestURL = nil;
    id object = [targetInfo objectForKey:@"requestURL"];
    if (object != nil && [object isKindOfClass:[NSURL class]])
    {
        requestURL = (NSURL *)object;
    }
    
    
    [self _returnResponseForConnection: connection];
}



- (void) _returnResponseForConnection: (NSURLConnection *)connection {
	NSMutableDictionary * targetInfo = (id)CFDictionaryGetValue(connections, connection);
	NSMutableData * data = (id)CFDictionaryGetValue(connectionsData, connection);
	
	if (self.logXMLInOut) {
		NSLog(@"ResponseBody:\n%@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
	}
	
	id target = [targetInfo valueForKey: @"target"];
	SEL selector;
	[[targetInfo valueForKey: @"selector"] getValue: &selector];
    
	NSError *error = nil;
	NSHTTPURLResponse * response = nil;
	id errorObject = [targetInfo valueForKey: @"error"];
	if (errorObject != [NSNull null] && [errorObject isKindOfClass:[NSError class]])
	{
		response = [targetInfo valueForKey: @"response"];
		NSInteger status = [response statusCode];
		if (status != 200) error = [NSError errorWithDomain: @"APIError" code: status userInfo: nil];
	}
    
	ZKElement *responseElement = nil;
	if ([data length] && [error code] != 401) {
		@try {
			responseElement = [self _processHttpResponse:response data:data];
		} @catch (NSException *exception) {
			error = [NSError errorWithDomain: @"XMLError" code: 199 userInfo: [NSDictionary dictionaryWithObject: exception forKey: @"exception"]];
		}
	}
	
    // In this case, a valid status code is returned meaning that the request was
    // received and processed.  But, the result of the processing may be a SOAP
    // Fault as defined by the service.  So we need to check every call to make sure
    // that a fault wasn't returned, and if one was, to throw the error passing the 
    // fault code and fault string
    // Checking for SOAP Fault here now?
	if ([responseElement childElement:@"faultcode"] != nil) {
		NSDictionary *errorDictionary = [[NSDictionary alloc] initWithObjectsAndKeys:[[responseElement childElement:@"faultcode"] stringValue],@"faultcode", [[responseElement childElement:@"faultstring"] stringValue], @"faultstring", nil];
		error = [NSError errorWithDomain:@"APIError" code:0 userInfo:errorDictionary];
	}
	
	id context = [targetInfo valueForKey:@"context"];
	if ([context isEqual: [NSNull null]])
		context = nil;
	
	[target performSelector:selector withObject:responseElement withObject:error withObject:context];
    
	CFDictionaryRemoveValue(connections, connection);
	CFDictionaryRemoveValue(connectionsData, connection);
}

- (void)_checkSession
{
    if ([sessionExpiry timeIntervalSinceNow] < 0)
		[self loginWithUsername:_username password:_password target:self selector:@selector(_sessionResumed:error:)];
}

- (void)_sessionResumed:(ZKLoginResult *)loginResult error:(NSError *)error
{
    if (error)
    {
        NSLog(@"There was an error resuming the session: %@", error);
    }
    else {
        NSLog(@"Session Resumed Successfully!");
    }
    
}



-(ZKElement *)_processHttpResponse:(NSHTTPURLResponse *)resp data:(NSData *)responseData
{
	ZKElement *root = [ZKParser parseData:responseData];
	if (root == nil)	
		@throw [NSException exceptionWithName:@"Xml error" reason:@"Unable to parse XML returned by server" userInfo:nil];
	if (![[root name] isEqualToString:@"Envelope"])
		@throw [NSException exceptionWithName:@"Xml error" reason:[NSString stringWithFormat:@"response XML not valid SOAP, root element should be Envelope, but was %@", [root name]] userInfo:nil];
	if (![[root namespace] isEqualToString:SOAP_NS])
		@throw [NSException exceptionWithName:@"Xml error" reason:[NSString stringWithFormat:@"response XML not valid SOAP, root namespace should be %@ but was %@", SOAP_NS, [root namespace]] userInfo:nil];
	ZKElement *body = [root childElement:@"Body" ns:SOAP_NS];
	if (resp.statusCode == 500) 
    {
		// I don't believe this will work.  With our API we occaisionally return
		// a 500, but not for operational errors such as bad username/password.  The 
		// body of the response is generally a web page (HTML) not soap
		ZKElement *fault = [body childElement:@"Fault" ns:SOAP_NS];
		if (fault == nil)
			@throw [NSException exceptionWithName:@"Xml error" reason:@"Fault status code returned, but unable to find soap:Fault element" userInfo:nil];
		NSString *fc = [[fault childElement:@"faultcode"] stringValue];
		NSString *fm = [[fault childElement:@"faultstring"] stringValue];
		@throw [ZKSoapException exceptionWithFaultCode:fc faultString:fm];
	} 
    
	return [[body childElements] objectAtIndex:0];
}

- (NSDictionary *)_contextWrapperDictionaryForTarget:(id)target selector:(SEL)selector context:(id)context
{
    NSValue *selectorValue = [NSValue value: &selector withObjCType: @encode(SEL)];
    return [NSDictionary dictionaryWithObjectsAndKeys:
            selectorValue, @"selector",
            target, @"target",
            context ? context: [NSNull null], @"context",
            nil];
}

- (void)_unwrapContext:(NSDictionary *)wrapperContext andCallSelectorWithResponse:(id)response error:(NSError *)error
{
    SEL selector;
    [[wrapperContext valueForKey: @"selector"] getValue: &selector];
    id target = [wrapperContext valueForKey:@"target"];
    id context = [wrapperContext valueForKey:@"context"];
    if ([context isEqual:[NSNull null]])
        context = nil;
    
    [target performSelector:selector withObject:response withObject:error withObject: context];
}



@end
