//
//  Created by merowing on 08/10/2013.
//
//
//


#import <Foundation/Foundation.h>
#import "TestObjectProtocol.h"

@interface TestObject : NSObject <TestObjectProtocol>
@property(nonatomic, strong) NSURL *contentURL;
@property(nonatomic, strong) NSURL *videoURL;
@property(nonatomic, strong) id type;
@property(nonatomic, strong) NSString *title;
@property(nonatomic, strong) NSString *uniqueID;
@property(nonatomic, strong) NSNumber *number;
@property(nonatomic, assign) int intNumber;
@property(nonatomic, assign) float floatNumber;
@property(nonatomic, assign) BOOL isCheap;
@property(nonatomic, assign) BOOL isExpensive;

- (BOOL)updateFromDictionary:(NSDictionary *)dictionary;
- (id)passthroughMethod:(id)object;

@end