#import "SKProductDiscount+InAppUtils.h"

@implementation SKProductDiscount (InAppUtils)
- (NSString *)paymentModeString
{
    switch (self.paymentMode) {
        case SKProductDiscountPaymentModePayAsYouGo:
            return @"PayAsYouGo";
        case SKProductDiscountPaymentModePayUpFront:
            return @"PayUpFront";
        case SKProductDiscountPaymentModeFreeTrial:
            return @"FreeTrial";
    }
}

- (NSString *)priceString
{
    return [self priceStringWithLocale:self.priceLocale];
}

- (NSString *)priceStringWithLocale:(NSLocale *)locale
{
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.formatterBehavior = NSNumberFormatterBehavior10_4;
    formatter.numberStyle = NSNumberFormatterCurrencyStyle;
    formatter.locale = locale;
    
    return [formatter stringFromNumber:self.price];
}

@end
