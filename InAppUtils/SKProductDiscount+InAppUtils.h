#import <StoreKit/StoreKit.h>

@interface SKProductDiscount (InAppUtils)
- (NSString *)paymentModeString;
- (NSString *)priceString;
- (NSString *)priceStringWithLocale:(NSLocale *)locale;
@end
