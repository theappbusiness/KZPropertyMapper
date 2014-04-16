//
//  Created by merowing on 29/04/2013.
//
//
//

#import "KZPropertyMapper.h"
#import <objc/message.h>
#import <CoreData/CoreData.h>
#import "KZPropertyDescriptor.h"
#import "KZPropertyMapperCommon.h"

@implementation KZPropertyMapper {
}

+ (BOOL)mapValuesFrom:(id)arrayOrDictionary toInstance:(id)instance usingMapping:(NSDictionary *)parameterMapping
{
  return [self mapValuesFrom:arrayOrDictionary toInstance:instance usingMapping:parameterMapping errors:nil];
}

+ (BOOL)mapValuesFrom:(id)arrayOrDictionary toInstance:(id)instance usingMapping:(NSDictionary *)parameterMapping errors:(__autoreleasing NSArray **)oErrors
{
  NSArray *errors = [self validateMapping:parameterMapping withValues:arrayOrDictionary];
  if (errors.count > 0) {
    if (oErrors) {
      *oErrors = errors;
    }
    return NO;
  }

  if ([arrayOrDictionary isKindOfClass:NSDictionary.class]) {
    return [self mapValuesFromDictionary:arrayOrDictionary toInstance:instance usingMapping:parameterMapping];
  }

  if ([arrayOrDictionary isKindOfClass:NSArray.class]) {
    return [self mapValuesFromArray:arrayOrDictionary toInstance:instance usingMapping:parameterMapping];
  }

  AssertTrueOrReturnNo([arrayOrDictionary isKindOfClass:NSArray.class] || [arrayOrDictionary isKindOfClass:NSDictionary.class]);
  return YES;
}

+ (BOOL)mapValuesFromDictionary:(NSDictionary *)sourceDictionary toInstance:(id)instance usingMapping:(NSDictionary *)parameterMapping
{
  AssertTrueOrReturnNo([sourceDictionary isKindOfClass:NSDictionary.class]);

  [sourceDictionary enumerateKeysAndObjectsUsingBlock:^(id property, id value, BOOL *stop) {
    id subMapping = [parameterMapping objectForKey:property];
    [self mapValue:value toInstance:instance usingMapping:subMapping sourcePropertyName:property];
  }];

  return YES;
}

+ (BOOL)mapValuesFromArray:(NSArray *)sourceArray toInstance:(id)instance usingMapping:(NSDictionary *)parameterMapping
{
  AssertTrueOrReturnNo([sourceArray isKindOfClass:NSArray.class]);

  [sourceArray enumerateObjectsUsingBlock:^(id value, NSUInteger idx, BOOL *stop) {
    NSNumber *key = @(idx);
    id subMapping = [parameterMapping objectForKey:key];
    [self mapValue:value toInstance:instance usingMapping:subMapping sourcePropertyName:[NSString stringWithFormat:@"Index %ld", (long)key.integerValue]];
  }];
  return YES;
}

+ (void)mapValue:(id)value toInstance:(id)instance usingMapping:(id)mapping sourcePropertyName:(NSString *)propertyName
{
  if ([value isKindOfClass:NSNull.class]) {
    value = nil;
  }

  if ([mapping isKindOfClass:NSDictionary.class] || [mapping isKindOfClass:NSArray.class]) {
    if ([value isKindOfClass:NSDictionary.class] || [value isKindOfClass:NSArray.class]) {
      [self mapValuesFrom:value toInstance:instance usingMapping:mapping];
    } else if (_shouldLogIgnoredValues) {
      NSLog(@"KZPropertyMapper: Ignoring property %@ as it's not in mapping dictionary", propertyName);
    }
    return;
  }

  if (!mapping) {
    if (_shouldLogIgnoredValues) {
      NSLog(@"KZPropertyMapper: Ignoring value at index %@ as it's not mapped", propertyName);
    }
    return;
  }

  [self mapValue:value toInstance:instance usingMapping:mapping];
}

+ (BOOL)mapValue:(id)value toInstance:(id)instance usingMapping:(id)mapping
{
  if ([mapping isKindOfClass:KZPropertyDescriptor.class]) {
    return [self mapValue:value toInstance:(id)instance usingDescriptor:(KZPropertyDescriptor *)mapping];
  }

  return [self mapValue:value toInstance:instance usingStringMapping:mapping];

}

+ (BOOL)mapValue:(id)value toInstance:(id)instance usingStringMapping:(NSString *)mapping
{
  AssertTrueOrReturnNo([mapping isKindOfClass:NSString.class]);

  BOOL isBoxedMapping = [mapping hasPrefix:@"@"];
  BOOL isListOfMappings = [mapping rangeOfString:@"&"].location != NSNotFound;
  
  if (!isBoxedMapping && !isListOfMappings) {
    //! normal 1 : 1 mapping
    [self setValue:value withMapping:mapping onInstance:instance];
    return YES;
  }

  if (isListOfMappings) {
    //! List of mappings
    BOOL parseResult = YES;
    NSArray *stringMappings = [mapping componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"&"]];
    for (NSString *innerMapping in stringMappings) {
      NSString *wipedInnerMapping = [innerMapping stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      parseResult = [self mapValue:value toInstance:instance usingStringMapping:wipedInnerMapping] && parseResult;
    }
    return parseResult;
  }

  //! Single boxing
  NSArray *components = [mapping componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"@()"]];
  AssertTrueOrReturnNo(components.count == 4);

  NSString *mappingType = [components objectAtIndex:1];
  NSString *boxingParametersString = [components objectAtIndex:2];

  //! extract and cleanup params
  NSArray *boxingParameters = [boxingParametersString componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];

  NSMutableArray *boxingParametersProcessed = [NSMutableArray new];
  [boxingParameters enumerateObjectsUsingBlock:^(NSString *param, NSUInteger idx, BOOL *stop) {
    [boxingParametersProcessed addObject:[param stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
  }];
  boxingParameters = [boxingParametersProcessed copy];

  NSString *targetProperty = [boxingParameters lastObject];
  boxingParameters = [boxingParameters subarrayWithRange:NSMakeRange(0, boxingParameters.count - 1)];

  //! We need to handle multiple params boxing as well as normal one
  id boxedValue = nil;
  if (boxingParameters.count > 0) {
    SEL mappingSelector = NSSelectorFromString([NSString stringWithFormat:@"boxValueAs%@OnTarget:value:params:", mappingType]);
    AssertTrueOrReturnNoBlock([self respondsToSelector:mappingSelector], ^(NSError *error) {
    });
    id (*objc_msgSendTyped)(id, SEL, id, id, NSArray *) = (void *)objc_msgSend;
    boxingParameters = [boxingParameters arrayByAddingObject:targetProperty];
    boxedValue = objc_msgSendTyped(self, mappingSelector, instance, value, boxingParameters);
  } else {
    SEL mappingSelector = NSSelectorFromString([NSString stringWithFormat:@"boxValueAs%@:", mappingType]);
    AssertTrueOrReturnNoBlock([self respondsToSelector:mappingSelector], ^(NSError *error) {
    });
    id (*objc_msgSendTyped)(id, SEL, id) = (void *)objc_msgSend;
    boxedValue = objc_msgSendTyped(self, mappingSelector, value);
  }

  if (!boxedValue) {
    return NO;
  }
  [self setValue:boxedValue withMapping:targetProperty onInstance:instance];
  return YES;
}

+ (BOOL)mapValue:(id)value toInstance:(id)instance usingDescriptor:(KZPropertyDescriptor *)descriptor
{
  NSArray *errors = [descriptor validateValue:value];
  if (errors.count > 0) {
    return NO;
  }

  [self mapValue:value toInstance:instance usingStringMapping:descriptor.stringMapping];
  return YES;
}

+ (void)setValue:(id)value withMapping:(NSString *)mapping onInstance:(id)instance
{
  if (![self mapping:mapping forInstance:instance matchesTypeOfObject:value]) {
    return;
  }
  
  Class coreDataBaseClass = NSClassFromString(@"NSManagedObject");
  if (coreDataBaseClass != nil && [instance isKindOfClass:coreDataBaseClass] &&
      [[((NSManagedObject *)instance).entity propertiesByName] valueForKey:mapping]) {
    [instance willChangeValueForKey:mapping];
    void (*objc_msgSendTyped)(id, SEL, id, NSString*) = (void *)objc_msgSend;
    objc_msgSendTyped(instance, NSSelectorFromString(@"setPrimitiveValue:forKey:"), value, mapping);
    [instance didChangeValueForKey:mapping];
  } else {
    [instance setValue:value forKeyPath:mapping];
  }
}

+ (BOOL)mapping:(NSString *)mapping forInstance:(id)instance matchesTypeOfObject:(id)object
{
  objc_property_t theProperty = class_getProperty([instance class], [mapping UTF8String]);
  if (!theProperty) {
    return YES; // This keeps default behaviour of KZPropertyMapper
  }
  
  NSString *propertyEncoding = [NSString stringWithUTF8String:property_getAttributes(theProperty)];
  NSArray *encodings = [propertyEncoding componentsSeparatedByString:@","];
  NSString *fullTypeEncoding = [encodings firstObject];
  NSString *typeEncoding = [fullTypeEncoding substringFromIndex:1];
  const char *cTypeEncoding = [typeEncoding substringToIndex:1].UTF8String;
  
  if (strcmp(cTypeEncoding, @encode(id)) != 0) {
    return YES; // This keeps default behaviour of KZPropertyMapper
  }
  
  if ([typeEncoding isEqual:@"@"] || typeEncoding.length < 3) {
    return YES; // Looks like it is "id" so, should be fine
  }
  
  NSString *className = [typeEncoding substringWithRange:NSMakeRange(2, typeEncoding.length - 3)];
  Class propertyClass = NSClassFromString(className);
  BOOL isSameTypeObject = ([object isKindOfClass:propertyClass]);
  
  if (_shouldLogIgnoredValues && !isSameTypeObject) {
    NSLog(@"KZPropertyMapper: Ignoring value at index %@ as it's not mapped", mapping);
  }
  return isSameTypeObject;
}

#pragma mark - Validation

+ (NSArray *)validateMapping:(NSDictionary *)mapping withValues:(id)values
{
  AssertTrueOrReturnErrors([mapping isKindOfClass:NSDictionary.class]);

  if (!values || [values isKindOfClass:NSDictionary.class]) {
    return [self validateMapping:mapping withValuesDictionary:values];
  } else if ([values isKindOfClass:NSArray.class]) {
    return [self validateMapping:mapping withValuesArray:values];
  }
  if (_shouldLogIgnoredValues) {
    NSLog(@"KZPropertyMapper: Ignoring value at index %@ as it's not mapped", mapping);
  }
  return nil;
}

+ (NSArray *)validateMapping:(NSDictionary *)mapping withValuesArray:(NSArray *)values
{
  AssertTrueOrReturnNil([values isKindOfClass:NSArray.class]);
  
  NSMutableArray *errors = [NSMutableArray new];
  [mapping enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, id obj, BOOL *stop) {
    AssertTrueOrReturn([key isKindOfClass:NSNumber.class]);
    
    NSUInteger itemIndex = key.unsignedIntValue;
    if (itemIndex >= values.count) {
      if (_shouldLogIgnoredValues) {
        NSLog(@"KZPropertyMapper: Ignoring value at index %@ as it's not mapped", key);
      }
      return;
    }
    
    id value = [values objectAtIndex:itemIndex];
    
    //! submapping
    if ([obj isKindOfClass:NSArray.class] || [obj isKindOfClass:NSDictionary.class]) {
      NSArray *validationErrors = [self validateMapping:obj withValues:value];
      if (validationErrors) {
        [errors addObjectsFromArray:validationErrors];
      }
    }

    if ([obj isKindOfClass:KZPropertyDescriptor.class]) {
      KZPropertyDescriptor *descriptor = obj;
      NSArray *validationErrors = [descriptor validateValue:value];
      if (validationErrors.count > 0) {
        [errors addObjectsFromArray:validationErrors];
      }
    }
  }];

  return errors;
}

+ (NSArray *)validateMapping:(NSDictionary *)mapping withValuesDictionary:(NSDictionary *)values
{
  NSMutableArray *errors = [NSMutableArray new];
  [mapping enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
    id value = [values objectForKey:key];
    if ([value isKindOfClass:NSNull.class]) {
      value = nil;
    }
    
    //! submapping
    if ([obj isKindOfClass:NSArray.class] || [obj isKindOfClass:NSDictionary.class]) {
      NSArray *validationErrors = [self validateMapping:obj withValues:value];
      if (validationErrors) {
        [errors addObjectsFromArray:validationErrors];
      }
    }

    if ([obj isKindOfClass:KZPropertyDescriptor.class]) {
      KZPropertyDescriptor *descriptor = obj;
      NSArray *validationErrors = [descriptor validateValue:value];
      if (validationErrors.count > 0) {
        [errors addObjectsFromArray:validationErrors];
      }
    }
  }];

  return errors;
}

#pragma mark - Logging configuration

#ifdef KZPropertyMapperLogIgnoredValues
static BOOL _shouldLogIgnoredValues = KZPropertyMapperLogIgnoredValues;
#else
static BOOL _shouldLogIgnoredValues = YES;
#endif

+ (void)logIgnoredValues:(BOOL)logIgnoredValues
{
  _shouldLogIgnoredValues = logIgnoredValues;
}


#pragma mark - Dynamic boxing

+ (NSURL *)boxValueAsURL:(id)value __unused
{
  if (value == nil) {
    return nil;
  }
  AssertTrueOrReturnNil([value isKindOfClass:NSString.class]);
  return [NSURL URLWithString:value];
}

+ (NSDate *)boxValueAsDate:(id)value __unused
{
  if (value == nil) {
    return nil;
  }
  AssertTrueOrReturnNil([value isKindOfClass:NSString.class]);
  return [[self dateFormatter] dateFromString:value];
}

+ (NSDateFormatter *)dateFormatter
{
  static NSDateFormatter *df = nil;
  if (df == nil) {
    df = [[NSDateFormatter alloc] init];
    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    [df setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
    [df setLocale:locale];
    [df setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
  }
  return df;
}

+ (id)boxValueAsSelectorOnTarget:(id)target value:(id)value params:(NSArray *)params __unused
{
  AssertTrueOrReturnNil(params.count == 2);
  NSString *selectorName = [params objectAtIndex:0];
  NSString *targetPropertyName = [params objectAtIndex:1];
  NSArray *selectorComponents = [selectorName componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
  SEL selector = NSSelectorFromString(selectorName);
  
  AssertTrueOrReturnNil([target respondsToSelector:selector]);
  if(selectorComponents.count > 2){
    id (*objc_msgSendTyped)(id, SEL, id, NSString*) = (void *)objc_msgSend;
    return objc_msgSendTyped(target, selector, value, targetPropertyName);
  }
  id (*objc_msgSendTyped)(id, SEL, id) = (void *)objc_msgSend;
  return objc_msgSendTyped(target, selector, value);
}
@end

